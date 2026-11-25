import 'dart:async';

import 'package:flutter/material.dart';

import '../../search/presentation/catalog_widgets.dart';
import '../application/track_playback_controller.dart';
import 'artwork_prefetch.dart';
import 'live_cover.dart';

/// La portada del reproductor y sus vecinas: la que suena, grande y en el
/// centro, con la anterior y la siguiente asomando a los lados, algo más
/// pequeñas y atenuadas. Deslizar a los lados o tocar una vecina cambia de
/// canción; deslizar hacia arriba abre la cola; dos toques dan Me gusta y
/// mantener pulsado abre el menú de la canción.
///
/// Solo existen las páginas a la vista: [PageView.builder] construye las demás
/// bajo demanda, así que una cola de cien canciones cuesta lo mismo que una de
/// tres.
class PlayerCoverCarousel extends StatefulWidget {
  const PlayerCoverCarousel({
    super.key,
    required this.controller,
    required this.side,
    this.onSwipeUp,
    this.onDoubleTap,
    this.onLongPress,
  });

  final TrackPlaybackController controller;

  /// Lado de la portada.
  final double side;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  /// Aire sobre y bajo la portada: ahí se dibuja su sombra.
  static const gap = 12.0;

  @override
  State<PlayerCoverCarousel> createState() => _PlayerCoverCarouselState();
}

class _PlayerCoverCarouselState extends State<PlayerCoverCarousel> {
  static const _bundledCover = 'assets/images/discover-mountains.webp';

  PageController? _pageController;

  /// Separación entre la portada y sus vecinas.
  static const _spacing = 12.0;

  /// El controlador para que cada página ocupe [fraction] del ancho: lo que
  /// sobra a cada lado es lo que asoma de las vecinas.
  PageController _controllerFor(double fraction) {
    final current = _pageController;
    if (current != null && (current.viewportFraction - fraction).abs() < .005) {
      return current;
    }
    final page = current != null && current.hasClients
        ? current.page?.round()
        : null;
    current?.dispose();
    return _pageController = PageController(
      viewportFraction: fraction,
      initialPage: page ?? (_player.index < 0 ? 0 : _player.index),
    );
  }

  // Verdadero mientras la página se mueve por código (botones, fin de pista):
  // las páginas intermedias de esa animación no deben cambiar de canción.
  bool _settling = false;

  TrackPlaybackController get _player => widget.controller;

  @override
  void initState() {
    super.initState();
    _player.addListener(_follow);
  }

  @override
  void didUpdateWidget(PlayerCoverCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_follow);
      _player.addListener(_follow);
    }
  }

  @override
  void dispose() {
    _player.removeListener(_follow);
    _pageController?.dispose();
    super.dispose();
  }

  void _follow() {
    final pages = _pageController;
    final target = _player.index;
    if (pages == null || !pages.hasClients || target < 0 || _settling) return;
    if (pages.position.isScrollingNotifier.value) return;
    final page = pages.page?.round();
    if (page == null || page == target) return;
    // Solo una vecina se anima: es un cambio de canción y el deslizamiento es
    // su respuesta. Un salto de muchas páginas se coloca sin pasar por ellas.
    if ((page - target).abs() > 1) {
      pages.jumpToPage(target);
      return;
    }
    _settling = true;
    unawaited(
      pages
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _settling = false),
    );
  }

  void _onPageChanged(int page) {
    if (_settling || page == _player.index) return;
    unawaited(_player.jump(page));
  }

  // Para precargar solo cuando cambia la canción, la cola o el tamaño.
  (int, int, double)? _prefetched;

  void _prefetch(double side) {
    final key = (_player.index, _player.queue.length, side);
    if (key == _prefetched) return;
    _prefetched = key;
    ArtworkPrefetch.lastSide = side;
    // Tras pintar: la portada visible tiene prioridad sobre las de la cola.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ArtworkPrefetch.around(context, _player, side: side);
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = _player.queue;
    final side = widget.side;
    _prefetch(side);
    final Widget covers;
    if (_player.isBundledTrack || queue.length < 2) {
      covers = Center(
        child: _Cover(
          size: side,
          // Una radio con carátula de lo que suena la usa; si no, su logo.
          url: _player.current?.isLive == true
              ? _player.liveArtwork
              : _player.current?.thumbnailUrl,
          asset: _player.isBundledTrack ? _bundledCover : null,
          live: _player.current?.isLive == true && _player.liveArtwork == null,
          liveColors: _player.current?.liveColors,
          liveLogo: _player.current?.liveLogo,
        ),
      );
    } else {
      covers = LayoutBuilder(
        builder: (context, box) {
          final pages = _controllerFor(
            ((side + _spacing) / box.maxWidth).clamp(.4, 1.0).toDouble(),
          );
          return PageView.builder(
            controller: pages,
            itemCount: queue.length,
            onPageChanged: _onPageChanged,
            // Con «repetir canción» no hay a dónde deslizar.
            physics: _player.repeat == PlaybackRepeat.one
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            itemBuilder: (context, index) => AnimatedBuilder(
              animation: pages,
              builder: (context, _) {
                // Cuánto se aleja esta página del centro: 0 la que suena, 1
                // una vecina entera.
                final page = pages.hasClients && pages.position.haveDimensions
                    ? pages.page ?? index.toDouble()
                    : pages.initialPage.toDouble();
                final distance = (page - index).abs().clamp(0.0, 1.0);
                return Center(
                  child: Transform.scale(
                    scale: 1 - .06 * distance,
                    child: _Cover(
                      key: ValueKey('cover:${queue[index].id}:$index'),
                      size: side,
                      url: queue[index].isLive && index == _player.index
                          ? _player.liveArtwork
                          : queue[index].thumbnailUrl,
                      live:
                          queue[index].isLive &&
                          !(index == _player.index &&
                              _player.liveArtwork != null),
                      liveColors: queue[index].liveColors,
                      liveLogo: queue[index].liveLogo,
                      dim: .35 * distance,
                      // Tocar una vecina salta a ella.
                      onTap: distance > .5
                          ? () => unawaited(_player.jump(index))
                          : null,
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }
    return SizedBox(
      height: side + PlayerCoverCarousel.gap * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        // Solo cuenta el gesto hacia arriba; hacia los lados es del carrusel.
        onVerticalDragEnd: widget.onSwipeUp == null
            ? null
            : (details) {
                if ((details.primaryVelocity ?? 0) < -250) widget.onSwipeUp!();
              },
        child: covers,
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    super.key,
    required this.size,
    this.url,
    this.asset,
    this.liveColors,
    this.liveLogo,
    this.live = false,
    this.dim = 0,
    this.onTap,
  });

  final double size;
  final String? url;
  final String? asset;

  /// Una radio en directo: su degradado en lugar de una imagen.
  final bool live;
  final List<int>? liveColors;
  final String? liveLogo;

  /// Cuánto se atenúa (una vecina), de 0 a 1.
  final double dim;
  final VoidCallback? onTap;

  static const _radius = 22.0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, .28 * (1 - dim)),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Stack(
          children: [
            if (live)
              LiveCover(size: size, colors: liveColors, logo: liveLogo)
            else if (asset != null)
              Image.asset(
                asset!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              )
            else
              TrackArtwork(url: url, size: size, borderRadius: 0),
            if (dim > 0)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: dim),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
