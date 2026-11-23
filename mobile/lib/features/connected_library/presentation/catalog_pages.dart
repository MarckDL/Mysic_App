import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../../search/presentation/music_tiles.dart';
import '../application/music_mode_controller.dart';
import '../data/original_music_catalog.dart';
import '../domain/music_mode.dart';
import 'collection_actions.dart';
import 'music_mode_host.dart';
import 'track_sheet.dart';

/// Abre la página de artista nueva cuando el id es un canal y hay catálogo
/// público; si no, la lista de canciones del canal de siempre.
void openArtist(BuildContext context, String id, {PageSeed? seed}) {
  final public = MusicModeScope.of(context)?.hasPublicCatalog == true;
  context.push(
    public && OriginalMusicCatalog.isArtistId(id)
        ? '/artist/$id'
        : '/music/artist/${Uri.encodeComponent(id)}',
    extra: seed,
  );
}

/// Abre la página de álbum nueva para ids de álbum de YouTube Music; los
/// álbumes guardados con otro tipo de id siguen en la lista de siempre.
void openAlbum(BuildContext context, String id, {PageSeed? seed}) {
  final public = MusicModeScope.of(context)?.hasPublicCatalog == true;
  context.push(
    public && OriginalMusicCatalog.isAlbumId(id)
        ? '/album/$id'
        : '/music/album/${Uri.encodeComponent(id)}',
    extra: seed,
  );
}

/// Abre la página de artista o de álbum de una canción. Si la canción no
/// trae el enlace se resuelve buscándola; si no se encuentra, se avisa.
Future<void> openTrackLink(
  BuildContext context, {
  required bool album,
  required String videoId,
  required String title,
  required String artist,
  String? artistId,
  String? albumId,
}) async {
  final music = MusicModeScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  String? target = album ? albumId : artistId;
  if (target == null && music != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(album ? 'Buscando el álbum…' : 'Buscando el artista…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final found = await music.trackLinks(
        videoId: videoId,
        title: title,
        artist: artist,
        artistId: artistId,
        albumId: albumId,
      );
      target = album ? found.albumId : found.artistId;
    } on Object {
      target = null;
    }
  }
  messenger.hideCurrentSnackBar();
  if (target == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          album
              ? 'No se encontró el álbum de esta canción.'
              : 'No se encontró el artista de esta canción.',
        ),
      ),
    );
    return;
  }
  router.push(album ? '/album/$target' : '/artist/$target');
}

/// Reproduce [tracks] desde [index] con la fuente musical activa.
void _playTracks(
  BuildContext context,
  WidgetRef ref,
  List<MusicTrack> tracks,
  int index, {
  bool shuffled = false,
}) {
  final music = MusicModeScope.of(context);
  final connection = music?.connection;
  final generation = connection?.generation;
  if (music == null ||
      generation == null ||
      !music.isCurrent(generation) ||
      !connection!.capabilities.contains('playback')) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conecta una fuente musical para reproducir.'),
      ),
    );
    return;
  }
  // La lista entra entera a la cola (con lo ya pasado detrás); solo una lista
  // enorme se recorta a una ventana alrededor de la elegida.
  final start = index < TrackPlaybackController.maxQueue ? 0 : index - 50;
  final queue = tracks
      .skip(start)
      .take(TrackPlaybackController.maxQueue)
      .map((track) => music.playbackTrack(generation, track))
      .toList();
  if (queue.isEmpty) return;
  unawaited(
    ref
        .read(trackPlaybackControllerProvider)
        .playQueue(
          queue,
          initialIndex: index - start,
          shuffled: shuffled,
          listenForTrack: connection.nativeCatalog
              ? () => music.listenForTrack(generation)
              : null,
        ),
  );
  context.push('/player');
}

String _failureText(Object? error) => error is ApiFailure
    ? error.message
    : 'No se pudo cargar. Inténtalo de nuevo.';

