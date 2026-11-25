import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/offline_mode.dart';
import '../../../core/settings/app_settings.dart';
import '../../authentication/presentation/account_screen.dart'
    show AccountAction;
import '../../downloads/application/download_sort_provider.dart';
import '../../spotify_import/presentation/spotify_import_sheet.dart'
    show showSpotifyImport;
import '../../downloads/data/download_store.dart';
import '../../downloads/domain/download_sort.dart';
import '../../downloads/presentation/download_sort_sheet.dart';
import '../../downloads/presentation/downloads_screen.dart'
    show openDownloadedCollection;
import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import '../../playback/domain/track_audio_engine.dart' show TrackAudioPhase;
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../../search/presentation/music_tiles.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import 'catalog_pages.dart';
import 'tab_top_bar.dart';
import 'track_sheet.dart';

/// Pestañas de la Biblioteca, en el orden de la fila de chips de Limusic
/// (`LibraryChips`). Mysic no tiene podcasts.
enum LibraryTab { all, playlists, albums, artists, songs, downloads }

/// Se sube cada vez que algo cambia la biblioteca de la cuenta desde fuera de
/// esta pantalla (el importador de Spotify crea una playlist): la Biblioteca
/// vuelve a leer lo que muestra.
final libraryRefreshRequests = ValueNotifier<int>(0);

/// La pestaña que la Biblioteca debe mostrar al abrirse (o ahora, si ya está
/// abierta): la app la pide al arrancar sin internet para dejar al usuario en
/// Descargas. La Biblioteca la lee una vez y la borra.
final libraryTabRequests = ValueNotifier<LibraryTab?>(null);

/// Lo que se sabe de una colección: la última lista que llegó (se conserva
/// mientras se refresca, como `last` en `GridLibraryPlaylist`), si hay una
/// petición en curso y si la última falló.
class _Res {
  List<MusicItem>? items;
  String? cursor;
  bool loading = false;
  bool failed = false;
  bool more = false;

  /// La última página siguiente falló: no se reintenta sola hasta que el
  /// usuario desplace o actualice.
  bool moreFailed = false;
}

