import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/images/disk_cached_image.dart';
import '../../connected_library/domain/music_mode.dart'
    show MusicTrack, TrackLinks;
import '../../connected_library/presentation/catalog_pages.dart';
import '../../connected_library/presentation/library_screen.dart'
    show LibraryChip;
import '../../connected_library/presentation/music_mode_host.dart';
import '../../connected_library/presentation/track_sheet.dart';
import '../../lyrics/data/lyrics_repository.dart';
import '../../lyrics/presentation/lyrics_sheet.dart';
import '../../search/domain/catalog_track.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../../search/presentation/item_sheet.dart';
import '../../ytm/data/liked_tracks.dart';
import '../application/playback_providers.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import 'playback_progress.dart';
import 'player_backdrop.dart';
import 'player_carousel.dart';
import 'player_queue_sheet.dart';
import 'player_sheets.dart';

/// Lo que enseña el centro del reproductor. Los controles de debajo son los
/// mismos en las tres vistas (Limusic `ClassicView`).
enum _View { player, queue, lyrics }

/// El reproductor a pantalla completa, con la disposición del «Classic» de
/// Limusic (`NowPlayingContentLimusic`): una portada grande con la línea de
/// letra que suena debajo, título y artista con el corazón, la barra ondulada,
/// tres píldoras de transporte y una fila de cuadrados al pie (guardar,
/// repetir, letra, aleatorio, cola) con el menú de la canción a la derecha.
///
/// Cola y Letra son vistas de la misma página: ocupan el sitio de la portada
/// y los controles se quedan donde están.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _gutter = 24.0;

  /// Margen de la portada: lo que queda a cada lado para sus vecinas.
  static const _coverMargin = 72.0;

  var _view = _View.player;

  // En Cola y Letra las píldoras se recogen tras unos segundos sin tocar, para
  // dejar sitio a la lista y a las líneas; un toque las devuelve.
  var _pillsShown = true;
  Timer? _hide;

  // Cada doble toque sobre la portada lanza un corazón.
  var _hearts = 0;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _touched() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && _view != _View.player) {
        setState(() => _pillsShown = false);
      }
    });
    if (!_pillsShown) setState(() => _pillsShown = true);
  }

  /// Tocar el cuadrado de la vista que se ve vuelve a la portada.
  void _toggle(_View view) {
    setState(() => _view = _view == view ? _View.player : view);
    _touched();
  }

  LikedTracks? get _likes {
    try {
      return ref.watch(likedTracksProvider);
    } on Object {
      return null;
    }
  }

  static String? _youtubeId(CatalogTrack track) =>
      track.id.startsWith('youtube:') ? track.id.substring(8) : null;

  /// La canción que suena como elemento de la biblioteca, para sus hojas.
  static MusicTrack? _musicTrack(CatalogTrack track) {
    final id = _youtubeId(track);
    if (id == null) return null;
    return MusicTrack(
      id,
      track.title,
      track.artistName,
      track.durationSeconds ?? 0,
      false,
      null,
      nativePlayback: true,
      artistId: track.artistId,
      albumId: track.albumId,
      albumName: track.albumName,
      thumbnailUrl: track.thumbnailUrl,
    );
  }

  bool _linkable(TrackPlaybackController controller) =>
      !controller.isBundledTrack &&
      controller.current?.id.startsWith('youtube:') == true &&
      MusicModeScope.of(context)?.hasPublicCatalog == true;

  void _openLink(CatalogTrack track, {required bool album}) => unawaited(
    openTrackLink(
      context,
      album: album,
      videoId: track.id.substring(8),
      title: track.title,
      artist: track.artistName,
      artistId: track.artistId,
      albumId: track.albumId,
    ),
  );

  void _like(CatalogTrack track, {bool burst = false}) {
    final id = _youtubeId(track);
    final likes = _likes;
    if (id == null || likes == null) return;
    // El doble toque solo da Me gusta, nunca lo quita.
    if (burst) {
      setState(() => _hearts++);
      if (likes.isLiked(id)) return;
    }
    unawaited(likes.toggle(id));
  }

  Future<void> _openOutput() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await const MethodChannel(
        'com.mysic/audio_output',
      ).invokeMethod<void>('open');
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Configura la salida de audio desde los ajustes del dispositivo.',
          ),
        ),
      );
    }
  }

  /// Las filas que solo tiene la hoja de la canción que suena (Limusic: «the
  /// player's own rows»).
  List<SheetRow> _playerRows(
    TrackPlaybackController controller,
    CatalogTrack track,
  ) => [
    SheetRow(
      icon: Icons.access_alarm_rounded,
      label: 'Temporizador de apagado',
      subtitle: controller.sleepAtTrackEnd
          ? 'Al acabar la canción'
          : controller.sleepActive
          ? 'Quedan ${controller.sleepMinutesLeft} min'
          : null,
      onTap: () => unawaited(showSleepTimerSheet(context, controller)),
    ),
    // Una radio en directo no se acelera ni se afina, ni tiene ficha de canción.
    if (controller.canTune && !track.isLive)
      SheetRow(
        icon: Icons.speed_rounded,
        label: 'Velocidad y tono',
        subtitle: controller.speed != 1 || controller.pitch != 0
            ? 'x${controller.speed.toStringAsFixed(1)} · tono '
                  '${controller.pitch}'
            : null,
        onTap: () => unawaited(showTuningSheet(context, controller)),
      ),
    if (!track.isLive)
      SheetRow(
        icon: Icons.info_outline_rounded,
        label: 'Información de la canción',
        onTap: () => unawaited(showSongInfoSheet(context, track, controller)),
      ),
    SheetRow(
      icon: Icons.stop_circle_outlined,
      label: 'Detener reproducción',
      onTap: () => unawaited(controller.stop()),
    ),
  ];

  /// La hoja de la canción que suena (Limusic `NowPlayingBottomSheet` con las
  /// filas del reproductor).
  void _openMenu(TrackPlaybackController controller, CatalogTrack track) {
    final music = _musicTrack(track);
    if (music != null && MusicModeScope.of(context) != null) {
      unawaited(
        showTrackSheet(
          context,
          ref,
          music,
          playerRows: () => _playerRows(controller, track),
          playerRefresh: controller,
        ),
      );
      return;
    }
    // Una muestra o un archivo propio: solo lo del reproductor.
    unawaited(
      showItemSheet(
        context,
        header: SheetHeader(
          title: track.title,
          subtitle: track.artistName,
          url: track.thumbnailUrl,
        ),
        refresh: controller,
        rows: () => _playerRows(controller, track),
      ),
    );
  }

  void _saveToPlaylist(CatalogTrack track) {
    final music = _musicTrack(track);
    if (music != null) unawaited(showSaveToPlaylist(context, ref, [music]));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final track = controller.current;
        final ImageProvider<Object>? artwork = controller.isBundledTrack
            ? const AssetImage('assets/images/discover-mountains.webp')
            : switch (track?.thumbnailUrl) {
                // Va desenfocada: basta el archivo pequeño que ya guardó la
                // caché de disco al pintar la fila.
                final String url => DiskCachedImage(
                  TrackArtwork.sizedUrl(url, 160),
                ),
                _ => null,
              };
        return PlayerBackdrop(
          artwork: artwork,
          builder: (context, theme, backdrop) => PopScope(
            // Atrás deja Cola o Letra por la portada antes de cerrar.
            canPop: _view == _View.player,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _view = _View.player);
            },
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(child: backdrop),
                  SafeArea(
                    child: Listener(
                      onPointerDown: (_) => _touched(),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: track == null
                              ? _empty(context)
                              : _page(context, theme, controller, track),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) => Column(
    children: [
      _TopRow(title: 'Reproductor', onClose: () => context.pop()),
      const Expanded(
        child: Center(child: Text('Elige una canción para empezar')),
      ),
    ],
  );

  Widget _page(
    BuildContext context,
    ThemeData theme,
    TrackPlaybackController controller,
    CatalogTrack track,
  ) {
    final colors = theme.colorScheme;
    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: KeyedSubtree(
              key: ValueKey(_view),
              child: switch (_view) {
                _View.player => _playerView(context, theme, controller, track),
                _View.queue => Column(
                  children: [
                    _TopRow(
                      title: 'Cola',
                      onClose: () => setState(() => _view = _View.player),
                    ),
                    Expanded(
                      child: PlayerQueueSheet(
                        controller: controller,
                        embedded: true,
                        musicLikesLabel: MusicModeScope.of(
                          context,
                        )?.connection?.likesActionLabel,
                        openMusicLikes: () => context.push('/music/liked'),
                      ),
                    ),
                  ],
                ),
                _View.lyrics => Column(
                  children: [
                    _TopRow(
                      title: 'Letra',
                      onClose: () => setState(() => _view = _View.player),
                    ),
                    Expanded(child: LyricsSheet(controller: controller)),
                  ],
                ),
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.isLive) ...[
                // ROVR da cuándo empieza y acaba el programa: su línea de tiempo.
                if (controller.liveStartedAt != null &&
                    controller.liveEndsAt != null)
                  LiveTimeline(controller: controller),
                _LiveBadge(
                  playing: controller.phase == TrackAudioPhase.playing,
                ),
              ] else
                PlaybackProgress(
                  key: ValueKey(track.id),
                  controller: controller,
                ),
              if (controller.phase == TrackAudioPhase.error)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.sourceBlocked
                        ? 'YouTube está pidiendo confirmar que no eres un bot '
                              'desde esta red, así que las canciones nuevas no '
                              'se pueden reproducir por ahora. Las canciones '
                              'descargadas siguen sonando.'
                        : 'Esta pista no se pudo reproducir. Reintenta o elige '
                              'otra.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _view == _View.player || _pillsShown
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _TransportRow(
                          controller: controller,
                          live: track.isLive,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 12),
              _bottomRow(colors, controller, track),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  /// La portada, la línea de letra que suena y el título. Deslizar la portada
  /// hacia arriba abre la cola.
  Widget _playerView(
    BuildContext context,
    ThemeData theme,
    TrackPlaybackController controller,
    CatalogTrack track,
  ) {
    final colors = theme.colorScheme;
    final likes = _likes;
    final id = _youtubeId(track);
    final linkable = _linkable(controller);
    // Una radio dice lo que suena ahora; mientras no, su nombre y su dial.
    final nowPlaying = track.isLive && controller.liveTitle != null;
    final artistText = !track.isLive
        ? track.artistName
        : nowPlaying
        ? controller.liveArtist ?? track.title
        : track.artistName;
    final titleText = nowPlaying ? controller.liveTitle! : track.title;
    return Column(
      children: [
        _TopRow(
          title: 'Reproduciendo',
          onClose: () => context.pop(),
          trailing: IconButton(
            tooltip: 'Salida de audio',
            color: colors.onSurface,
            icon: const Icon(Icons.headphones_rounded),
            onPressed: () => unawaited(_openOutput()),
          ),
        ),
        // Las señales de la emisora, bajo «Reproduciendo»: «Radio» y sus moods.
        if (track.isLive && controller.liveMoodOptions.isNotEmpty)
          _MoodPills(controller: controller, track: track),
        // Portada, línea de letra y título van juntos con huecos fijos; la
        // altura que sobra queda sobre la portada. Donde falta sitio (pantalla
        // baja, letra grande) encoge la portada, no los huecos ni el título.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final side = math
                        .min(
                          // Algo más estrecha que el texto, para que la
                          // anterior y la siguiente asomen a los lados.
                          box.maxWidth - _coverMargin * 2,
                          box.maxHeight - PlayerCoverCarousel.gap * 2,
                        )
                        .clamp(0.0, 440.0)
                        .toDouble();
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        RepaintBoundary(
                          child: PlayerCoverCarousel(
                            controller: controller,
                            side: side,
                            // Una radio no tiene cola que abrir.
                            onSwipeUp: track.isLive
                                ? null
                                : () => setState(() => _view = _View.queue),
                            onDoubleTap: () => _like(track, burst: true),
                            onLongPress: () => _openMenu(controller, track),
                          ),
                        ),
                        if (_hearts > 0)
                          IgnorePointer(
                            child: _HeartBurst(key: ValueKey(_hearts)),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                child: controller.isBundledTrack || track.isLive
                    ? const SizedBox(height: _LyricLine.height)
                    : _LyricLine(
                        key: ValueKey(track.id),
                        track: track,
                        controller: controller,
                      ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Encima del título, el artista como enlace a su página.
                    InkWell(
                      onTap: linkable
                          ? () => _openLink(track, album: false)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Text(
                        artistText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          decoration: linkable
                              ? TextDecoration.underline
                              : null,
                          decorationColor: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // El corazón va en la línea del título.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (likes != null && id != null)
                          ListenableBuilder(
                            listenable: likes,
                            builder: (context, _) {
                              final liked = likes.isLiked(id);
                              return IconButton(
                                tooltip: liked ? 'Quitar Me gusta' : 'Me gusta',
                                iconSize: 28,
                                style: IconButton.styleFrom(
                                  fixedSize: const Size.square(40),
                                  padding: EdgeInsets.zero,
                                ),
                                color: liked
                                    ? colors.primary
                                    : colors.onSurface,
                                icon: Icon(
                                  liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                                onPressed: () => _like(track),
                              );
                            },
                          )
                        else
                          const SizedBox(height: 40),
                      ],
                    ),
                    // Debajo, el álbum como enlace a su página.
                    if (linkable)
                      _AlbumLink(key: ValueKey(track.id), track: track)
                    else if (nowPlaying)
                      // La emisora y su dial, donde iría el álbum.
                      // Todo a la izquierda: la emisora con su programa y quién
                      // lo presenta («BY …») y, si la hay, la discográfica.
                      SizedBox(
                        height: _AlbumLink.height,
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              [
                                track.title,
                                if (controller.liveProgram != null)
                                  controller.liveProgram!
                                else
                                  track.artistName,
                                if (controller.liveCurator != null)
                                  'by ${controller.liveCurator}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            if (controller.liveLabel != null)
                              Text(
                                controller.liveLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: _AlbumLink.height),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  /// Guardar en playlist, repetir, Letra, aleatorio y Cola como cuadrados con
  /// borde; el menú de la canción, relleno, a la derecha. Cola y Letra se
  /// encienden mientras su vista está en pantalla.
  Widget _bottomRow(
    ColorScheme colors,
    TrackPlaybackController controller,
    CatalogTrack track,
  ) {
    // Una radio en directo no tiene cola, repetir, aleatorio, letra ni lista
    // donde guardarla: solo el menú (temporizador de apagado, detener…).
    if (track.isLive) {
      return Row(
        children: [
          const Spacer(),
          IconButton.filled(
            tooltip: 'Opciones de la radio',
            style: IconButton.styleFrom(fixedSize: const Size.square(46)),
            icon: const Icon(Icons.more_vert),
            onPressed: () => _openMenu(controller, track),
          ),
        ],
      );
    }
    final direct =
        _youtubeId(track) != null &&
        MusicModeScope.of(context)?.connection?.isDirect == true;
    return Row(
      children: [
        _Square(
          tooltip: 'Guardar en playlist',
          icon: Icons.playlist_add_rounded,
          onPressed: direct ? () => _saveToPlaylist(track) : null,
        ),
        const SizedBox(width: 10),
        _Square(
          tooltip: switch (controller.repeat) {
            PlaybackRepeat.off => 'Repetir desactivado',
            PlaybackRepeat.all => 'Repetir cola',
            PlaybackRepeat.one => 'Repetir canción',
          },
          icon: controller.repeat == PlaybackRepeat.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          active: controller.repeat != PlaybackRepeat.off,
          onPressed: controller.cycleRepeat,
        ),
        const SizedBox(width: 10),
        _Square(
          tooltip: 'Letra',
          icon: Icons.lyrics_outlined,
          active: _view == _View.lyrics,
          onPressed: controller.isBundledTrack || track.isLive
              ? null
              : () => _toggle(_View.lyrics),
        ),
        const SizedBox(width: 10),
        _Square(
          tooltip: 'Aleatorio',
          icon: Icons.shuffle_rounded,
          active: controller.shuffleEnabled,
          onPressed: controller.queue.length < 2
              ? null
              : controller.toggleShuffle,
        ),
        const SizedBox(width: 10),
        _Square(
          tooltip: 'Cola',
          icon: Icons.queue_music_rounded,
          active: _view == _View.queue,
          onPressed: () => _toggle(_View.queue),
        ),
        const Spacer(),
        IconButton.filled(
          tooltip: 'Opciones de la canción',
          style: IconButton.styleFrom(fixedSize: const Size.square(46)),
          icon: const Icon(Icons.more_vert),
          onPressed: () => _openMenu(controller, track),
        ),
      ],
    );
  }
}

/// Las pastillas «RADIO · mood · mood…» de una emisora con varias señales
/// (ROVR). La que suena va rellena; tocar otra cambia de señal.
class _MoodPills extends StatelessWidget {
  const _MoodPills({required this.controller, required this.track});

  final TrackPlaybackController controller;
  final CatalogTrack track;

  /// «DRIVE» → «Drive»: como las pastillas de la Biblioteca.
  static String _capital(String text) => text.isEmpty
      ? text
      : text[0].toUpperCase() + text.substring(1).toLowerCase();

  @override
  Widget build(BuildContext context) {
    // La pista de la emisora («Radio»): la propia, o de la que cuelga el mood.
    final radio = track.liveParent ?? track;
    final onRadio = track.liveParent == null;
    // Las mismas pastillas que los filtros de la Biblioteca (`LibraryChip`):
    // la elegida va rellena del acento; tocar otra cambia de señal.
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        children: [
          LibraryChip(
            label: 'Radio',
            selected: onRadio,
            onTap: () {
              if (!onRadio) unawaited(controller.playQueue([radio]));
            },
          ),
          for (final mood in controller.liveMoodOptions) ...[
            const SizedBox(width: 8),
            LibraryChip(
              label: _capital(mood.title),
              selected: track.id.endsWith(':${mood.id}'),
              onTap: () {
                if (!track.id.endsWith(':${mood.id}')) {
                  unawaited(controller.playQueue([mood.toTrack(radio)]));
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// En lugar de la barra de progreso: una radio no tiene principio ni fin.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A la izquierda, como el resto de los datos de la radio.
    return SizedBox(
      height: 40,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 9,
                color: playing ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                'EN VIVO',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La fila de arriba: cerrar a la izquierda, lo que se está viendo en el
/// centro y, en la portada, la salida de audio a la derecha.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.title, required this.onClose, this.trailing});

  final String title;
  final VoidCallback onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cerrar',
            color: theme.colorScheme.onSurface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: onClose,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing ?? const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// Anterior, reproducir o pausar y siguiente: tres píldoras del color de la
/// portada, la del centro la más ancha (Limusic `ClassicTransportRow`).
class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.controller, this.live = false});

  final TrackPlaybackController controller;

  /// Una radio en directo: un solo botón, como en la web de ROVR. Parar y
  /// volver a sintonizar; no hay anterior ni siguiente.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final playing = controller.phase == TrackAudioPhase.playing;
    final loading = controller.phase == TrackAudioPhase.loading;
    ButtonStyle pill(Size size) => IconButton.styleFrom(
      fixedSize: size,
      shape: const StadiumBorder(),
      padding: EdgeInsets.zero,
    );
    if (live) {
      return Center(
        child: IconButton.filled(
          tooltip: playing || loading ? 'Detener' : 'Sintonizar',
          style: pill(const Size(120, 80)),
          iconSize: 42,
          // Mientras sintoniza no hay nada que parar: se espera a que suene.
          onPressed: loading
              ? null
              : () => unawaited(
                  playing ? controller.pause() : controller.resume(),
                ),
          icon: loading
              ? const SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
        ),
      );
    }
    // En pantallas estrechas las tres encogen juntas.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            tooltip: 'Anterior',
            style: pill(const Size(80, 64)),
            iconSize: 32,
            onPressed: controller.hasPrevious
                ? () => unawaited(controller.previous())
                : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: playing ? 'Pausar' : 'Reproducir',
            style: pill(const Size(120, 80)),
            iconSize: 42,
            onPressed: loading
                ? null
                : () => unawaited(
                    playing ? controller.pause() : controller.resume(),
                  ),
            icon: loading
                ? const SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: 'Siguiente',
            style: pill(const Size(80, 64)),
            iconSize: 32,
            onPressed: controller.hasNext
                ? () => unawaited(controller.next())
                : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }
}

/// Un cuadrado pequeño con borde (Limusic `OutlinedButton`); [active] lo
/// enciende con el color de la portada (aleatorio activo, la vista abierta).
class _Square extends StatelessWidget {
  const _Square({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = active ? colors.primary : colors.onSurface;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 22,
      color: color,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(44),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: color.withValues(
              alpha: onPressed == null
                  ? .12
                  : active
                  ? .9
                  : .3,
            ),
          ),
        ),
      ),
      icon: Icon(icon),
    );
  }
}

/// La línea de letra que suena, bajo la portada (Limusic `CoverLyricLine`).
/// Solo con letra sincronizada; si no la hay, el hueco se queda vacío para que
/// nada salte.
class _LyricLine extends ConsumerWidget {
  const _LyricLine({super.key, required this.track, required this.controller});

  final CatalogTrack track;
  final TrackPlaybackController controller;

  static const height = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(trackLyricsProvider(track)).value;
    if (lyrics == null || !lyrics.isSynced) {
      return const SizedBox(height: height);
    }
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: ValueListenableBuilder<Duration>(
        valueListenable: controller.positionListenable,
        builder: (context, _, _) {
          final now = controller.position;
          var text = '';
          for (final line in lyrics.lines) {
            if (line.start > now) break;
            text = line.text;
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Center(
              key: ValueKey(text),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// El corazón del doble toque: crece, se queda un instante y se va.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 700),
    builder: (context, t, child) => Opacity(
      opacity: t < .7 ? 1 : (1 - t) / .3,
      child: Transform.scale(
        scale: .5 + .7 * Curves.elasticOut.transform(math.min(1, t / .6)),
        child: child,
      ),
    ),
    child: const Icon(
      Icons.favorite_rounded,
      size: 96,
      color: Colors.white,
      shadows: [Shadow(color: Color(0x66000000), blurRadius: 18)],
    ),
  );
}

/// El álbum de la canción bajo su título, como enlace a su página. El nombre
/// no siempre viene con la canción: se resuelve una vez por pista (con caché)
/// y la línea reserva su alto para que el reproductor no salte al llegar.
class _AlbumLink extends StatefulWidget {
  const _AlbumLink({super.key, required this.track});

  final CatalogTrack track;

  static const height = 26.0;

  @override
  State<_AlbumLink> createState() => _AlbumLinkState();
}

class _AlbumLinkState extends State<_AlbumLink> {
  TrackLinks? _links;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    final music = MusicModeScope.of(context);
    if (music == null) return;
    _asked = true;
    final track = widget.track;
    // Si la canción ya trae su álbum con nombre no hay nada que buscar.
    if (track.albumId != null && track.albumName != null) {
      _links = (
        artistId: track.artistId,
        albumId: track.albumId,
        album: track.albumName,
      );
      return;
    }
    unawaited(
      music
          .trackLinks(
            videoId: track.id.substring(8),
            title: track.title,
            artist: track.artistName,
            artistId: track.artistId,
            albumId: track.albumId,
            withAlbumName: true,
          )
          .then<void>(
            (links) {
              if (mounted) setState(() => _links = links);
            },
            // Sin red no hay enlace; el menú «Ir al álbum» sigue disponible.
            onError: (Object _) {},
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final links = _links;
    final id = links?.albumId;
    return SizedBox(
      height: _AlbumLink.height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        child: id == null
            ? const SizedBox.shrink()
            : InkWell(
                onTap: () => context.push('/album/$id'),
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.album_outlined, size: 16, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        links?.album ?? 'Ver álbum',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          decoration: TextDecoration.underline,
                          decorationColor: color,
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
