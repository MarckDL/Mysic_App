import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/network/api_failure.dart';
import '../../history/data/local_listens.dart';
import '../../ytm/data/ytm_auth_repository.dart';
import '../../ytm/data/ytm_client.dart';
import '../domain/music_mode.dart';
import '../domain/music_search.dart';
import 'music_boot_cache.dart';
import 'public_catalog_client.dart';

/// Lo que la app muestra de música. Nada pasa por un servidor propio: las
/// pantallas de la cuenta salen de YouTube Music con la sesión del teléfono,
/// la búsqueda y las fichas de artista y álbum del catálogo público, y
/// Recientes y Lo más oído de la base local.
class MusicModeClient {
  MusicModeClient({
    required this.ytm,
    required this.ytmAccount,
    this.catalog,
    this.boot,
    this.listens,
  });

  /// La sesión de YouTube Music.
  final YtmClient ytm;

  /// La cuenta de la sesión (nombre y canal), ya conocida por el arranque.
  final YtmAccount? Function() ytmAccount;

  /// Catálogo público de artistas, álbumes y búsqueda (sin sesión).
  final PublicCatalogClient? catalog;

  /// Escuchas guardadas en el teléfono: de ahí salen Recientes y Lo más oído.
  final ListenStore? listens;

  /// Primeras páginas guardadas para abrir la app sin esperar a la red.
  final MusicBootCache? boot;

  /// Generación fija: con una sola sesión local no hay vínculos que cambien.
  static const ytmGeneration = 'ytm';

  /// Todas las pantallas: con la sesión directa, YouTube Music las sirve todas.
  static const ytmCapabilities = {
    'home',
    'songs',
    'liked',
    'channelLiked',
    'playlists',
    'playlist',
    'albums',
    'album',
    'artists',
    'artist',
    'search',
    'history',
    'mysicRecents',
    'onRepeat',
    'playback',
    'musicPlaylists',
  };

  bool _activityPaused = false;

  static String _pageKey(
    String generation,
    MusicSurface surface,
    String? playlistId,
  ) => '$generation|${surface.name}|${playlistId ?? ''}';

  MusicConnection _connectionFor(YtmAccount account) {
    final me = MusicAccount(
      YtmAuthRepository.uidFor(account),
      account.name,
      _activityPaused,
    );
    return MusicConnection(
      status: MusicLinkStatus.linked,
      provider: 'youtubeOAuth',
      personalization: 'verified',
      libraryId: me.id,
      accounts: [me],
      account: me,
      generation: ytmGeneration,
      // Recientes y Lo más oído existen siempre: salen de lo escuchado aquí.
      capabilities: ytmCapabilities,
    );
  }

  /// La conexión de la cuenta guardada, al instante y sin red; null si aún no
  /// se conoce la cuenta.
  Future<MusicConnection?> rememberedConnection() async {
    final account = ytmAccount();
    return account == null ? null : _connectionFor(account);
  }

  /// La primera página guardada en disco de [surface] (o de una playlist)
  /// para [generation], si la hay.
  Future<MusicPage?> rememberedPage(
    String generation,
    MusicSurface surface, {
    String? playlistId,
  }) async {
    try {
      final data = await boot?.readPage(
        _pageKey(generation, surface, playlistId),
      );
      return data == null ? null : MusicPage.fromJson(data);
    } on Object {
      return null;
    }
  }

  static String get _dialKey => '$ytmGeneration|dial|';

  /// El collage de Inicio tal como quedó la última vez, si lo hay.
  Future<MusicPage?> rememberedDial() async {
    try {
      final data = await boot?.readPage(_dialKey);
      return data == null ? null : MusicPage.fromJson(data);
    } on Object {
      return null;
    }
  }

  /// Guarda el collage para la próxima apertura.
  void rememberDial(Map<String, dynamic> json) {
    final cache = boot;
    if (cache != null) unawaited(cache.writePage(_dialKey, json));
  }