/// La Biblioteca, con la estructura de `LibraryScreen.kt` de Limusic: barra
/// superior con desenfoque que contiene el título y la fila de chips; debajo,
/// el contenido de la pestaña elegida con un fundido al cambiar.
///
///  - **Todo**: cuatro teselas 2×2, el estante de playlists con «Ver todo» y la
///    lista «Añadido recientemente».
///  - **Playlists / Álbumes**: cuadrícula de al menos tres columnas.
///  - **Artistas / Canciones**: lista a todo el ancho; Canciones pagina sola.
///  - **Descargas**: filas de estado y las canciones descargadas.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.connection,
  });

  final MusicModeController controller;
  final MusicConnection connection;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  var _tab = LibraryTab.all;
  var _wasInBackground = false;
  final _res = <MusicSurface, _Res>{};
  final _store = DownloadStore.instance;

  Set<String> get _caps => widget.connection.capabilities;
  String? get _generation => widget.connection.generation;

  MusicSurface? get _likedSurface => _caps.contains('liked')
      ? MusicSurface.liked
      : _caps.contains('channelLiked')
      ? MusicSurface.channelLiked
      : null;

  /// La superficie de la pestaña Canciones: la biblioteca de canciones de la
  /// cuenta o, si no la hay, los Me gusta.
  MusicSurface? get _songsSurface =>
      _caps.contains('songs') ? MusicSurface.songs : _likedSurface;

  List<LibraryTab> get _tabs => [
    LibraryTab.all,
    LibraryTab.playlists,
    if (_caps.contains('albums')) LibraryTab.albums,
    if (_caps.contains('artists')) LibraryTab.artists,
    if (_songsSurface != null) LibraryTab.songs,
    LibraryTab.downloads,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    libraryRefreshRequests.addListener(_onRefreshRequested);
    libraryTabRequests.addListener(_onTabRequested);
    unawaited(_store.load());
    // Si la app pidió una pestaña antes de que se abriera la Biblioteca (el
    // arranque sin internet pide Descargas), se abre ya en ella.
    final asked = libraryTabRequests.value;
    if (asked != null) {
      libraryTabRequests.value = null;
      _tab = asked;
    }
    _enter(_tab);
  }

  @override
  void dispose() {
    libraryTabRequests.removeListener(_onTabRequested);
    libraryRefreshRequests.removeListener(_onRefreshRequested);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Se pidió otra pestaña con la Biblioteca ya abierta.
  void _onTabRequested() {
    final asked = libraryTabRequests.value;
    if (asked == null || !mounted) return;
    libraryTabRequests.value = null;
    _select(asked);
  }

  /// Algo creó una playlist en la cuenta (el importador de Spotify): se
  /// vuelve a leer lo que se está viendo.
  void _onRefreshRequested() {
    if (mounted) unawaited(_refresh());
  }

  /// Al volver a la app se refresca lo que se está viendo: una playlist
  /// creada en YouTube Music aparece sin tener que tirar de la lista.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      unawaited(_refresh());
    }
  }

  /// Vuelve a pedir lo que muestra la pestaña actual, conservando en pantalla
  /// lo que ya había.
  Future<void> _refresh() => switch (_tab) {
    LibraryTab.all => Future.wait([
      if (_caps.contains('playlists'))
        _ensure(MusicSurface.playlists, force: true),
      if (_likedSurface != null)
        _ensure(_likedSurface!, force: true, quiet: true),
    ]),
    LibraryTab.playlists => _ensure(MusicSurface.playlists, force: true),
    LibraryTab.albums => _ensure(MusicSurface.albums, force: true),
    LibraryTab.artists => _ensure(MusicSurface.artists, force: true),
    LibraryTab.songs => _ensure(_songsSurface!, force: true),
    LibraryTab.downloads => _store.load(),
  };

  _Res _of(MusicSurface surface) => _res.putIfAbsent(surface, _Res.new);

  /// Carga [surface] si aún no se tiene (o si [force]). Lo ya visto en esta
  /// sesión o guardado en disco se pinta al instante y se refresca por detrás.
  Future<void> _ensure(
    MusicSurface surface, {
    bool force = false,
    bool quiet = false,
  }) async {
    final generation = _generation;
    final res = _of(surface);
    if (generation == null || res.loading) return;
    if (res.items != null && !force) return;
    res.loading = true;
    res.failed = false;
    res.moreFailed = false;
    if (res.items == null) {
      final seen = widget.controller.recalledPage(generation, surface);
      if (seen != null) {
        res.items = seen.items;
        res.cursor = seen.nextCursor;
      } else {
        unawaited(
          widget.controller.rememberedPage(generation, surface).then((saved) {
            if (saved != null && mounted && res.items == null) {
              setState(() => res.items = saved.items);
            }
          }),
        );
      }
    }
    if (mounted) setState(() {});
    try {
      final page = await widget.controller.page(
        generation,
        surface,
        quiet: quiet,
        remember: true,
      );
      res.items = page.items;
      res.cursor = page.nextCursor;
    } on Object {
      res.failed = true;
    } finally {
      res.loading = false;
      if (mounted) setState(() {});
    }
  }

  /// La página siguiente de [surface], una sola petición a la vez.
  Future<void> _more(MusicSurface surface, {bool retry = false}) async {
    final generation = _generation;
    final res = _of(surface);
    final cursor = res.cursor;
    if (generation == null || cursor == null || res.more || res.loading) return;
    if (res.moreFailed && !retry) return;
    res.more = true;
    res.moreFailed = false;
    try {
      final page = await widget.controller.page(
        generation,
        surface,
        cursor: cursor,
        quiet: true,
      );
      final known = {
        for (final item in res.items ?? const <MusicItem>[]) item.id,
      };
      res.items = [
        ...?res.items,
        for (final item in page.items)
          if (known.add(item.id)) item,
      ];
      res.cursor = page.nextCursor;
    } on Object {
      // Se reintenta cuando el usuario vuelve a desplazar cerca del final.
      res.moreFailed = true;
    } finally {
      res.more = false;
      if (mounted) setState(() {});
    }
  }

  /// Lo que pide cada pestaña al mostrarse (el `LaunchedEffect(currentFilter)`
  /// de Limusic): una vez por visita, no en cada cambio de chip.
  void _enter(LibraryTab tab) {
    switch (tab) {
      case LibraryTab.all:
        if (_caps.contains('playlists')) {
          unawaited(_ensure(MusicSurface.playlists));
        }
        final liked = _likedSurface;
        if (liked != null) unawaited(_ensure(liked, quiet: true));
        if (_caps.contains('onRepeat')) {
          unawaited(_ensure(MusicSurface.onRepeat, quiet: true));
        }
        if (_caps.contains('artists')) {
          unawaited(_ensure(MusicSurface.artists, quiet: true));
        }
      case LibraryTab.playlists:
        unawaited(_ensure(MusicSurface.playlists));
      case LibraryTab.albums:
        unawaited(_ensure(MusicSurface.albums));
      case LibraryTab.artists:
        unawaited(_ensure(MusicSurface.artists));
      case LibraryTab.songs:
        final songs = _songsSurface;
        if (songs != null) unawaited(_ensure(songs));
      case LibraryTab.downloads:
        break;
    }
  }

  void _select(LibraryTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _enter(tab);
  }

  // ---- Reproducción ----

  TrackPlaybackController get _player =>
      ref.read(trackPlaybackControllerProvider);

  /// El reproductor solo si ya existe: pintar una fila no justifica crearlo.
  TrackPlaybackController? get _playerIfAny =>
      ref.exists(trackPlaybackControllerProvider) ? _player : null;

  bool _canPlay(MusicTrack track) =>
      canPlayMusicTrack(widget.controller, track);

  /// Una canción suelta: la cola es esa canción y su radio (como el
  /// `PlaylistType.RADIO` de «Recently added» en Limusic).
  void _playOne(MusicTrack track) {
    final generation = _generation;
    if (generation == null || !widget.controller.isCurrent(generation)) return;
    final music = widget.controller;
    unawaited(
      _player.playQueue([
        music.playbackTrack(generation, track),
      ], listenForTrack: () => music.listenForTrack(generation)),
    );
    context.push('/player');
  }

  void _openPlaylist(MusicPlaylist item) => context.push(
    '/music/playlist/${Uri.encodeComponent(item.id)}',
    extra: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
  );

  void _open(MusicItem item) {
    switch (item) {
      case MusicPlaylist():
        _openPlaylist(item);
      case MusicAlbum():
        openAlbum(
          context,
          item.id,
          seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
        );
      case MusicArtist():
        openArtist(
          context,
          item.id,
          seed: PageSeed(title: item.title, imageUrl: item.thumbnailUrl),
        );
      case MusicTrack():
        if (_canPlay(item)) _playOne(item);
    }
  }

  /// Mantener pulsado: la hoja de opciones del elemento.
  void _hold(MusicItem item) => unawaited(
    showItemMenu(
      context,
      ref,
      item,
      // Editar o eliminar una playlist, o seguir a un artista, cambia lo que
      // esta pantalla enseña.
      onChanged: () => unawaited(_refresh()),
    ),
  );

  static String? _coverOf(_Res? res) => res?.items
      ?.map(
        (item) => switch (item) {
          MusicTrack() => item.thumbnailUrl,
          MusicArtist() => item.thumbnailUrl,
          MusicAlbum() => item.thumbnailUrl,
          MusicPlaylist() => item.thumbnailUrl,
        },
      )
      .whereType<String>()
      .firstOrNull;

  // ---- Interfaz ----

  /// Alto de la barra: 64 dp del título y 44 dp de la fila de chips.
  static const _barHeight = 64.0 + 44.0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + _barHeight;
    return Scaffold(
      body: Stack(
        children: [
          // El contenido cambia con un fundido (Limusic: `Crossfade`).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: _content(context, top),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _LibraryBar(
              tabs: _tabs,
              selected: _tab,
              onSelect: _select,
              showHistory:
                  _caps.contains('history') || _caps.contains('mysicRecents'),
              onRefresh: () => unawaited(_refresh()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, double top) => switch (_tab) {
    LibraryTab.all => _allTab(context, top),
    LibraryTab.playlists => _grid(
      top,
      MusicSurface.playlists,
      empty: 'Aún no tienes playlists.',
    ),
    LibraryTab.albums => _grid(
      top,
      MusicSurface.albums,
      empty: 'Aún no has guardado álbumes.',
    ),
    LibraryTab.artists => _artists(top),
    LibraryTab.songs => _list(
      top,
      _songsSurface!,
      empty: 'Aún no hay canciones en tu biblioteca.',
      paged: true,
    ),
    LibraryTab.downloads => _downloadsTab(context, top),
  };

  EdgeInsets _padding(double top) => EdgeInsets.only(
    top: top,
    bottom: 24 + MediaQuery.paddingOf(context).bottom,
  );

  // -- Todo --

  Widget _allTab(BuildContext context, double top) {
    final playlists = _of(MusicSurface.playlists);
    final liked = _likedSurface == null ? null : _of(_likedSurface!);
    final repeat = _res[MusicSurface.onRepeat];
    final artists = _res[MusicSurface.artists];
    final downloads = _store.tracks;
    final recent =
        liked?.items?.whereType<MusicTrack>().take(20).toList() ?? const [];
    final player = _playerIfAny;
    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: _refresh,
      child: ListView(
        padding: _padding(top),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Las cuatro colecciones, dos por fila (`LibraryTilingBox`).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) => LibraryTiles(
                tiles: [
                  if (_likedSurface != null)
                    (
                      icon: Icons.favorite_rounded,
                      label: widget.connection.usesChannelLikes
                          ? 'Me gusta de mi canal'
                          : 'Tus Me gusta',
                      caption: 'Tus favoritas',
                      onTap: () => context.push('/music/liked'),
                      coverUrl: _coverOf(liked),
                    ),
                  (
                    icon: Icons.download_for_offline_rounded,
                    label: 'Descargas',
                    caption: downloads.length == 1
                        ? '1 canción'
                        : '${downloads.length} canciones',
                    onTap: () => _select(LibraryTab.downloads),
                    coverUrl: downloads.firstOrNull?.thumbnailUrl,
                  ),
                  if (_caps.contains('onRepeat'))
                    (
                      icon: Icons.trending_up_rounded,
                      label: 'Lo más oído',
                      caption: 'Últimos 30 días',
                      onTap: () => context.push('/music/repeat'),
                      coverUrl: _coverOf(repeat),
                    ),
                  if (_caps.contains('artists'))
                    (
                      icon: Icons.people_alt_rounded,
                      label: 'Artistas',
                      caption: 'Los que sigues',
                      // Como en Limusic: abre la pestaña, no otra pantalla.
                      onTap: () => _select(LibraryTab.artists),
                      coverUrl: _coverOf(artists),
                    ),
                ],
              ),
            ),
          ),
          if (_caps.contains('playlists')) ...[
            LibrarySectionHeader(
              icon: Icons.queue_music_rounded,
              title: 'Playlists',
              padding: const EdgeInsets.only(top: 20),
              onMore: () => _select(LibraryTab.playlists),
            ),
            _PlaylistShelf(
              playlists:
                  playlists.items?.whereType<MusicPlaylist>().toList() ??
                  const [],
              loading: playlists.items == null && playlists.loading,
              onNearEnd: () => unawaited(_more(MusicSurface.playlists)),
              onOpen: _openPlaylist,
              onHold: _hold,
            ),
          ],
          if (liked != null) ...[
            const LibrarySectionHeader(
              icon: Icons.update_rounded,
              title: 'Añadido recientemente',
              padding: EdgeInsets.only(top: 20, bottom: 4),
            ),
            // Fundido entre el esqueleto y la lista (`Crossfade(isLoading)`).
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: liked.items == null && liked.loading
                  ? const Padding(
                      key: ValueKey('skeleton'),
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SkeletonRows(count: 5),
                    )
                  : Padding(
                      key: const ValueKey('rows'),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          for (final track in recent)
                            _songRow(track, player, key: 'recent'),
                          if (recent.isEmpty)
                            _EmptyText(
                              liked.failed
                                  ? 'No se pudo cargar. Desliza para reintentar.'
                                  : 'Aún no has añadido canciones.',
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _songRow(
    MusicTrack track,
    TrackPlaybackController? player, {
    required String key,
  }) => TouchWarm(
    key: ValueKey('$key:${track.id}'),
    // Como en Inicio: el audio se adelanta al detenerse en la fila y al
    // tocarla, para que suene al instante.
    onTouch: () => _warm(track, touch: true),
    onLinger: () => _warm(track, touch: false),
    child: _plainSongRow(track, player),
  );

  void _warm(MusicTrack track, {required bool touch}) {
    final generation = _generation;
    final player = _playerIfAny;
    if (!mounted ||
        player == null ||
        generation == null ||
        !_canPlay(track) ||
        !widget.controller.isCurrent(generation)) {
      return;
    }
    final playable = widget.controller.playbackTrack(generation, track);
    touch ? player.touchTrack(playable) : player.warmTracks([playable]);
  }

  Widget _plainSongRow(MusicTrack track, TrackPlaybackController? player) =>
      SongRow(
        playback: player,
        isCurrent: () => player?.current?.id == 'youtube:${track.id}',
        isRunning: () => player?.phase == TrackAudioPhase.playing,
        url: track.thumbnailUrl,
        title: track.title,
        subtitle: track.artist,
        onTap: _canPlay(track) ? () => _playOne(track) : null,
        onLongPress: () => _hold(track),
      );

  // -- Cuadrículas (Playlists, Álbumes) --

  Widget _grid(double top, MusicSurface surface, {required String empty}) {
    final res = _of(surface);
    final items = res.items;
    final skeleton = items == null && res.loading;
    final isEmpty = !skeleton && (items == null || items.isEmpty);
    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: () => _ensure(surface, force: true),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: isEmpty
            ? _EmptyPage(
                key: const ValueKey('empty'),
                top: top,
                text: res.failed
                    ? 'No se pudo cargar. Desliza para reintentar.'
                    : empty,
              )
            : LayoutBuilder(
                key: const ValueKey('grid'),
                builder: (context, box) {
                  // `LibraryGridCells`: las columnas que dejan la portada más
                  // cerca de 150 dp, nunca menos de tres.
                  final columns = (box.maxWidth / 170).round().clamp(3, 12);
                  final cell = (box.maxWidth - 12) / columns;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (note) {
                      if (note is ScrollUpdateNotification &&
                          note.metrics.extentAfter < 600) {
                        unawaited(_more(surface, retry: true));
                      }
                      return false;
                    },
                    child: GridView.builder(
                      padding: _padding(top).copyWith(left: 6, right: 6),
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        // Portada cuadrada, dos líneas de título y una de
                        // subtítulo, con el relleno de la tarjeta.
                        mainAxisExtent:
                            (cell - 20) +
                            16 +
                            MediaQuery.textScalerOf(context).scale(58),
                      ),
                      itemCount: skeleton ? 12 : items!.length,
                      itemBuilder: (context, index) {
                        if (skeleton) return const LibraryTileSkeleton();
                        // Al pintar las últimas se pide la página siguiente,
                        // también cuando la primera no llena la pantalla.
                        if (index >= items!.length - 6) {
                          unawaited(_more(surface));
                        }
                        final item = items[index];
                        return LibraryCoverTile(
                          key: ValueKey('${surface.name}:${item.id}'),
                          title: item.title,
                          subtitle: switch (item) {
                            MusicPlaylist() =>
                              item.isPrivate ? 'Privada' : 'Playlist',
                            MusicAlbum() => item.detail ?? 'Álbum',
                            _ => '',
                          },
                          url: switch (item) {
                            MusicPlaylist() => item.thumbnailUrl,
                            MusicAlbum() => item.thumbnailUrl,
                            _ => null,
                          },
                          icon: item is MusicAlbum
                              ? Icons.album
                              : Icons.queue_music,
                          onTap: () => _open(item),
                          onLongPress: () => _hold(item),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  // -- Listas (Artistas, Canciones) --

  Widget _list(
    double top,
    MusicSurface surface, {
    required String empty,
    bool paged = false,
  }) {
    final res = _of(surface);
    final items = res.items ?? const <MusicItem>[];
    final firstLoad = res.items == null && res.loading;
    final player = _playerIfAny;
    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: () => _ensure(surface, force: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (note) {
          // Cerca del final se pide la página siguiente.
          if (note is ScrollUpdateNotification &&
              note.metrics.extentAfter < 400) {
            unawaited(_more(surface, retry: true));
          }
          return false;
        },
        child: ListView.builder(
          padding: _padding(top),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == items.length) {
              if (firstLoad) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SkeletonRows(count: 8),
                );
              }
              if (items.isEmpty) {
                return _EmptyText(
                  res.failed
                      ? 'No se pudo cargar. Desliza para reintentar.'
                      : empty,
                );
              }
              return res.more
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            }
            // A cinco del final se pide la página siguiente (Limusic).
            if (index >= items.length - 5) unawaited(_more(surface));
            final item = items[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: switch (item) {
                MusicTrack() => _songRow(item, player, key: surface.name),

                _ => SongRow(
                  key: ValueKey('item:${item.id}'),
                  title: item.title,
                  subtitle: '',
                  onTap: () => _open(item),
                  onLongPress: () => _hold(item),
                ),
              },
            );
          },
        ),
      ),
    );
  }

  // -- Artistas --

  /// Los artistas con su foto, en filas de tres: la vista que la Biblioteca
  /// ya tenía (no las filas a todo el ancho de Limusic).
  Widget _artists(double top) {
    const surface = MusicSurface.artists;
    final res = _of(surface);
    final artists =
        res.items?.whereType<MusicArtist>().toList() ?? const <MusicArtist>[];
    final firstLoad = res.items == null && res.loading;
    final rows = (artists.length / 3).ceil();
    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: () => _ensure(surface, force: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (note) {
          if (note is ScrollUpdateNotification &&
              note.metrics.extentAfter < 400) {
            unawaited(_more(surface, retry: true));
          }
          return false;
        },
        child: ListView.builder(
          padding: _padding(top).copyWith(left: 16, right: 16),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: rows + 1,
          itemBuilder: (context, index) {
            if (index == rows) {
              if (firstLoad) return const SkeletonRows(count: 8);
              if (artists.isEmpty) {
                return _EmptyText(
                  res.failed
                      ? 'No se pudo cargar. Desliza para reintentar.'
                      : 'Aún no sigues a ningún artista.',
                );
              }
              return const SizedBox.shrink();
            }
            if (index >= rows - 2) unawaited(_more(surface));
            return ArtistPhotoRow(
              tiles: [
                for (final artist in artists.skip(index * 3).take(3))
                  ArtistPhotoTile(
                    key: ValueKey('artist:${artist.id}'),
                    name: artist.title,
                    detail: artist.detail,
                    url: artist.thumbnailUrl,
                    onTap: () => _open(artist),
                    onLongPress: () => _hold(artist),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // -- Descargas --

  Widget _downloadsTab(BuildContext context, double top) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final sort = ref.watch(downloadSortProvider);
      final tracks = sort.apply(_store.tracks);
      final collections = _store.collections;
      final pending = _store.pending;
      final failures = _store.failures;
      final bytes = tracks.fold<int>(0, (sum, track) => sum + track.bytes);
      final offline = ref.watch(offlineOnlyProvider);
      return ListView(
        padding: _padding(top),
        children: [
          // Las filas sobre la lista (`DownloadsHeader`).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              children: [
                _StatusRow(
                  icon: Icons.wifi_off_rounded,
                  title: 'Solo canciones descargadas',
                  subtitle: 'Sin usar internet ni datos',
                  trailing: Switch(
                    value: offline,
                    onChanged: ref.read(offlineOnlyProvider.notifier).set,
                  ),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _StatusRow(
                    icon: Icons.downloading_rounded,
                    title: pending.length == 1
                        ? 'Descargando «${pending.first.title}»'
                        : 'Descargando ${pending.length} canciones',
                    progress:
                        _store.progressOf(pending.first.id.substring(8)) ?? -1,
                  ),
                ],
                const SizedBox(height: 10),
                _StatusRow(
                  icon: Icons.download_for_offline_rounded,
                  title: 'Canciones descargadas',
                  subtitle:
                      '${tracks.length == 1 ? '1 canción' : '${tracks.length} canciones'}'
                      ' · ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                  onTap: () => context.push('/downloads'),
                ),
                if (failures.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _StatusRow(
                    icon: Icons.error_outline_rounded,
                    title: failures.length == 1
                        ? 'Falló 1 descarga'
                        : 'Fallaron ${failures.length} descargas',
                    subtitle: failures.first.title,
                    trailing: TextButton(
                      onPressed: () {
                        for (final failure in failures) {
                          _store.dismissFailure(failure.id);
                        }
                      },
                      child: const Text('Descartar'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Los álbumes y playlists descargados enteros (Limusic:
          // `GridLibraryPlaylist` con `getAllDownloadedPlaylist`).
          if (collections.isNotEmpty) ...[
            const SizedBox(height: 8),
            LibrarySectionHeader(title: 'Álbumes y playlists'),
            _collectionsGrid(collections),
          ],
          const SizedBox(height: 8),
          if (tracks.isNotEmpty)
            // El orden de la lista, como la «ActionsPill» de Limusic.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sort.key.label + (sort.desc ? ' · invertido' : ''),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const DownloadSortButton(),
                ],
              ),
            ),
          if (tracks.isEmpty)
            const _EmptyText(
              'Aún no hay canciones descargadas. Mantén pulsada una canción y '
              'elige «Descargar».',
            )
          else
            for (final (index, track) in tracks.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SongRow(
                  key: ValueKey('download:${track.id}'),
                  url: track.thumbnailUrl,
                  title: track.title,
                  subtitle:
                      sort.key == DownloadSortKey.album &&
                          (track.albumName?.isNotEmpty ?? false)
                      ? '${track.artist} · ${track.albumName}'
                      : track.artist,
                  onTap: () => unawaited(_playDownloads(tracks, index)),
                ),
              ),
        ],
      );
    },
  );

  /// La cuadrícula de colecciones descargadas: cada una con su portada, su
  /// nombre y cuántas de sus canciones están ya en el teléfono.
  Widget _collectionsGrid(List<DownloadedCollection> collections) =>
      LayoutBuilder(
        builder: (context, box) {
          final columns = (box.maxWidth / 170).round().clamp(3, 12);
          final cell = (box.maxWidth - 12) / columns;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent:
                  (cell - 20) + 16 + MediaQuery.textScalerOf(context).scale(58),
            ),
            itemCount: collections.length,
            itemBuilder: (context, index) {
              final collection = collections[index];
              final have = _store.tracksOf(collection).length;
              final total = collection.trackIds.length;
              final kind = collection.album ? 'Álbum' : 'Playlist';
              return LibraryCoverTile(
                key: ValueKey('downloaded:${collection.id}'),
                title: collection.title,
                // Mientras bajan, cuántas llegaron; después, el artista.
                subtitle: have < total
                    ? '$kind · $have de $total'
                    : collection.album && collection.subtitle != null
                    ? '$kind · ${collection.subtitle}'
                    : kind,
                url: collection.thumbnailUrl,
                icon: collection.album ? Icons.album : Icons.queue_music,
                onTap: () => _openCollection(collection),
                onLongPress: () => _holdCollection(collection),
              );
            },
          );
        },
      );

  MusicItem _itemOf(DownloadedCollection collection) => collection.album
      ? MusicAlbum(
          collection.id,
          collection.title,
          thumbnailUrl: collection.thumbnailUrl,
          artist: collection.subtitle,
        )
      : MusicPlaylist(
          collection.id,
          collection.title,
          false,
          thumbnailUrl: collection.thumbnailUrl,
        );

  /// Con internet se abre su página de siempre; sin ella, la de lo descargado.
  void _openCollection(DownloadedCollection collection) =>
      openDownloadedCollection(context, collection);

  void _holdCollection(DownloadedCollection collection) {
    if (!OfflineMode.instance.active) {
      _hold(_itemOf(collection));
      return;
    }
    unawaited(() async {
      final remove = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (context) => AlertDialog(
          title: Text(collection.title),
          content: const Text(
            '¿Quitar la descarga? Las canciones que no guarde otro álbum o '
            'playlist dejarán de estar en el teléfono.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Quitar descarga'),
            ),
          ],
        ),
      );
      if (remove == true) await _store.releaseCollection(collection.id);
    }());
  }

  Future<void> _playDownloads(List<DownloadedTrack> tracks, int index) async {
    final dir = await _store.directory();
    if (dir == null || !mounted) return;
    unawaited(
      _player.playQueue([
        for (final track in tracks.take(TrackPlaybackController.maxQueue))
          _store.playable(track, dir),
      ], initialIndex: index),
    );
    if (mounted) unawaited(context.push('/player'));
  }
}

/// La barra de la Biblioteca: título de 64 dp con sus acciones y, debajo, la
/// fila de chips, sobre un desenfoque del contenido (Limusic: `hazeBlur` con
/// `ultraThinBarStyle`). Con «Reducir efectos» es opaca, como el respaldo de
/// Limusic por debajo de Android 12.
class _LibraryBar extends StatelessWidget {
  const _LibraryBar({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.showHistory,
    required this.onRefresh,
  });

  final VoidCallback onRefresh;
  final List<LibraryTab> tabs;
  final LibraryTab selected;
  final ValueChanged<LibraryTab> onSelect;
  final bool showHistory;

  static const _labels = {
    LibraryTab.all: ('Todo', Icons.grid_view_rounded),
    LibraryTab.playlists: ('Playlists', Icons.queue_music_rounded),
    LibraryTab.albums: ('Álbumes', Icons.album_rounded),
    LibraryTab.artists: ('Artistas', Icons.people_alt_rounded),
    LibraryTab.songs: ('Canciones', Icons.library_music_rounded),
    LibraryTab.downloads: ('Descargas', Icons.download_for_offline_rounded),
  };

  @override
  Widget build(BuildContext context) => TabTopBar(
    title: 'Biblioteca',
    actions: [
      IconButton(
        tooltip: 'Actualizar',
        icon: const Icon(Icons.sync_rounded),
        onPressed: onRefresh,
      ),
      IconButton(
        tooltip: 'Importar de Spotify',
        icon: const Icon(Icons.link_rounded),
        onPressed: () => unawaited(showSpotifyImport(context)),
      ),
      if (showHistory)
        IconButton(
          tooltip: 'Abrir Recientes',
          icon: const Icon(Icons.history),
          onPressed: () => context.push('/history'),
        ),
      const AccountAction(),
    ],
    bottom: SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
        itemCount: tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final (label, icon) = _labels[tab]!;
          return LibraryChip(
            label: label,
            icon: icon,
            selected: tab == selected,
            onTap: () => onSelect(tab),
          );
        },
      ),
    ),
  );
}

/// Chip de la Biblioteca (Limusic `Chip`): píldora sin relleno y con borde
/// suave; la elegida va rellena del acento. Sin marca de verificación, para
/// que el ancho no cambie al tocar y la fila no salte bajo el dedo.
class LibraryChip extends StatelessWidget {
  const LibraryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;

  /// Sin icono en los filtros de Buscar, como el `Chip` de Limusic.
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final foreground = selected ? colors.onPrimary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: ShapeDecoration(
          color: selected ? colors.primary : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? Colors.transparent : colors.outlineVariant,
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Título de sección (Limusic `LibrarySectionHeader`): icono del tipo en el
/// acento suavizado, título en negrita y «Ver todo» al final cuando hay más.
class LibrarySectionHeader extends StatelessWidget {
  const LibrarySectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.onMore,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final IconData? icon;
  final VoidCallback? onMore;

  /// Lo que va al final en vez de «Ver todo» (p. ej. «Borrar»).
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 22,
                  color: colors.primary.withValues(alpha: .7),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Solo las palabras abren «Ver todo», no todo el ancho.
                  child: GestureDetector(
                    onTap: onMore,
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ?trailing,
              if (onMore != null)
                InkWell(
                  onTap: onMore,
                  customBorder: const StadiumBorder(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ver todo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las playlists en una fila (Limusic `PlaylistShelf`): portadas de 120 dp.
/// Mientras llegan, teselas de esqueleto del mismo alto para que la lista de
/// debajo no salte.
class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf({
    required this.playlists,
    required this.loading,
    required this.onNearEnd,
    required this.onOpen,
    required this.onHold,
  });

  final VoidCallback onNearEnd;
  final List<MusicPlaylist> playlists;
  final bool loading;
  final ValueChanged<MusicPlaylist> onOpen;
  final ValueChanged<MusicPlaylist> onHold;

  static const _thumb = 120.0;

  @override
  Widget build(BuildContext context) {
    final height = _thumb + 16 + MediaQuery.textScalerOf(context).scale(58);
    if (!loading && playlists.isEmpty) {
      return const _EmptyText('Aún no tienes playlists.');
    }
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: loading ? 4 : playlists.length,
        itemBuilder: (context, index) {
          if (loading) {
            return const SizedBox(
              width: _thumb + 20,
              child: LibraryTileSkeleton(),
            );
          }
          if (index >= playlists.length - 3) onNearEnd();
          final item = playlists[index];
          return SizedBox(
            width: _thumb + 20,
            child: LibraryCoverTile(
              key: ValueKey('shelf:${item.id}'),
              title: item.title,
              subtitle: item.isPrivate ? 'Privada' : 'Playlist',
              url: item.thumbnailUrl,
              icon: Icons.queue_music,
              onTap: () => onOpen(item),
              onLongPress: () => onHold(item),
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta de portada (Limusic `HomeItemContentPlaylist`): relleno 10/10/10/6,
/// carátula 1:1 con radio 10 que aparece con un fundido, título a dos líneas y
/// una línea de subtítulo. Mantener pulsado abre su hoja.
class LibraryCoverTile extends StatelessWidget {
  const LibraryCoverTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    required this.icon,
    this.url,
  });

  final String title;
  final String subtitle;
  final String? url;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrackArtwork(
                url: url,
                size: box.maxWidth,
                borderRadius: 10,
                fallbackIcon: icon,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta aún cargando (Limusic `PlaylistTileSkeleton`): el cuadrado de la
/// portada y dos líneas, con el mismo relleno que la real.
class LibraryTileSkeleton extends StatelessWidget {
  const LibraryTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton.block(
              context,
              width: box.maxWidth,
              height: box.maxWidth,
              radius: 10,
            ),
            const SizedBox(height: 10),
            Skeleton.block(
              context,
              width: box.maxWidth * .7,
              height: 14,
              radius: 50,
            ),
            const SizedBox(height: 6),
            Skeleton.block(
              context,
              width: box.maxWidth * .45,
              height: 11,
              radius: 50,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fila de estado de Descargas (Limusic `DownloadsRow`): tarjeta de radio 18 y
/// al menos 64 dp, con el cuadro de icono de 40 dp en el acento al 16 %.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.progress,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Avance de 0 a 1; -1 si no se conoce.
  final double? progress;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(icon, size: 22, color: colors.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        if (progress != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(
                              value: progress! < 0 ? null : progress,
                              color: colors.primary,
                              backgroundColor: colors.primary.withValues(
                                alpha: .16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// Una pestaña vacía: el texto centrado, desplazable para poder tirar y
/// actualizar.
class _EmptyPage extends StatelessWidget {
  const _EmptyPage({super.key, required this.top, required this.text});

  final double top;
  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: box.maxHeight,
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: _EmptyText(text),
        ),
      ),
    ),
  );
}
