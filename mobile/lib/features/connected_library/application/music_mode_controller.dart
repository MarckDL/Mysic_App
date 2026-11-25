import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, setEquals, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../playback/application/playback_providers.dart';
import '../../history/application/listening_tracker.dart'
    show MusicListenCallback;
import '../../history/data/local_listens.dart';
import '../data/device_recordings.dart';
import '../data/public_catalog_client.dart';
import '../../search/domain/catalog_track.dart';
import '../data/music_boot_cache.dart';
import '../data/music_mode_client.dart';
import '../../ytm/data/ytm_client.dart';
import '../domain/music_mode.dart';
import '../domain/shortcut.dart';

final musicModeControllerProvider = Provider.autoDispose
    .family<MusicModeController, String>((ref, uid) {
      final auth = ref.watch(authRepositoryProvider);
      final playback = ref.watch(trackPlaybackControllerProvider);
      bool owns() => auth.currentUser?.uid == uid;
      // El catálogo público (artistas, álbumes, búsqueda) no lleva sesión.
      final catalog = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? PublicCatalogClient(owns)
          : null;
      final ytmAuth = ref.watch(ytmAuthProvider);
      final session = ytmAuth.session;
      if (session == null) {
        throw const AuthFailure('Inicia sesión en YouTube Music.');
      }
      final ytmClient = YtmClient(session);
      final controller = MusicModeController(
        MusicModeClient(
          ytm: ytmClient,
          ytmAccount: () => ytmAuth.account,
          catalog: catalog,
          boot: MusicBootCache(uid),
          // Recientes y Lo más oído salen de la base de datos del teléfono.
          listens: ref.watch(localListensProvider(uid)),
        ),
        owns,
        playback.clear,
        device: DeviceRecordings(uid),
        onDeviceAudioRemoved: playback.removeDeviceAudio,
      );
      ref.onDispose(() {
        controller.dispose();
        catalog?.close();
        ytmClient.close();
      });
      return controller;
    });

class MusicModeController extends ChangeNotifier {
  MusicModeController(
    this._client,
    this._isOwner,
    this._clearPlayback, {
    this.device,
    this.onDeviceAudioRemoved,
  });
  final DeviceRecordings? device;
  final Future<void> Function(Uri)? onDeviceAudioRemoved;
  Map<String, Uri> _files = {};
  String? _fileGeneration;
  bool pickingAudio = false;
  Uri? deviceAudio(String id) =>
      isCurrent(_fileGeneration ?? '') ? _files[id] : null;

  final MusicModeClient _client;
  final bool Function() _isOwner;
  final Future<void> Function() _clearPlayback;
  MusicConnection? _connection;
  MusicConnection? get connection => _connection;
  set connection(MusicConnection? value) {
    _connection = value;
    // La pausa de actividad de Ajustes también frena las escuchas locales.
    _client.listens?.paused = value?.account?.historyPaused == true;
  }

  bool wantsMusic = false;
  bool busy = false;
  bool transitioning = false;
  final bool _localOverride = false;
  bool failed = false;
  String? failureCode;
  bool _disposed = false;
  bool _refreshAgain = false;
  int _bindingEpoch = 0;
  int _revision = 0;
  bool get _active => !_disposed && _isOwner();
  bool get showMusic =>
      transitioning ||
      (!_localOverride && (wantsMusic || connection == null || false));
  int get revision => _revision;
  CatalogTrack playbackTrack(String generation, MusicTrack track) =>
      track.toPlaybackTrack(deviceAudio: deviceAudio(track.id));

  bool isCurrent(String generation) =>
      _active &&
      !transitioning &&
      !_localOverride &&
      wantsMusic &&
      connection?.status == MusicLinkStatus.linked &&
      generation == connection?.generation;

  void _forgetData() {
    _revision++;
    recentSearches.clear();
    _links.clear();
    _recalled.clear();
  }

  Future<bool> attachAudio(String generation, String id) async {
    if (!isCurrent(generation) || pickingAudio || device == null) return false;
    final revision = _revision;
    bool current() => isCurrent(generation) && revision == _revision;
    pickingAudio = true;
    notifyListeners();
    try {
      final uri = await device!.attach(
        connection!.libraryId ?? generation,
        id,
        current,
      );
      if (uri == null || !current()) return false;
      _files[id] = uri;
      _fileGeneration = generation;
      return true;
    } finally {
      pickingAudio = false;
      if (_active) notifyListeners();
    }
  }