  /// La conexión de la cuenta: la guardada, o la que YouTube confirma.
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      _connectionFor(ytmAccount() ?? await ytm.account());

  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
    bool remember = false,
  }) async {
    // Recientes y Lo más oído salen de la base del teléfono.
    final store = listens;
    if (store != null) {
      if (surface == MusicSurface.mysicRecents ||
          surface == MusicSurface.history ||
          surface == MusicSurface.onRepeat) {
        // El historial guardado con la identidad anterior pasa a esta cuenta.
        await store.adoptLegacy();
      }
      if (surface == MusicSurface.mysicRecents ||
          surface == MusicSurface.history) {
        return MusicPage(await store.recent(limit: 5000), null, null, 0);
      }
      if (surface == MusicSurface.onRepeat) {
        return MusicPage(await store.mostPlayed(limit: 500), null, null, 0);
      }
    }
    if (surface == MusicSurface.search) {
      final songs = catalog;
      if (songs == null) {
        throw const ApiFailure('La búsqueda no está disponible.');
      }
      return songs.search(query ?? '', 'song', cancelToken: cancelToken);
    }
    final json = await ytm.pageJson(
      surface,
      playlistId: playlistId,
      cursor: cursor,
      cancelToken: cancelToken,
    );
    // Solo la primera página de la pantalla pedida, y solo si se pudo leer.
    final cache = boot;
    if (remember && cache != null && query == null && cursor == null) {
      unawaited(
        cache.writePage(_pageKey(generation, surface, playlistId), json),
      );
    }
    return MusicPage.fromJson(json);
  }

  // ---- Buscar: directo a YouTube Music, como el resto de la cuenta ----

  static List<MusicItem> _items(Iterable<Map<String, dynamic>> rows) {
    final items = <MusicItem>[];
    for (final row in rows) {
      try {
        items.add(MusicItem.fromJson(row));
      } on Object {
        // Una fila que no se entiende no tumba la búsqueda.
      }
    }
    return items;
  }

  /// La búsqueda de Limusic: la general (resultado principal, álbumes,
  /// artistas, playlists) y las de canciones y vídeos, las tres a la vez. Si
  /// YouTube Music no responde a ninguna, se prueba el catálogo público.
  Future<SearchResults> searchAll(
    String query, {
    CancelToken? cancelToken,
  }) async {
    Future<
      ({
        List<MusicItem> items,
        MusicItem? top,
        String line,
        List<MusicItem> paired,
      })?
    >
    attempt(String? filter) async {
      try {
        final page = await ytm.search(
          query,
          filter: filter,
          cancelToken: cancelToken,
        );
        return (
          items: _items(page.items),
          top: page.top == null ? null : _items([page.top!]).firstOrNull,
          line: page.topSubtitle,
          paired: _items(page.topSongs),
        );
      } on ApiFailure {
        return null;
      }
    }

    final [all, songs, videos] = await Future.wait([
      attempt(null),
      attempt('songs'),
      attempt('videos'),
    ]);
    if (all == null && songs == null && videos == null) {
      final public = catalog;
      if (public == null) {
        throw const ApiFailure('La búsqueda no está disponible.');
      }
      final page = await public.search(query, 'song', cancelToken: cancelToken);
      return SearchResults(songs: page.items.whereType<MusicTrack>().toList());
    }
    final mixed = all?.items ?? const <MusicItem>[];
    return SearchResults(
      top: all?.top,
      topSubtitle: all?.line ?? '',
      topSongs: all?.paired.whereType<MusicTrack>().toList() ?? const [],
      songs: (songs?.items ?? mixed).whereType<MusicTrack>().toList(),
      videos: (videos?.items ?? const <MusicItem>[])
          .whereType<MusicTrack>()
          .toList(),
      albums: mixed.whereType<MusicAlbum>().toList(),
      artists: mixed.whereType<MusicArtist>().toList(),
      playlists: mixed.whereType<MusicPlaylist>().toList(),
    );
  }

  /// La lista completa de un tipo (álbumes, artistas o playlists): su propia
  /// búsqueda filtrada, que se pide al abrir ese chip.
  Future<List<MusicItem>> searchKind(
    String query,
    SearchKind kind, {
    CancelToken? cancelToken,
  }) async => _items(
    (await ytm.search(
      query,
      filter: kind.name,
      cancelToken: cancelToken,
    )).items,
  );

  /// Sugerencias para lo que se lleva escrito.
  Future<SearchSuggestions> suggest(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final page = await ytm.suggestions(input, cancelToken: cancelToken);
    return SearchSuggestions(queries: page.queries, items: _items(page.items));
  }

  /// Las secciones de «Ambientes y géneros» guardadas de la última vez.
  Future<List<MoodSection>?> rememberedMoods() async {
    final saved = await boot?.read('moods');
    final sections = MoodSection.listFromJson(saved?['sections']);
    return sections.isEmpty ? null : sections;
  }

  /// Las secciones de «Ambientes y géneros» de YouTube Music; se guardan para
  /// pintarlas al instante la próxima vez.
  Future<List<MoodSection>> moods({CancelToken? cancelToken}) async {
    final sections = await ytm.moods(cancelToken: cancelToken);
    final cache = boot;
    if (cache != null && sections.isNotEmpty) {
      unawaited(cache.write('moods', {'sections': sections}));
    }
    return MoodSection.listFromJson(sections);
  }

  /// La página de un ambiente o género: sus playlists, cada una con el título
  /// de su sección.
  Future<MusicPage> moodPage(String params, {CancelToken? cancelToken}) async =>
      MusicPage.fromJson(
        await ytm.moodPageJson(params, cancelToken: cancelToken),
      );

  static const _artworkTtl = Duration(days: 7);
  static const _artworkParallel = 4;
  final _artwork = <String, Future<String?>>{};
  int _artworkRunning = 0;
  final _artworkWaiting = <Completer<void>>[];

  /// La portada de un ambiente o género: la primera carátula de su página. Se
  /// pide una sola vez por categoría, con pocas a la vez, y se guarda una
  /// semana.
  Future<String?> moodArtwork(String params) =>
      _artwork[params] ??= _resolveArtwork(params);

  Future<String?> _resolveArtwork(String params) async {
    final cache = boot;
    final saved = await cache?.read('moodArt') ?? const <String, dynamic>{};
    final hit = saved[params];
    if (hit is Map &&
        hit['url'] is String &&
        hit['at'] is int &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(hit['at'] as int),
            ) <
            _artworkTtl) {
      return hit['url'] as String;
    }
    if (_artworkRunning >= _artworkParallel) {
      final turn = Completer<void>();
      _artworkWaiting.add(turn);
      await turn.future;
    }
    _artworkRunning++;
    try {
      final page = await moodPage(params);
      final url = page.items
          .map(
            (item) => switch (item) {
              MusicTrack() => item.thumbnailUrl,
              MusicArtist() => item.thumbnailUrl,
              MusicAlbum() => item.thumbnailUrl,
              MusicPlaylist() => item.thumbnailUrl,
            },
          )
          .whereType<String>()
          .firstOrNull;
      if (url != null && cache != null) {
        final latest = {
          ...?await cache.read('moodArt'),
          params: {'url': url, 'at': DateTime.now().millisecondsSinceEpoch},
        };
        unawaited(cache.write('moodArt', latest));
      }
      return url;
    } on Object {
      // Sin portada la tesela se ve terminada igualmente; se reintenta en
      // otra visita.
      unawaited(_artwork.remove(params));
      return null;
    } finally {
      _artworkRunning--;
      if (_artworkWaiting.isNotEmpty) _artworkWaiting.removeAt(0).complete();
    }
  }

  /// Las búsquedas recientes guardadas de esta cuenta.
  Future<List<String>> rememberedSearches() async {
    final saved = await boot?.read('recentSearches');
    final items = saved?['items'];
    return items is List ? items.whereType<String>().toList() : const [];
  }

  void rememberSearches(List<String> queries) {
    final cache = boot;
    if (cache != null) {
      unawaited(
        cache.write('recentSearches', {
          'items': [...queries],
        }),
      );
    }
  }

  /// Inicio con un ambiente elegido (Relax, Dormir…): la misma página de
  /// YouTube Music con su clave. [cursor] pide la página siguiente.
  Future<MusicPage> moodHome(
    String params, {
    String? cursor,
    CancelToken? cancelToken,
  }) => ytm.page(
    MusicSurface.home,
    params: cursor == null ? params : null,
    cursor: cursor,
    cancelToken: cancelToken,
  );

  /// Una preferencia guardada de esta cuenta (atajos, disposición de Inicio).
  Future<Map<String, dynamic>?> rememberedPrefs(String key) async =>
      boot?.read(key);

  void rememberPrefs(String key, Map<String, dynamic> value) {
    final cache = boot;
    if (cache != null) unawaited(cache.write(key, value));
  }

  /// La pausa de actividad y el borrado son locales.
  Future<void> activityPreference(String generation, {bool? paused}) async {
    _activityPaused = paused == true;
  }
}