/// Carga una página del catálogo una sola vez y permite reintentar.
mixin _PageLoader<W extends ConsumerStatefulWidget, T> on ConsumerState<W> {
  Future<T>? future;
  CancelToken? _cancel;

  Future<T> fetch(MusicModeController music, CancelToken cancel);

  /// Las canciones de la página, para adelantar el audio de las primeras.
  List<MusicTrack> songsOf(T page) => const [];

  // Adelanta el audio de las primeras canciones, que son las que se tocan
  // nada más llegar. Solo si el motor de audio ya existe.
  void _warm(MusicModeController music, T page) {
    final generation = music.connection?.generation;
    if (!mounted ||
        generation == null ||
        !music.isCurrent(generation) ||
        !ref.exists(trackPlaybackControllerProvider)) {
      return;
    }
    ref
        .read(trackPlaybackControllerProvider)
        .warmTracks(
          songsOf(page)
              .take(TrackPlaybackController.warmLimit)
              .map((track) => music.playbackTrack(generation, track)),
        );
  }

  void load() {
    final music = MusicModeScope.of(context);
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      future = music == null
          ? Future.error(const ApiFailure('El catálogo no está disponible.'))
          : fetch(music, cancel).then((page) {
              _warm(music, page);
              return page;
            });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (future == null) load();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}

/// Degradado bajo la barra de estado: el contenido que se desplaza por
/// debajo de ella se funde con el fondo en vez de mezclarse con el reloj.
class _StatusScrim extends StatelessWidget {
  const _StatusScrim();

  @override
  Widget build(BuildContext context) {
    final paper = Theme.of(context).colorScheme.surface;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // Opaco bajo toda la barra de estado y se desvanece en los 18 dp de debajo.
      height: MediaQuery.paddingOf(context).top + 18,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .72, 1],
              colors: [
                paper,
                paper.withValues(alpha: .97),
                paper.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo translúcido que flota sobre la cabecera.
class _FloatingBack extends StatelessWidget {
  const _FloatingBack();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Atrás',
      onPressed: () => Navigator.of(context).maybePop(),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(48),
        backgroundColor: colors.surfaceContainerHighest.withValues(alpha: .8),
        foregroundColor: colors.onSurface,
      ),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }
}

/// Aleatorio sin fondo y Play circular de 52 dp relleno del acento.
class _PlayActions extends StatelessWidget {
  const _PlayActions({required this.onPlay, required this.onShuffle});

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Aleatorio',
        iconSize: 26,
        style: IconButton.styleFrom(fixedSize: const Size.square(52)),
        onPressed: onShuffle,
        icon: const Icon(Icons.shuffle_rounded),
      ),
      const SizedBox(width: 4),
      IconButton.filled(
        tooltip: 'Reproducir',
        iconSize: 30,
        style: IconButton.styleFrom(fixedSize: const Size.square(52)),
        onPressed: onPlay,
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
      ),
    ),
  );
}

/// Lo que ya se sabe de una página antes de pedirla: el título y la imagen de
/// la tarjeta que el usuario acaba de tocar.
class PageSeed {
  const PageSeed({required this.title, this.imageUrl});
  final String title;
  final String? imageUrl;
}