  Future<void> removeAudio(String generation, String id) async {
    final audio = deviceAudio(id);
    if (!isCurrent(generation) || pickingAudio || audio == null) {
      return;
    }
    pickingAudio = true;
    notifyListeners();
    try {
      await onDeviceAudioRemoved?.call(audio);
      if (!isCurrent(generation)) return;
      await device?.remove(connection!.libraryId ?? generation, id);
      if (isCurrent(generation)) _files.remove(id);
    } finally {
      pickingAudio = false;
      if (_active) notifyListeners();
    }
  }

  Future<void> refresh({
    bool invalidate = false,
    bool recheckMusic = false,
  }) async {
    if (!_active) return;
    if (invalidate) {
      _bindingEpoch++;
      connection = null;
      transitioning = true;
      _forgetData();
      unawaited(_clearPlayback());
    }
    if (busy) {
      _refreshAgain = true;
      if (invalidate) notifyListeners();
      return;
    }
    final epoch = _bindingEpoch;
    busy = true;
    failed = false;
    failureCode = null;
    notifyListeners();
    try {
      // Al abrir la app se muestra enseguida la última conexión conocida; la
      // respuesta del servidor la confirma o la sustituye justo después.
      if (connection == null && !invalidate && !recheckMusic) {
        final remembered = await _client.rememberedConnection();
        if (remembered != null &&
            remembered.status == MusicLinkStatus.linked &&
            connection == null &&
            _active &&
            epoch == _bindingEpoch) {
          connection = remembered;
          wantsMusic = !_localOverride;
          notifyListeners();
        }
      }
      final next = await _client.connection(recheckMusic: recheckMusic);
      if (!_active || epoch != _bindingEpoch) return;
      final previous = connection;
      if (previous != null &&
          next.generation != null &&
          next.generation == previous.generation &&
          next.activityEpoch < previous.activityEpoch) {
        return;
      }
      final changed =
          connection?.generation != next.generation ||
          connection?.status != next.status;
      if (!changed &&
          (connection?.personalization != next.personalization ||
              !setEquals(connection?.capabilities, next.capabilities))) {
        _revision++;
      }
      if (!changed && connection?.activityEpoch != next.activityEpoch) {
        _revision++;
      }
      if (!_localOverride &&
          changed &&
          (wantsMusic || next.status == MusicLinkStatus.linked)) {
        transitioning = true;
        _forgetData();
        notifyListeners();
        await _clearPlayback();
      }
      if (!_active || epoch != _bindingEpoch) return;
      if (next.isDirect &&
          device != null &&
          (next.status == MusicLinkStatus.linked ||
              next.status == MusicLinkStatus.unlinked) &&
          (_fileGeneration != next.generation ||
              invalidate ||
              connection == null)) {
        try {
          final files = await device!.open(
            next.libraryId ?? next.generation,
            () => _active && epoch == _bindingEpoch,
          );
          if (!_active || epoch != _bindingEpoch) return;
          _files = files;
          _fileGeneration = next.generation;
        } on Object {
          if (!_active || epoch != _bindingEpoch) return;
          _files = {};
          _fileGeneration = null;
        }
      }
      connection = next;
      wantsMusic =
          !_localOverride &&
          (next.status == MusicLinkStatus.linked ||
              next.status == MusicLinkStatus.expired);
    } catch (_) {
      if (_active && epoch == _bindingEpoch) failed = true;
    } finally {
      busy = false;
      if (_active && _refreshAgain) {
        _refreshAgain = false;
        unawaited(refresh());
      } else {
        transitioning = false;
        if (_active) notifyListeners();
      }
    }
  }

  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,

    /// Consulta de adorno (portadas de las pastillas): si falla, solo falla
    /// ella. Sin esto, un error de una consulta secundaria refrescaba la
    /// conexión y abortaba la lista que el usuario estaba esperando.
    bool quiet = false,

