import 'package:dio/dio.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/offline_mode.dart';
import '../domain/music_mode.dart';
import 'original_music_catalog.dart';

/// Catálogo público de Mysic (búsqueda, artistas y álbumes). Ninguna de estas
/// consultas lleva sesión ni credenciales: sirven con cualquier cuenta.
class PublicCatalogClient {
  PublicCatalogClient(this._owns, {Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: 'https://myslc.duckdns.org/api/',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: false,
      validateStatus: (status) => status != null,
      headers: {'Accept': 'application/json'},
    );
    // Con «solo canciones descargadas» ninguna petición sale.
    _dio.interceptors.add(OfflineMode.dioGuard);
  }

  final bool Function() _owns;
  final Dio _dio;
  bool _closed = false;

  bool get _active => !_closed && _owns();

  void _checkOwner() {
    if (!_active) throw const ApiFailure('Cambió la cuenta de Mysic.');
  }

  Future<Response<dynamic>> _request(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    _checkOwner();
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        cancelToken: cancelToken,
      );
      _checkOwner();
      final status = response.statusCode!;
      if (status == 410) {
        throw const ApiFailure(
          'Actualiza la lista para seguir.',
          code: 'CURSOR_EXPIRED',
        );
      }
      if (status == 404 || status == 405) {
        throw ApiFailure(
          'El catálogo de Mysic no ofrece esta sección.',
          statusCode: status,
          code: 'CATALOG_ROUTE',
        );
      }
      if (status == 429) {
        throw const ApiFailure(
          'El catálogo de Mysic recibió demasiadas consultas. Reintenta más tarde.',
          code: 'TOO_MANY_REQUESTS',
        );
      }
      if (status < 200 ||
          status >= 300 ||
          response.data is! Map<String, dynamic>) {
        throw const ApiFailure(
          'El catálogo de Mysic no pudo entregar los datos. Reintenta en unos momentos.',
          code: 'CATALOG_SERVICE',
        );
      }
      return response;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const ApiFailure(
        'No se pudo conectar con el catálogo de Mysic.',
        code: 'CATALOG_NETWORK',
      );
    }
  }

  /// Búsqueda pública por tipo: "song", "artist" o "album".
  Future<MusicPage> search(
    String query,
    String type, {
    CancelToken? cancelToken,
  }) async {
    assert(type == 'song' || type == 'artist' || type == 'album');
    final response = await _request(
      'youtube/search',
      query: {'q': query, 'type': type},
      cancelToken: cancelToken,
    );
    final data = response.data as Map<String, dynamic>;
    if (data['type'] != type || data['items'] is! List) {
      throw const ApiFailure(
        'El catálogo musical no está disponible.',
        code: 'MUSIC_SEARCH_UNAVAILABLE',
      );
    }
    return MusicPage(
      OriginalMusicCatalog.rows(data['items'], type),
      null,
      null,
      0,
    );
  }

  Future<MusicPage> publicSongs(String query, CancelToken? cancelToken) =>
      search(query, 'song', cancelToken: cancelToken);

  Future<MusicPage> searchCatalog(
    String query,
    String type, {
    CancelToken? cancelToken,
  }) {
    assert(type == 'artist' || type == 'album');
    return search(query, type, cancelToken: cancelToken);
  }

  Future<ArtistProfile> artistPage(
    String id, {
    CancelToken? cancelToken,
  }) async {
    if (!OriginalMusicCatalog.isArtistId(id)) {
      throw const ApiFailure('El identificador del artista no es válido.');
    }
    final response = await _request(
      'youtube/artist/$id',
      cancelToken: cancelToken,
    );
    return OriginalMusicCatalog.artistProfile(
      response.data as Map<String, dynamic>,
    );
  }

  /// Todas las canciones del artista («Ver todo» de Canciones destacadas).
  Future<List<MusicTrack>> artistSongs(
    String id, {
    CancelToken? cancelToken,
  }) async {
    if (!OriginalMusicCatalog.isArtistId(id)) {
      throw const ApiFailure('El identificador del artista no es válido.');
    }
    final response = await _request(
      'youtube/artist/$id/songs',
      cancelToken: cancelToken,
    );
    return OriginalMusicCatalog.artistSongs(
      response.data as Map<String, dynamic>,
    );
  }

  /// La discografía completa del artista, por estantes (Álbumes, Sencillos y
  /// EP…): «Ver todo» de cada uno.
  Future<List<({String title, List<MusicItem> items})>> artistReleases(
    String id, {
    CancelToken? cancelToken,
  }) async {
    if (!OriginalMusicCatalog.isArtistId(id)) {
      throw const ApiFailure('El identificador del artista no es válido.');
    }
    final response = await _request(
      'youtube/artist/$id/releases',
      cancelToken: cancelToken,
    );
    return OriginalMusicCatalog.artistReleases(
      response.data as Map<String, dynamic>,
    );
  }

  Future<AlbumDetail> albumPage(String id, {CancelToken? cancelToken}) async {
    if (!OriginalMusicCatalog.isAlbumId(id)) {
      throw const ApiFailure('El identificador del álbum no es válido.');
    }
    final response = await _request(
      'youtube/album/$id',
      cancelToken: cancelToken,
    );
    return OriginalMusicCatalog.albumDetail(
      response.data as Map<String, dynamic>,
    );
  }

  /// Resuelve el artista y el álbum de una canción que llegó sin enlaces (las
  /// canciones del canal no los traen) buscándola en el catálogo público.
  /// Solo se acepta la coincidencia exacta del vídeo para el álbum; para el
  /// artista basta otra pista del mismo nombre.
  Future<TrackLinks> resolveLinks({
    required String videoId,
    required String title,
    required String artist,
    CancelToken? cancelToken,
  }) async {
    final response = await _request(
      'youtube/search',
      query: {'q': '$title $artist', 'type': 'song'},
      cancelToken: cancelToken,
    );
    final rows = response.data['items'];
    if (rows is! List) return (artistId: null, albumId: null, album: null);
    String? artistId, albumId, album;
    String? valid(Object? value, RegExp pattern) =>
        value is String && pattern.hasMatch(value) ? value : null;
    for (final row in rows) {
      if (row is! Map) continue;
      final exact = row['id'] == videoId;
      final sameArtist =
          row['artist'] is String &&
          (row['artist'] as String).toLowerCase() == artist.toLowerCase();
      if (!exact && !sameArtist) continue;
      artistId ??= valid(row['artistId'], RegExp(r'^UC[A-Za-z0-9_-]{22}$'));
      if (exact) {
        albumId = valid(row['albumId'], RegExp(r'^MPREb_[A-Za-z0-9_-]{6,60}$'));
        final name = row['album'];
        if (albumId != null && name is String && name.trim().isNotEmpty) {
          album = name.trim();
        }
        artistId =
            valid(row['artistId'], RegExp(r'^UC[A-Za-z0-9_-]{22}$')) ??
            artistId;
        break;
      }
    }
    return (artistId: artistId, albumId: albumId, album: album);
  }

  void close() {
    _closed = true;
    _dio.close(force: true);
  }
}