/// Página de artista o de álbum mientras llega: en vez de un círculo de carga
/// sobre una pantalla vacía, la imagen y el título que ya se conocen y el
/// hueco de las pistas. Sin [seed] solo se ve el esqueleto.
class _SeedLoading extends StatelessWidget {
  const _SeedLoading({required this.seed, this.round = false});
  final PageSeed? seed;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final size = (MediaQuery.sizeOf(context).width * .5)
        .clamp(120.0, 230.0)
        .toDouble();
    return Scaffold(
      body: Stack(
        children: [
          ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, top + 64, 16, 24),
            children: [
              Center(
                child: TrackArtwork(
                  url: seed?.imageUrl,
                  size: size,
                  borderRadius: round ? size / 2 : 16,
                  fallbackIcon: round ? Icons.person : Icons.album,
                ),
              ),
              const SizedBox(height: 20),
              if (seed != null)
                Text(
                  seed!.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 20),
              Semantics(label: 'Cargando', child: const SkeletonRows()),
            ],
          ),
          Positioned(top: top + 8, left: 8, child: const _FloatingBack()),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_failureText(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: retry, child: const Text('Reintentar')),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Artista
// ---------------------------------------------------------------------------

/// Página de artista con la cabecera de Limusic: foto 1:1 a sangre fundida
/// con el fondo, nombre grande sobre ella y Play circular a la derecha.
class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.id, this.seed});
  final String id;
  final PageSeed? seed;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen>
    with _PageLoader<ArtistScreen, ArtistProfile> {
  bool _fullBio = false;

  @override
  Future<ArtistProfile> fetch(MusicModeController music, CancelToken cancel) =>
      music.artistProfile(widget.id, cancelToken: cancel);

  @override
  List<MusicTrack> songsOf(ArtistProfile page) => page.topSongs;

  @override
  Widget build(BuildContext context) => FutureBuilder<ArtistProfile>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(error: snapshot.error, retry: load);
      }
      final artist = snapshot.data;
      if (artist == null) return _SeedLoading(seed: widget.seed, round: true);
      final theme = Theme.of(context), colors = theme.colorScheme;
      final songs = artist.topSongs;
      return Scaffold(
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _ArtistHeader(
                  artist: artist,
                  onPlay: songs.isEmpty
                      ? null
                      : () => _playTracks(context, ref, songs, 0),
                  onShuffle: songs.length < 2
                      ? null
                      : () =>
                            _playTracks(context, ref, songs, 0, shuffled: true),
                ),
                if (artist.description != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: InkWell(
                      onTap: () => setState(() => _fullBio = !_fullBio),
                      borderRadius: BorderRadius.circular(8),
                      child: Text(
                        artist.description!,
                        maxLines: _fullBio ? null : 3,
                        overflow: _fullBio ? null : TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                if (songs.isNotEmpty) ...[
                  const _SectionTitle('Canciones destacadas'),
                  for (final (index, track) in songs.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SongRow(
                        key: ValueKey('top:${track.id}'),
                        url: track.thumbnailUrl,
                        title: track.title,
                        subtitle: track.artist,
                        onTap: () => _playTracks(context, ref, songs, index),
                        onLongPress: () =>
                            unawaited(showTrackSheet(context, ref, track)),
                        trailing: track.albumId == null
                            ? null
                            : IconButton(
                                tooltip: 'Ver álbum',
                                icon: const Icon(Icons.album_outlined),
                                onPressed: () =>
                                    openAlbum(context, track.albumId!),
                              ),
                      ),
                    ),
                ],
                for (final shelf in artist.shelves) ...[
                  _SectionTitle(shelf.title),
                  _AlbumShelf(
                    albums: shelf.items.whereType<MusicAlbum>().toList(),
                  ),
                ],
                if (songs.isEmpty && artist.shelves.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Este artista aún no tiene música disponible.'),
                  ),
              ],
            ),
            const _StatusScrim(),
          ],
        ),
      );
    },
  );
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.artist,
    required this.onPlay,
    required this.onShuffle,
  });

  final ArtistProfile artist;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), paper = theme.colorScheme.surface;
    final width = MediaQuery.sizeOf(context).width;
    // 1:1 como en Limusic, con tope para que en pantallas anchas quepa texto.
    final side = width.clamp(0.0, 520.0).toDouble();
    return SizedBox(
      height: side,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: TrackArtwork(
              url: artist.thumbnailUrl,
              size: side,
              borderRadius: 0,
              fallbackIcon: Icons.person_outline,
            ),
          ),
          // Velo que funde la foto con el fondo en el 70 % inferior. Las
          // paradas intermedias siguen una curva suave para no dejar banda.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .3, .55, .78, 1],
                colors: [
                  paper.withValues(alpha: .25),
                  paper.withValues(alpha: 0),
                  paper.withValues(alpha: .32),
                  paper.withValues(alpha: .82),
                  paper,
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: const _FloatingBack(),
          ),
          Positioned(
            left: 16,
            right: 12,
            bottom: 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ARTISTA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        artist.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 28,
                          height: 1.14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (artist.audience != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            artist.audience!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _PlayActions(onPlay: onPlay, onShuffle: onShuffle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Estante de la discografía: cada álbum es su portada con medio disco de
/// vinilo asomando por la derecha.
class _AlbumShelf extends ConsumerWidget {
  const _AlbumShelf({required this.albums});
  final List<MusicAlbum> albums;

  static const _cover = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _cover + 14 + MediaQuery.textScalerOf(context).scale(46),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final album = albums[index];
          return InkWell(
            key: ValueKey('album:${album.id}'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => openAlbum(
              context,
              album.id,
              seed: PageSeed(title: album.title, imageUrl: album.thumbnailUrl),
            ),
            onLongPress: () => showItemMenu(context, ref, album),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AlbumDiscArt(size: _cover, url: album.thumbnailUrl),
                const SizedBox(height: 8),
                SizedBox(
                  width: _cover + 40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        album.detail ?? 'Álbum',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Álbum
// ---------------------------------------------------------------------------

/// Página de álbum: la portada con medio disco de vinilo a su lado, el
/// artista enlazado y las pistas numeradas.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.id, this.seed});
  final String id;
  final PageSeed? seed;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with _PageLoader<AlbumScreen, AlbumDetail> {
  @override
  Future<AlbumDetail> fetch(MusicModeController music, CancelToken cancel) =>
      music.albumDetail(widget.id, cancelToken: cancel);

  @override
  List<MusicTrack> songsOf(AlbumDetail page) => page.tracks;

  static String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => FutureBuilder<AlbumDetail>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(error: snapshot.error, retry: load);
      }
      final album = snapshot.data;
      if (album == null) return _SeedLoading(seed: widget.seed);
      final theme = Theme.of(context), colors = theme.colorScheme;
      final tracks = album.tracks;
      final width = MediaQuery.sizeOf(context).width;
      // La portada y su medio disco (45 % más de ancho) caben centrados.
      final cover = ((width - 64) / 1.45).clamp(120.0, 230.0).toDouble();
      return Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              // Cabecera + una fila por pista: los álbumes largos no se
              // construyen enteros.
              itemCount: tracks.length + 1,
              itemBuilder: (context, row) {
                if (row > 0) {
                  final index = row - 1, track = tracks[index];
                  return InkWell(
                    key: ValueKey('track:${track.id}'),
                    onTap: () => _playTracks(context, ref, tracks, index),
                    onLongPress: () =>
                        unawaited(showTrackSheet(context, ref, track)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (track.durationSeconds > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                _time(track.durationSeconds),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        MediaQuery.paddingOf(context).top + 8,
                        12,
                        0,
                      ),
                      child: Row(
                        children: [
                          const _FloatingBack(),
                          const Spacer(),
                          // Las mismas opciones que al mantener pulsado el
                          // álbum: reproducir, cola, radio, guardar, atajo…
                          IconButton(
                            tooltip: 'Opciones',
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(48),
                              backgroundColor: colors.surfaceContainerHighest
                                  .withValues(alpha: .82),
                              foregroundColor: colors.onSurface,
                            ),
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => unawaited(
                              showItemMenu(
                                context,
                                ref,
                                MusicAlbum(
                                  widget.id,
                                  album.title,
                                  thumbnailUrl: album.thumbnailUrl,
                                  artist: album.artist,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: AlbumDiscArt(size: cover, url: album.thumbnailUrl),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 12, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ['ÁLBUM', ?album.year].join(' • '),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 1,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  album.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontSize: 28,
                                        height: 1.14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          // Descargar y guardar en la biblioteca; reproducir y
                          // aleatorio están en la hoja de tres puntos.
                          CollectionActions(
                            id: widget.id,
                            album: true,
                            tracks: tracks,
                            title: album.title,
                            subtitle: album.artist,
                            thumbnailUrl: album.thumbnailUrl,
                          ),
                        ],
                      ),
                    ),
                    // Enlace al artista del álbum.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextButton.icon(
                        onPressed: album.artistId == null
                            ? null
                            : () => openArtist(context, album.artistId!),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onSurface,
                          disabledForegroundColor: colors.onSurface,
                        ),
                        icon: const Icon(Icons.person_rounded, size: 20),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                album.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (album.artistId != null)
                              const Icon(Icons.chevron_right_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                    if (album.info != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Text(
                          album.info!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const _StatusScrim(),
          ],
        ),
      );
    },
  );
}
