import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../playback/application/playback_providers.dart';
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../domain/music_mode.dart';
import 'catalog_pages.dart';
import 'cover_art.dart';
import 'library_screen.dart' show LibrarySectionHeader;
import 'music_mode_host.dart';
import 'track_sheet.dart';

/// Lo que la tesela tocada ya sabe del ambiente o género que se abre.
class MoodSeed {
  const MoodSeed({
    required this.params,
    required this.title,
    this.color,
    this.artwork,
    this.kicker,
  });

  final String params;
  final String title;

  /// El color de YouTube para la categoría (ARGB).
  final int? color;
  final String? artwork;

  /// La sección de la que viene («Ambientes», «Géneros»).
  final String? kicker;
}

/// La página de un ambiente o género (Limusic `MoodScreen`): la tesela,
/// crecida, como cabecera, y cada sección de YouTube («Playlists destacadas»,
/// «Playlists de la comunidad») como una cuadrícula de portadas a dos
/// columnas.
class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen({super.key, required this.seed});

  final MoodSeed seed;

  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  static const _hero = 300.0;

  final _scroll = ScrollController();
  final _pastHero = ValueNotifier(false);
  MusicPage? _page;
  bool _loading = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final bar = MediaQuery.paddingOf(context).top + 64;
      _pastHero.value = _scroll.offset > _hero - bar - 40;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pastHero.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final music = MusicModeScope.of(context);
    final generation = music?.connection?.generation;
    if (music == null || generation == null || _loading) return;
    setState(() => _loading = true);
    try {
      final page = await music.ask(
        generation,
        (client) => client.moodPage(widget.seed.params),
      );
      if (mounted) setState(() => _page = page);
    } on Object {
      // Se ofrece reintentar.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String? _coverOf(MusicItem item) => switch (item) {
    MusicTrack() => item.thumbnailUrl,
    MusicArtist() => item.thumbnailUrl,
    MusicAlbum() => item.thumbnailUrl,
    MusicPlaylist() => item.thumbnailUrl,
  };

  void _open(MusicItem item) {
    final seed = PageSeed(title: item.title, imageUrl: _coverOf(item));
    switch (item) {
      case MusicPlaylist():
        context.push(
          '/music/playlist/${Uri.encodeComponent(item.id)}',
          extra: seed,
        );
      case MusicAlbum():
        openAlbum(context, item.id, seed: seed);
      case MusicArtist():
        openArtist(context, item.id, seed: seed);
      case MusicTrack():
        // Una canción suelta suena con su radio.
        final music = MusicModeScope.of(context);
        final generation = music?.connection?.generation;
        if (music == null ||
            generation == null ||
            !music.isCurrent(generation) ||
            !canPlayMusicTrack(music, item)) {
          return;
        }
        unawaited(
          ref.read(trackPlaybackControllerProvider).playQueue([
            music.playbackTrack(generation, item),
          ], listenForTrack: () => music.listenForTrack(generation)),
        );
        context.push('/player');
    }
  }

  void _hold(MusicItem item) => unawaited(showItemMenu(context, ref, item));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final seed = widget.seed;
    final page = _page;
    // Las secciones, en el orden en que llegan.
    final sections = <String, List<MusicItem>>{};
    for (final item in page?.items ?? const <MusicItem>[]) {
      sections.putIfAbsent(item.shelfTitle ?? '', () => []).add(item);
    }
    final playlists = page?.items.whereType<MusicPlaylist>().length ?? 0;
    final title = seed.title.isNotEmpty ? seed.title : (page?.title ?? '');
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _MoodHero(
                  height: _hero,
                  color: seed.color == null || seed.color == 0
                      ? colors.primary
                      : Color(seed.color!),
                  artwork:
                      seed.artwork ??
                      page?.items.map(_coverOf).whereType<String>().firstOrNull,
                  kicker: seed.kicker,
                  title: title,
                  count: playlists == 0
                      ? null
                      : playlists == 1
                      ? '1 playlist'
                      : '$playlists playlists',
                ),
              ),
              if (page == null && _loading)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (page == null || sections.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Text(
                          page == null
                              ? 'No se pudo cargar esta categoría.'
                              : 'Esta categoría no tiene playlists.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (page == null)
                          TextButton(
                            onPressed: () => unawaited(_load()),
                            child: const Text('Reintentar'),
                          ),
                      ],
                    ),
                  ),
                )
              else
                for (final (index, entry) in sections.entries.indexed) ...[
                  if (entry.key.isNotEmpty)
                    SliverToBoxAdapter(
                      child: LibrarySectionHeader(
                        title: entry.key,
                        padding: EdgeInsets.only(top: index == 0 ? 4 : 16),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverLayoutBuilder(
                      builder: (context, box) {
                        final cell = (box.crossAxisExtent - 4) / 2;
                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 4,
                                // Portada cuadrada, dos líneas de título y una
                                // de subtítulo.
                                mainAxisExtent:
                                    cell +
                                    16 +
                                    MediaQuery.textScalerOf(context).scale(62),
                              ),
                          itemCount: entry.value.length,
                          itemBuilder: (context, i) {
                            final item = entry.value[i];
                            return _MoodCard(
                              key: ValueKey('$index:${item.id}'),
                              title: item.title,
                              subtitle: switch (item) {
                                MusicTrack() => item.artist,
                                MusicAlbum() => item.detail ?? 'Álbum',
                                MusicArtist() => 'Artista',
                                MusicPlaylist() => 'Playlist',
                              },
                              url: _coverOf(item),
                              round: item is MusicArtist,
                              onTap: () => _open(item),
                              onLongPress: () => _hold(item),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 24 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
          // Atrás flota sobre la cabecera; cuando el nombre pasa bajo el
          // borde, una barra con el nombre toma su sitio.
          ValueListenableBuilder(
            valueListenable: _pastHero,
            builder: (context, past, _) => Stack(
              children: [
                IgnorePointer(
                  ignoring: !past,
                  child: AnimatedOpacity(
                    opacity: past ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Material(
                      color: colors.surface,
                      child: Padding(
                        padding: EdgeInsets.only(top: top),
                        child: SizedBox(
                          height: 64,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 60, right: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: top + 8,
                  left: 8,
                  child: IconButton(
                    tooltip: 'Atrás',
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(48),
                      backgroundColor: past
                          ? Colors.transparent
                          : colors.surface.withValues(alpha: .55),
                    ),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => context.pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La cabecera (Limusic `MoodHero`): el color de la categoría como un lavado,
/// su portada desenfocada hasta ser una textura y el color de la página
/// subiendo desde abajo; encima, la sección, el nombre y cuántas playlists.
class _MoodHero extends StatelessWidget {
  const _MoodHero({
    required this.height,
    required this.color,
    required this.title,
    this.artwork,
    this.kicker,
    this.count,
  });

  final double height;
  final Color color;
  final String? artwork;
  final String? kicker;
  final String title;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final paper = colors.surface;
    return ClipRect(
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: color.withValues(alpha: .55)),
            // Sin desenfoque («Reducir efectos»), el color lleva la cabecera.
            if (artwork != null && !EffectsScope.reducedOf(context))
              Opacity(
                opacity: .5,
                child: Transform.scale(
                  scale: 1.2,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 36,
                      sigmaY: 36,
                      tileMode: TileMode.clamp,
                    ),
                    child: CoverArt(artwork!, pixels: 96),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: .8,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        paper.withValues(alpha: 0),
                        paper.withValues(alpha: .6),
                        paper,
                      ],
                      stops: const [0, .6, 1],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null && kicker!.isNotEmpty)
                      Text(
                        kicker!.toUpperCase(),
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 34,
                        height: 38 / 34,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (count != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          count!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una portada sobre su título y su línea (Limusic `CoverCard`): toque de
/// radio 16 con 4 dp de aire, carátula de radio 14 (redonda si es un artista).
class _MoodCard extends StatelessWidget {
  const _MoodCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    this.url,
    this.round = false,
  });

  final String title;
  final String subtitle;
  final String? url;
  final bool round;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: round
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              TrackArtwork(
                url: url,
                size: box.maxWidth,
                borderRadius: round ? box.maxWidth / 2 : 14,
                fallbackIcon: Icons.queue_music,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: round ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: round ? TextAlign.center : TextAlign.start,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