    /// Guarda esta primera página para pintarla en el próximo arranque.
    bool remember = false,
  }) async {
    if (!isCurrent(generation)) throw const ApiFailure('Cambió la conexión.');
    final requestRevision = _revision;
    try {
      late final MusicPage page;
      try {
        page = await _client.page(
          generation,
          surface,
          playlistId: playlistId,
          query: query,
          cursor: cursor,
          cancelToken: cancelToken,
          remember: remember,
        );
      } on ApiFailure catch (error) {
        if (error.code != 'MUSIC_SEARCH_UNAVAILABLE' ||
            surface != MusicSurface.search ||
            cursor != null ||
            query == null ||
            connection?.isDirect != true ||
            _client.catalog == null ||
            !isCurrent(generation) ||
            _revision != requestRevision) {
          rethrow;
        }
        page = await _client.catalog!.publicSongs(query, cancelToken);
      }
      if (!isCurrent(generation) || _revision != requestRevision) {
        throw const ApiFailure('Cambió la conexión.');
      }
      if (query == null && cursor == null) {
        _recall(_pageKey(generation, surface, playlistId), page);
      }
      return page;
    } on ApiFailure catch (error) {
      if (!quiet && isCurrent(generation) && _revision == requestRevision) {
        if (error.code == 'MUSIC_LINK_CHANGED' ||
            error.code == 'MUSIC_RECONNECT') {
          unawaited(refresh(invalidate: true));
        } else if ((error.code == 'MUSIC_ACCESS_DENIED' &&
                connection?.channelOnly != true) ||
            error.code == 'MYSIC_ACTIVITY_CHANGED') {
          unawaited(refresh());
        }
      }
      rethrow;
    }
  }

  // Las primeras páginas vistas en esta sesión: volver a una playlist, a Me
  // gusta o a la Biblioteca las pinta al instante mientras se piden de nuevo.
  static const _recallLimit = 24;
  final _recalled = <String, MusicPage>{};

  static String _pageKey(
    String generation,
    MusicSurface surface,
    String? playlistId,
  ) => '$generation|${surface.name}|${playlistId ?? ''}';

  void _recall(String key, MusicPage page) {
    _recalled.remove(key);
    _recalled[key] = page;
    if (_recalled.length > _recallLimit) {
      _recalled.remove(_recalled.keys.first);
    }
  }

  /// La primera página de [surface] tal como se vio la última vez en esta
  /// sesión, o null. Nunca sustituye a la respuesta del servidor.
  MusicPage? recalledPage(
    String generation,
    MusicSurface surface, {
    String? playlistId,
  }) => isCurrent(generation)
      ? _recalled[_pageKey(generation, surface, playlistId)]
      : null;

  /// La primera página que se guardó en disco de [surface] (o de una
  /// playlist), para pintarla al abrir aunque la app se haya cerrado.
  Future<MusicPage?> rememberedPage(
    String generation,
    MusicSurface surface, {
    String? playlistId,
  }) => _client.rememberedPage(generation, surface, playlistId: playlistId);

  /// El collage de Inicio guardado en la última apertura.
  Future<MusicPage?> rememberedDial() => _client.rememberedDial();

  /// Guarda el collage de Inicio para la próxima apertura.
  void rememberDial(Map<String, dynamic> json) => _client.rememberDial(json);

  /// Páginas públicas del catálogo (artista y álbum). Solo existen donde hay
  /// catálogo público (Android).
  Future<ArtistProfile> artistProfile(String id, {CancelToken? cancelToken}) {
    final catalog = _client.catalog;
    if (catalog == null) {
      throw const ApiFailure('El catálogo no está disponible aquí.');
    }
    return catalog.artistPage(id, cancelToken: cancelToken);
  }

  /// Todas las canciones de un artista (su «Ver todo»).
  Future<List<MusicTrack>> artistSongs(String id, {CancelToken? cancelToken}) {
    final catalog = _client.catalog;
    if (catalog == null) {
      throw const ApiFailure('El catálogo no está disponible aquí.');
    }
    return catalog.artistSongs(id, cancelToken: cancelToken);
  }

  /// La discografía completa de un artista, por estantes.
  Future<List<({String title, List<MusicItem> items})>> artistReleases(
    String id, {
    CancelToken? cancelToken,
  }) {
    final catalog = _client.catalog;
    if (catalog == null) {
      throw const ApiFailure('El catálogo no está disponible aquí.');
    }
    return catalog.artistReleases(id, cancelToken: cancelToken);
  }

  Future<AlbumDetail> albumDetail(String id, {CancelToken? cancelToken}) {
    final catalog = _client.catalog;
    if (catalog == null) {
      throw const ApiFailure('El catálogo no está disponible aquí.');
    }
    return catalog.albumPage(id, cancelToken: cancelToken);
  }

  bool get hasPublicCatalog => _client.catalog != null;

  /// Búsquedas recientes de la pestaña Buscar; se borran al cambiar de conexión.
  final recentSearches = <String>[];

  static const _maxSearches = 20;
  bool _searchesRestored = false;

  /// Trae las búsquedas guardadas en disco, una vez por sesión.
  Future<void> restoreSearches() async {
    if (_searchesRestored) return;
    _searchesRestored = true;
    final saved = await _client.rememberedSearches();
    if (_disposed) return;
    for (final query in saved) {
      if (recentSearches.length >= _maxSearches) break;
      if (!recentSearches.any((q) => q.toLowerCase() == query.toLowerCase())) {
        recentSearches.add(query);
      }
    }
  }

  /// Pone [query] la primera de las recientes (una por consulta, sin
  /// distinguir mayúsculas) y lo guarda.
  void rememberSearch(String query) {
    recentSearches
      ..removeWhere((q) => q.toLowerCase() == query.toLowerCase())
      ..insert(0, query);
    if (recentSearches.length > _maxSearches) {
      recentSearches.removeRange(_maxSearches, recentSearches.length);
    }
    _client.rememberSearches(recentSearches);
  }

  /// Olvida una búsqueda reciente, o todas si [query] es null.
  void forgetSearch([String? query]) {
    if (query == null) {
      recentSearches.clear();
    } else {
      recentSearches.remove(query);
    }
    _client.rememberSearches(recentSearches);
  }

  // ---- Inicio: atajos fijados y disposición ----

  /// Los atajos que el usuario fijó; null mientras no haya tocado nada (se
  /// usan entonces los de [defaultShortcuts]).
  final shortcuts = ValueNotifier<List<Shortcut>?>(null);

  /// Los atajos de fábrica: las colecciones y las primeras playlists. Los
  /// calcula Inicio con lo que la cuenta tiene.
  List<Shortcut> defaultShortcuts = const [];

  List<Shortcut> get effectiveShortcuts => shortcuts.value ?? defaultShortcuts;

  bool isShortcut(Shortcut shortcut) =>
      effectiveShortcuts.any((other) => other.sameAs(shortcut));

  bool get shortcutsFull => effectiveShortcuts.length >= Shortcut.max;

  /// Fija [shortcut] o lo quita si ya estaba. Con la cuadrícula llena no
  /// entra nada.
  void toggleShortcut(Shortcut shortcut) {
    final list = [...effectiveShortcuts];
    final at = list.indexWhere((other) => other.sameAs(shortcut));
    if (at >= 0) {
      list.removeAt(at);
    } else if (list.length < Shortcut.max) {
      list.add(shortcut);
    } else {
      return;
    }
    shortcuts.value = list;
    _client.rememberPrefs('shortcuts', {
      'items': [for (final item in list) item.toJson()],
    });
  }

  /// Mueve el atajo de [from] a [to] (índices de la lista final, como los da
  /// un `ReorderableListView` tras ajustar el destino). Devuelve false si no
  /// cambia nada. Parte de los de fábrica si aún no se había tocado nada.
  bool moveShortcut(int from, int to) {
    final list = [...effectiveShortcuts];
    if (from < 0 || from >= list.length || to < 0 || to >= list.length) {
      return false;
    }
    if (from == to) return false;
    list.insert(to, list.removeAt(from));
    shortcuts.value = list;
    _client.rememberPrefs('shortcuts', {
      'items': [for (final item in list) item.toJson()],
    });
    return true;
  }

  /// Cómo quiere el usuario su Inicio.
  final homeLayout = ValueNotifier(const HomeLayout());

  void setHomeLayout(HomeLayout layout) {
    homeLayout.value = layout;
    _client.rememberPrefs('homeLayout', layout.toJson());
  }

  bool _homeRestored = false;

  /// Trae los atajos y la disposición guardados, una vez por sesión.
  Future<void> restoreHome() async {
    if (_homeRestored) return;
    _homeRestored = true;
    try {
      final saved = await _client.rememberedPrefs('shortcuts');
      final items = saved?['items'];
      if (items is List && !_disposed && shortcuts.value == null) {
        shortcuts.value = [
          for (final item in items) ?Shortcut.fromJson(item),
        ].take(Shortcut.max).toList();
      }
      final layout = await _client.rememberedPrefs('homeLayout');
      if (layout != null && !_disposed) {
        homeLayout.value = HomeLayout.fromJson(layout);
      }
    } on Object {
      // Sin lo guardado, Inicio abre con lo de fábrica.
    }
  }

  /// Una consulta al cliente musical (búsqueda, sugerencias, ambientes) que
  /// solo vale si la conexión sigue siendo [generation] al terminar.
  Future<T> ask<T>(
    String generation,
    Future<T> Function(MusicModeClient client) run,
  ) async {
    if (!isCurrent(generation)) throw const ApiFailure('Cambió la conexión.');
    final revision = _revision;
    final result = await run(_client);
    if (!isCurrent(generation) || _revision != revision) {
      throw const ApiFailure('Cambió la conexión.');
    }
    return result;
  }

  /// Búsqueda de artistas o álbumes en el catálogo público.
  Future<MusicPage> publicSearch(
    String generation,
    String query,
    String type, {
    CancelToken? cancelToken,
  }) async {
    final catalog = _client.catalog;
    if (catalog == null || !isCurrent(generation)) {
      throw const ApiFailure('Cambió la conexión.');
    }
    final revision = _revision;
    final page = await catalog.searchCatalog(
      query,
      type,
      cancelToken: cancelToken,
    );
    if (!isCurrent(generation) || _revision != revision) {
      throw const ApiFailure('Cambió la conexión.');
    }
    return page;
  }

  // Se guarda la consulta, no solo su resultado: dos peticiones simultáneas
  // de la misma canción (el reproductor y un menú) comparten una búsqueda.
  final _links = <String, Future<TrackLinks>>{};

  /// Enlaces de artista y álbum de una canción, con caché por canción. Con
  /// [withAlbumName] se consulta aunque ya se conozcan los dos ids, porque las
  /// canciones no traen el nombre del álbum.
  Future<TrackLinks> trackLinks({
    required String videoId,
    required String title,
    required String artist,
    String? artistId,
    String? albumId,
    bool withAlbumName = false,
  }) async {
    final known = (artistId: artistId, albumId: albumId, album: null);
    final catalog = _client.catalog;
    if (catalog == null ||
        (!withAlbumName && artistId != null && albumId != null)) {
      return known;
    }
    final lookup = _links[videoId] ??= catalog.resolveLinks(
      videoId: videoId,
      title: title,
      artist: artist,
    );
    final TrackLinks found;
    try {
      found = await lookup;
    } on Object {
      // Un fallo no se recuerda: la próxima vez se vuelve a intentar.
      if (identical(_links[videoId], lookup)) unawaited(_links.remove(videoId));
      rethrow;
    }
    final sameAlbum = albumId == null || albumId == found.albumId;
    return (
      artistId: artistId ?? found.artistId,
      albumId: albumId ?? found.albumId,
      // El nombre solo vale si es del mismo álbum que ya traía la canción.
      album: sameAlbum ? found.album : null,
    );
  }

  bool updatingActivity = false;
  Future<void> updateActivity(String generation, {bool? paused}) async {
    if (!isCurrent(generation) || updatingActivity) return;
    updatingActivity = true;
    notifyListeners();
    try {
      await _client.activityPreference(generation, paused: paused);
      // "Borrar actividad" también vacía lo guardado en el teléfono.
      if (paused == null) await _client.listens?.clear();
      if (!isCurrent(generation)) return;
      final latest = await _client.connection();
      if (!isCurrent(generation) || latest.generation != generation) return;
      connection = latest;
      _revision++;
    } finally {
      updatingActivity = false;
      if (_active) notifyListeners();
    }
  }

  /// El conteo de cada escucha lo hace el registrador local; aquí solo se dice
  /// si se está registrando (no con la actividad en pausa).
  MusicListenCallback? listenForTrack(String generation) {
    final current = connection;
    if (!isCurrent(generation) ||
        current == null ||
        updatingActivity ||
        current.account?.historyPaused == true) {
      return null;
    }
    return (id, trackId, ms) {};
  }

  @override
  void dispose() {
    _disposed = true;
    _forgetData();
    super.dispose();
  }
}
