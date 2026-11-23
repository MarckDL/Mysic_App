import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/network/api_failure.dart';
import '../../../core/network/offline_mode.dart';
import '../../connected_library/domain/music_mode.dart';
import 'ytm_parser.dart';
import 'ytm_session.dart';

/// Nombre y foto de la cuenta con la sesión iniciada.
class YtmAccount {
  const YtmAccount({required this.name, this.handle, this.photoUrl});

  final String name;
  final String? handle;
  final String? photoUrl;
}

/// Habla directo con YouTube Music desde el teléfono, con la cookie de la
/// sesión. No pasa por ningún servidor de Mysic.
class YtmClient {
  YtmClient(this.session, {Dio? dio, DateTime Function()? clock})
    : _dio = dio ?? Dio(),
      _clock = clock ?? DateTime.now {
    _dio.options = BaseOptions(
      baseUrl: 'https://music.youtube.com/youtubei/v1/',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      validateStatus: (status) => status != null,
    );
    // Con «solo canciones descargadas» ninguna petición sale.
    _dio.interceptors.add(OfflineMode.dioGuard);
  }

  static const origin = 'https://music.youtube.com';

  final YtmSession session;
  final Dio _dio;
  final DateTime Function() _clock;

  /// La vista de la aplicación web de YouTube Music: usa la fecha de hoy
  /// porque YouTube acepta cualquier versión reciente.
  String get _clientVersion {
    final now = _clock().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '1.${now.year}${two(now.month)}${two(now.day)}.01.00';
  }

  static const _browseIds = {
    MusicSurface.home: 'FEmusic_home',
    MusicSurface.songs: 'FEmusic_liked_videos',
    MusicSurface.liked: 'VLLM',
    MusicSurface.channelLiked: 'VLLM',
    MusicSurface.playlists: 'FEmusic_liked_playlists',
    MusicSurface.albums: 'FEmusic_liked_albums',
    MusicSurface.artists: 'FEmusic_library_corpus_artists',
  };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
    Map<String, dynamic>? query,
  }) async {
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        path,
        queryParameters: {'prettyPrint': 'false', ...?query},
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Origin': origin,
            'X-Origin': origin,
            'X-Goog-AuthUser': '0',
            'Authorization': session.authorization(origin, now: _clock()),
            'Cookie': session.cookie,
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) '
                'Gecko/20100101 Firefox/128.0',
          },
        ),
        data: {
          'context': {
            'user': const <String, dynamic>{},
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': _clientVersion,
              'hl': 'es',
            },
          },
          ...body,
        },
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const ApiFailure(
        'No se pudo conectar con YouTube Music.',
        code: 'MUSIC_NETWORK',
      );
    }
    final status = response.statusCode ?? 0;
    debugPrint('ytm_request path=$path status=$status');
    if (status == 401 || status == 403) {
      throw const ApiFailure(
        'YouTube Music cerró la sesión. Inicia sesión de nuevo.',
        statusCode: 401,
        code: 'MUSIC_ACCESS_DENIED',
      );
    }
    if (status == 404) {
      throw const ApiFailure(
        'La playlist ya no está disponible en esta cuenta.',
        statusCode: 404,
        code: 'MUSIC_PLAYLIST_NOT_FOUND',
      );
    }
    if (status == 429) {
      throw const ApiFailure(
        'YouTube Music recibió demasiadas consultas. Reintenta más tarde.',
        code: 'TOO_MANY_REQUESTS',
      );
    }
    final data = response.data;
    if (status < 200 || status >= 300 || data is! Map<String, dynamic>) {
      throw const ApiFailure(
        'YouTube Music no pudo entregar los datos. Reintenta en unos momentos.',
        code: 'MUSIC_CATALOG_RESPONSE',
      );
    }
    return data;
  }

  /// La cuenta con la sesión iniciada, o un fallo si la sesión ya no vale.
  Future<YtmAccount> account({CancelToken? cancelToken}) async {
    final data = await _post(
      'account/account_menu',
      const {},
      cancelToken: cancelToken,
    );
    if (ytmLoggedOut(data)) {
      throw const ApiFailure(
        'Inicia sesión de nuevo en YouTube Music.',
        statusCode: 401,
        code: 'MUSIC_ACCESS_DENIED',
      );
    }
    Map<String, dynamic> obj(Object? v) =>
        v is Map<String, dynamic> ? v : const {};
    String text(Object? v) {
      final o = obj(v);
      if (o['simpleText'] is String) return o['simpleText'] as String;
      final runs = o['runs'];
      return runs is List
          ? runs
                .map((r) => obj(r)['text'] is String ? obj(r)['text'] : '')
                .join()
          : '';
    }

    final actions = data['actions'];
    final header = actions is List && actions.isNotEmpty
        ? obj(
            obj(
              obj(
                obj(obj(actions.first)['openPopupAction'])['popup'],
              )['multiPageMenuRenderer'],
            )['header'],
          )['activeAccountHeaderRenderer']
        : null;
    final account = obj(header);
    final photos = obj(account['accountPhoto'])['thumbnails'];
    final photo = photos is List && photos.isNotEmpty
        ? obj(photos.last)['url']
        : null;
    final name = text(account['accountName']).trim();
    if (name.isEmpty) {
      debugPrint(
        'ytm_account_empty keys=${data.keys.toList()} '
        'actions=${actions is List ? actions.length : actions.runtimeType}',
      );
      throw const ApiFailure(
        'Inicia sesión de nuevo en YouTube Music.',
        statusCode: 401,
        code: 'MUSIC_ACCESS_DENIED',
      );
    }
    final handle = text(account['channelHandle']).trim();
    return YtmAccount(
      name: name,
      handle: handle.isEmpty ? null : handle,
      photoUrl: photo is String && photo.startsWith('https://') ? photo : null,
    );
  }

  /// Una página de [surface]. [cursor] es el token de continuación de la
  /// página anterior; [params] elige el ambiente del Inicio (Relax, Entreno…).
  Future<MusicPage> page(
    MusicSurface surface, {
    String? playlistId,
    String? cursor,
    String? params,
    CancelToken? cancelToken,
  }) async => MusicPage.fromJson(
    await pageJson(
      surface,
      playlistId: playlistId,
      cursor: cursor,
      params: params,
      cancelToken: cancelToken,
    ),
  );

  /// Lo mismo que [page], con el JSON que entiende MusicPage.fromJson, para
  /// poder guardarlo en disco.
  Future<Map<String, dynamic>> pageJson(
    MusicSurface surface, {
    String? playlistId,
    String? cursor,
    String? params,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> body;
    if (cursor != null) {
      body = {'continuation': cursor};
    } else {
      final id = switch (surface) {
        MusicSurface.playlist when playlistId != null => 'VL$playlistId',
        MusicSurface.album => playlistId,
        MusicSurface.artist => playlistId,
        _ => _browseIds[surface],
      };
      if (id == null || !RegExp(r'^[\w-]{1,150}$').hasMatch(id)) {
        throw const ApiFailure(
          'Esta sección no está disponible en YouTube Music.',
          code: 'MUSIC_CATALOG_ROUTE',
        );
      }
      body = {'browseId': id, if (params != null) 'params': params};
    }
    // Las continuaciones llevan su token también en la dirección, como la web.
    final data = await _post(
      'browse',
      body,
      cancelToken: cancelToken,
      query: cursor == null
          ? null
          : {'ctoken': cursor, 'continuation': cursor, 'type': 'next'},
    );
    final parsed = parseYtmPage(
      data,
      surface == MusicSurface.channelLiked ? 'liked' : surface.name,
      continuation: cursor != null,
    );
    return parsed.toJson();
  }

  /// La radio de [videoId] (`RDAMVM<id>`): canciones parecidas que YouTube Music
  /// propone, y un token para pedir más ([cursor], de la respuesta anterior).
  Future<YtmRadioPage> radio(
    String videoId, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw const ApiFailure('La canción no es válida.');
    }
    final Map<String, dynamic> body = cursor != null
        ? {'continuation': cursor}
        : {
            'videoId': videoId,
            'playlistId': 'RDAMVM$videoId',
            // La radio de la canción, solo audio.
            'params': 'wAEB',
            'isAudioOnly': true,
            'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
          };
    final data = await _post(
      'next',
      body,
      cancelToken: cancelToken,
      query: cursor == null
          ? null
          : {'ctoken': cursor, 'continuation': cursor, 'type': 'next'},
    );
    return parseYtmRadio(data);
  }

  /// Filtros de `search`, los de la web de YouTube Music.
  static const searchFilters = {
    'songs': 'EgWKAQIIAWoKEAkQBRAKEAMQBA==',
    'videos': 'EgWKAQIQAWoKEAkQChAFEAMQBA==',
    'albums': 'EgWKAQIYAWoKEAkQChAFEAMQBA==',
    'artists': 'EgWKAQIgAWoKEAkQChAFEAMQBA==',
    'playlists': 'EgeKAQQoAEABagoQAxAEEAoQCRAF',
  };

  /// Busca [query]. Sin [filter] devuelve el resultado principal y filas de
  /// todos los tipos; con una clave de [searchFilters], solo ese tipo.
  Future<YtmSearchPage> search(
    String query, {
    String? filter,
    CancelToken? cancelToken,
  }) async {
    final params = filter == null ? null : searchFilters[filter];
    if (filter != null && params == null) {
      throw const ApiFailure('El filtro de búsqueda no es válido.');
    }
    return parseYtmSearch(
      await _post('search', {
        'query': query,
        'params': ?params,
      }, cancelToken: cancelToken),
      filtered: filter != null,
    );
  }

  /// Sugerencias para lo que se lleva escrito.
  Future<YtmSuggestions> suggestions(
    String input, {
    CancelToken? cancelToken,
  }) async => parseYtmSuggestions(
    await _post('music/get_search_suggestions', {
      'input': input,
    }, cancelToken: cancelToken),
  );

  /// Las secciones de «Ambientes y géneros» con sus botones.
  Future<List<Map<String, dynamic>>> moods({CancelToken? cancelToken}) async =>
      parseYtmMoods(
        await _post('browse', const {
          'browseId': 'FEmusic_moods_and_genres',
        }, cancelToken: cancelToken),
      );

  /// La página de un ambiente o género ([params] viene de [moods]), con el
  /// JSON de `MusicPage.fromJson`; cada elemento lleva el título de su sección.
  Future<Map<String, dynamic>> moodPageJson(
    String params, {
    CancelToken? cancelToken,
  }) async {
    if (!RegExp(r'^[\w%=-]{1,300}$').hasMatch(params)) {
      throw const ApiFailure('La categoría no es válida.');
    }
    return parseYtmPage(
      await _post('browse', {
        'browseId': 'FEmusic_moods_and_genres_category',
        'params': params,
      }, cancelToken: cancelToken),
      'mood',
    ).toJson();
  }

  /// Marca ([liked]) o desmarca una canción con Me gusta en YouTube Music.
  Future<void> rate(String videoId, {required bool liked}) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw const ApiFailure('La canción no es válida.');
    }
    await _post(liked ? 'like/like' : 'like/removelike', {
      'target': {'videoId': videoId},
    });
  }

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _playlistId = RegExp(r'^[A-Za-z0-9_-]{2,120}$');
  static final _channelId = RegExp(r'^UC[A-Za-z0-9_-]{22}$');

  static void _require(bool ok, String message) {
    if (!ok) throw ApiFailure(message);
  }

  /// YouTube contesta 200 también cuando rechaza un cambio: lo dice en
  /// `status`.
  static void _succeeded(Map<String, dynamic> data) {
    if (data['status'] == 'STATUS_FAILED') {
      throw const ApiFailure(
        'YouTube Music no aceptó el cambio.',
        code: 'MUSIC_EDIT_REFUSED',
      );
    }
  }

  /// Marca ([disliked]) o quita el No me gusta de una canción.
  Future<void> dislike(String videoId, {required bool disliked}) async {
    _require(_videoId.hasMatch(videoId), 'La canción no es válida.');
    await _post(disliked ? 'like/dislike' : 'like/removelike', {
      'target': {'videoId': videoId},
    });
  }

  /// Añade canciones al final de una playlist de la cuenta.
  Future<void> addToPlaylist(String playlistId, List<String> videoIds) async {
    _require(_playlistId.hasMatch(playlistId), 'La playlist no es válida.');
    _require(
      videoIds.isNotEmpty && videoIds.every(_videoId.hasMatch),
      'Las canciones no son válidas.',
    );
    _succeeded(
      await _post('browse/edit_playlist', {
        'playlistId': playlistId,
        'actions': [
          for (final id in videoIds)
            {'action': 'ACTION_ADD_VIDEO', 'addedVideoId': id},
        ],
      }),
    );
  }

  /// Quita de una playlist propia la entrada [entryId] (la de esa fila, no
  /// todas las apariciones de la canción).
  Future<void> removeFromPlaylist(
    String playlistId,
    String videoId,
    String entryId,
  ) async {
    _require(_playlistId.hasMatch(playlistId), 'La playlist no es válida.');
    _require(
      _videoId.hasMatch(videoId) && RegExp(r'^[\w-]{1,64}$').hasMatch(entryId),
      'La canción no es válida.',
    );
    _succeeded(
      await _post('browse/edit_playlist', {
        'playlistId': playlistId,
        'actions': [
          {
            'action': 'ACTION_REMOVE_VIDEO',
            'removedVideoId': videoId,
            'setVideoId': entryId,
          },
        ],
      }),
    );
  }

  /// Crea una playlist (privada salvo que se diga otra cosa) con [videoIds] y
  /// devuelve su id.
  Future<String> createPlaylist(
    String title, {
    List<String> videoIds = const [],
    String privacy = 'PRIVATE',
  }) async {
    final name = title.trim();
    _require(name.isNotEmpty && name.length <= 150, 'El nombre no es válido.');
    _require(
      videoIds.every(_videoId.hasMatch),
      'Las canciones no son válidas.',
    );
    final data = await _post('playlist/create', {
      'title': name,
      'privacyStatus': privacy,
      if (videoIds.isNotEmpty) 'videoIds': videoIds,
    });
    final id = data['playlistId'];
    if (id is! String || !_playlistId.hasMatch(id)) {
      throw const ApiFailure(
        'YouTube Music no creó la playlist.',
        code: 'MUSIC_EDIT_REFUSED',
      );
    }
    return id;
  }

  /// Cambia el nombre, la descripción o la privacidad (`PRIVATE`, `UNLISTED`,
  /// `PUBLIC`) de una playlist propia; lo que va a null no se toca.
  Future<void> editPlaylist(
    String playlistId, {
    String? title,
    String? description,
    String? privacy,
  }) async {
    _require(_playlistId.hasMatch(playlistId), 'La playlist no es válida.');
    _require(
      privacy == null ||
          const {'PRIVATE', 'UNLISTED', 'PUBLIC'}.contains(privacy),
      'La privacidad no es válida.',
    );
    final actions = [
      if (title != null)
        {'action': 'ACTION_SET_PLAYLIST_NAME', 'playlistName': title.trim()},
      if (description != null)
        {
          'action': 'ACTION_SET_PLAYLIST_DESCRIPTION',
          'playlistDescription': description,
        },
      if (privacy != null)
        {'action': 'ACTION_SET_PLAYLIST_PRIVACY', 'playlistPrivacy': privacy},
    ];
    if (actions.isEmpty) return;
    _succeeded(
      await _post('browse/edit_playlist', {
        'playlistId': playlistId,
        'actions': actions,
      }),
    );
  }

  /// Si el álbum [browseId] (`MPREb_…`) está en la biblioteca y con qué
  /// playlist se guarda.
  Future<YtmAlbumLibrary> albumLibrary(String browseId) async {
    _require(
      RegExp(r'^MPREb_[A-Za-z0-9_-]{6,60}$').hasMatch(browseId),
      'El álbum no es válido.',
    );
    return parseYtmAlbumLibrary(await _post('browse', {'browseId': browseId}));
  }

  /// Guarda ([saved]) o quita de la biblioteca la playlist o el álbum
  /// [playlistId] (para un álbum, su playlist de audio `OLAK5uy_…`).
  Future<void> saveToLibrary(String playlistId, {required bool saved}) async {
    _require(_playlistId.hasMatch(playlistId), 'La playlist no es válida.');
    final id = playlistId.replaceFirst(RegExp('^VL'), '');
    await _post(saved ? 'like/like' : 'like/removelike', {
      'target': {'playlistId': id},
    });
  }

  /// Elimina una playlist propia.
  Future<void> deletePlaylist(String playlistId) async {
    _require(_playlistId.hasMatch(playlistId), 'La playlist no es válida.');
    _succeeded(await _post('playlist/delete', {'playlistId': playlistId}));
  }

  /// Sigue ([followed]) o deja de seguir a un artista.
  Future<void> follow(String channelId, {required bool followed}) async {
    _require(_channelId.hasMatch(channelId), 'El artista no es válido.');
    await _post(
      followed ? 'subscription/subscribe' : 'subscription/unsubscribe',
      {
        'channelIds': [channelId],
      },
    );
  }

  /// La radio de una playlist o de un álbum (`RDAMPL<id>`).
  Future<YtmRadioPage> playlistRadio(String playlistId) async {
    _require(_playlistId.hasMatch(playlistId), 'La playlist no es válida.');
    return parseYtmRadio(
      await _post('next', {
        'playlistId': playlistId.startsWith('RD')
            ? playlistId
            : 'RDAMPL$playlistId',
        'params': 'wAEB',
        'isAudioOnly': true,
      }),
    );
  }

  void close() => _dio.close(force: true);
}
