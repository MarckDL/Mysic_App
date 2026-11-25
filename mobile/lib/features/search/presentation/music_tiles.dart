import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../../core/settings/app_settings.dart';

import '../../../core/images/disk_cached_image.dart';
import 'catalog_widgets.dart';

/// Disco de vinilo con la portada como etiqueta central.
///
/// Los surcos se pintan una sola vez: el [RepaintBoundary] guarda el resultado
/// como capa y el desplazamiento de la lista no vuelve a ejecutar el pintor.
class VinylDisc extends StatelessWidget {
  const VinylDisc({super.key, required this.size, this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final label = size * .38;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: const _VinylPainter(),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                TrackArtwork(
                  url: url,
                  size: label,
                  borderRadius: label / 2,
                  fallbackIcon: Icons.album,
                ),
                Container(
                  width: size * .07,
                  height: size * .07,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF16110F),
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

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF16110F));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = const Color(0x22FFFFFF);
    for (var r = radius * .46; r < radius * .96; r += radius * .075) {
      canvas.drawCircle(center, r, groove);
    }
    // Brillo en dos cuñas opuestas, como la luz sobre un vinilo real.
    final sheen = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0x00FFFFFF),
          Color(0x30FFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
          Color(0x26FFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0, .08, .17, .5, .58, .67, 1],
        transform: GradientRotation(-math.pi / 3),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sheen);
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}

/// Portada cuadrada con el disco asomando por la derecha.
class AlbumDiscArt extends StatelessWidget {
  const AlbumDiscArt({super.key, required this.size, this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    // Asoma exactamente medio disco: su centro queda en el borde de la portada.
    final disc = size * .9;
    final peek = disc / 2;
    return SizedBox(
      width: size + peek,
      height: size,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: size + peek - disc,
            child: VinylDisc(size: disc, url: url),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(3, 5),
                ),
              ],
            ),
            child: TrackArtwork(
              url: url,
              size: size,
              borderRadius: size * .16,
              fallbackIcon: Icons.album,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de álbum: portada con disco, título, detalle y acceso para abrirlo.
class AlbumDiscCard extends StatelessWidget {
  const AlbumDiscCard({
    super.key,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.subtitle = 'Álbum',
    this.url,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? url;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                AlbumDiscArt(size: 76, url: url),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 4, 12, 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_fill_rounded,
                                size: 20,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Abrir álbum',
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Foto del artista con el nombre y sus oyentes dentro de la imagen.
class ArtistPhotoTile extends StatelessWidget {
  const ArtistPhotoTile({
    super.key,
    required this.name,
    required this.onTap,
    this.detail,
    this.url,
    this.onLongPress,
  });

  final String name;
  final String? detail;
  final String? url;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: detail == null ? name : '$name, $detail',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: .86,
        child: LayoutBuilder(
          builder: (context, box) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: TrackArtwork(
                    url: url,
                    size: box.maxHeight,
                    borderRadius: 0,
                    fallbackIcon: Icons.person_outline,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [.42, 1],
                      colors: [Color(0x00000000), Color(0xD9000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 9,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail!,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xD9FFFFFF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: onTap, onLongPress: onLongPress),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barras de "sonando ahora" (Limusic `AudioPlayingIndicator`): seis cápsulas
/// que crecen desde el centro en un ciclo de 1,44 s. En pausa se congelan.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, required this.running, this.size = 24});

  final bool running;
  final double size;

  /// Las pruebas de widgets esperan con `pumpAndSettle`, que no termina
  /// mientras haya una animación perpetua: pueden apagarla aquí.
  @visibleForTesting
  static bool animationsEnabled = true;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1440),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running && NowPlayingBars.animationsEnabled) _loop.repeat();
  }

  @override
  void didUpdateWidget(NowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.running &&
        NowPlayingBars.animationsEnabled &&
        !_loop.isAnimating) {
      _loop.repeat();
    } else if (!widget.running && _loop.isAnimating) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _BarsPainter(_loop, Colors.white),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width / 11;
    const bars = 6;
    final step = size.width / bars;
    for (var i = 0; i < bars; i++) {
      // Cada barra con su fase; oscila entre el 24 % y el 100 % del alto.
      final wave = (math.sin((progress.value + i * .17) * 2 * math.pi) + 1) / 2;
      final half = size.height * (.12 + .38 * wave);
      final x = step * (i + .5);
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}

/// Pulso de carga: bloques que laten entre el 35 % y el 70 % de opacidad. Un
/// solo controlador para todos los bloques de la lista.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  /// Bloque redondeado del color de superficie elevada.
  static Widget block(
    BuildContext context, {
    double? width,
    double? height,
    double radius = 8,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: SizedBox(width: width, height: height),
  );

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(
      opacity: Tween<double>(begin: .35, end: .7).animate(_pulse),
      child: widget.child,
    ),
  );
}

/// Esqueleto de una lista de filas de canción.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Skeleton.block(context, width: 48, height: 48, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.block(
                        context,
                        width: 160.0 + (i % 3) * 30,
                        height: 12,
                      ),
                      const SizedBox(height: 8),
                      Skeleton.block(context, width: 100, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Esqueleto del collage de nueve portadas del Inicio.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = (box.maxWidth - 8) / 3;
      return Skeleton(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < 9; i++)
              Skeleton.block(context, width: side, height: side),
          ],
        ),
      );
    },
  );
}

/// Fila de canción compacta, con las medidas de Limusic: carátula de 48 dp,
/// título en 14 sp y artista en 12 sp, menú a la derecha.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.url,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.fallbackIcon = Icons.music_note,
    this.playback,
    this.isCurrent,
    this.isRunning,
  });

  final String title;
  final String subtitle;
  final String? url;
  final VoidCallback? onTap;

  /// Mantener pulsada la fila: abre su hoja de opciones.
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final IconData fallbackIcon;

  /// Para marcar la fila que suena: el reproductor y dos pruebas sobre él.
  final Listenable? playback;
  final bool Function()? isCurrent;
  final bool Function()? isRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Stack(
              children: [
                TrackArtwork(
                  url: url,
                  size: 48,
                  borderRadius: 6,
                  fallbackIcon: fallbackIcon,
                ),
                if (playback != null && isCurrent != null)
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: playback!,
                      builder: (context, _) => isCurrent!()
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0x73000000),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: NowPlayingBars(
                                  running: isRunning?.call() ?? true,
                                  size: 28,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: onTap == null ? colors.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) SizedBox(width: 40, child: trailing),
          ],
        ),
      ),
    );
  }
}

typedef DialItem = ({
  String title,
  String subtitle,
  String? url,
  VoidCallback? onTap,

  /// Mantener pulsada la casilla: abre la hoja de opciones.
  VoidCallback? onLongPress,
});

/// Collage de acceso rápido que abre el Inicio, como el de YouTube Music:
/// una cuadrícula de tres columnas de portadas con el título sobre la imagen.
///
/// Es una cuadrícula fija de como mucho nueve casillas, así que se construye
/// entera: no necesita scroll propio ni compite con el de la página.
/// Avisa en cuanto el dedo toca (antes de levantarse): entre el contacto y la
/// liberación pasan ~80–150 ms, que bastan para empezar a resolver el audio de
/// la canción. No participa en los gestos: no impide tocar, desplazar ni
/// mantener pulsado.
///
/// [onLinger] cubre las filas que el usuario alcanza desplazando la lista: se
/// llama una vez si la fila lleva [lingerDelay] construida (una lista perezosa
/// la destruye al salir de pantalla, así que un desplazamiento rápido no
/// calienta las filas que pasan de largo, solo las que se quedan a la vista).
class TouchWarm extends StatefulWidget {
  const TouchWarm({
    super.key,
    required this.onTouch,
    required this.child,
    this.onLinger,
    this.lingerDelay = const Duration(milliseconds: 400),
  });

  final VoidCallback? onTouch;
  final VoidCallback? onLinger;
  final Duration lingerDelay;
  final Widget child;

  @override
  State<TouchWarm> createState() => _TouchWarmState();
}

class _TouchWarmState extends State<TouchWarm> {
  Timer? _linger;
  int _attempts = 0;

  /// Intentos de calentar antes de rendirse (la fila sigue construida pero
  /// nunca quedó a la vista con la lista quieta).
  static const _maxAttempts = 24;

  @override
  void initState() {
    super.initState();
    if (widget.onLinger != null) _arm();
  }

  void _arm() {
    _linger = Timer(widget.lingerDelay, _fire);
  }

  /// Solo se calienta una fila que está a la vista y con la lista quieta:
  /// durante un desplazamiento pasan decenas de filas, y calentarlas todas
  /// dejaría a las que el usuario ve al detenerse al final de una cola larga.
  void _fire() {
    if (!mounted) return;
    final scrolling =
        Scrollable.maybeOf(context)?.position.isScrollingNotifier.value ??
        false;
    final box = context.findRenderObject();
    var visible = true;
    if (box is RenderBox && box.attached && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      visible =
          top + box.size.height > 0 && top < MediaQuery.sizeOf(context).height;
    }
    if ((scrolling || !visible) && ++_attempts < _maxAttempts) {
      _arm();
      return;
    }
    if (!scrolling && visible) widget.onLinger?.call();
  }

  @override
  void dispose() {
    _linger?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.onTouch == null
      ? widget.child
      : Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => widget.onTouch!(),
          child: widget.child,
        );
}

class SpeedDialGrid extends StatelessWidget {
  const SpeedDialGrid({
    super.key,
    required this.items,
    this.onTouch,
    this.eyebrow,
    this.heading,
    this.playing,
    this.isActive,
  });

  final List<DialItem> items;

  /// Se llama con el índice de la casilla en cuanto el dedo la toca.
  final ValueChanged<int>? onTouch;
  final String? eyebrow;
  final String? heading;

  /// Reproductor y prueba de "esta casilla es la que suena": la casilla
  /// activa se enmarca en blanco, como en YouTube Music.
  final Listenable? playing;
  final bool Function(int index)? isActive;

  static const _gap = 4.0;

  /// Casillas por página: tres filas de tres. Con más, el collage tiene
  /// varias páginas que se deslizan, como el de YouTube Music.
  static const pageSize = 9;

  /// Deja [list] en páginas completas: de nueve en nueve cuando pasa de una
  /// página, y en filas de tres cuando es una sola. Nunca una página a medias,
  /// con unas pocas casillas y el resto vacío.
  static List<T> wholePages<T>(List<T> list) {
    final count = list.length >= pageSize
        ? list.length ~/ pageSize * pageSize
        : list.length < 3
        ? list.length
        : list.length ~/ 3 * 3;
    return list.take(count).toList();
  }

  /// Lo que asoma de la página siguiente, para que se vea que se desliza.
  static const _peek = 28.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final theme = Theme.of(context);
      final Widget body;
      if (items.length <= pageSize) {
        body = _grid(context, 0, items, (box.maxWidth - _gap * 2) / 3);
      } else {
        // Cada página es algo más estrecha que la pantalla: la siguiente
        // asoma a la derecha.
        final pageWidth = box.maxWidth - _peek;
        final side = (pageWidth - _gap * 2 - 8) / 3;
        body = _DialPages(
          pageCount: (items.length / pageSize).ceil(),
          fraction: pageWidth / box.maxWidth,
          height: side * 3 + _gap * 2,
          page: (index) {
            final start = index * pageSize;
            final end = (start + pageSize).clamp(0, items.length);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: _grid(context, start, items.sublist(start, end), side),
              ),
            );
          },
        );
      }
      if (heading == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null)
            Text(
              eyebrow!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
          Text(
            heading!,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 10),
          body,
        ],
      );
    },
  );

  /// Una página del collage: las casillas [page], que en la lista entera
  /// empiezan en [offset] (para [onTouch] e [isActive]).
  Widget _grid(
    BuildContext context,
    int offset,
    List<DialItem> page,
    double side,
  ) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    return Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: [
        for (final (at, item) in page.indexed)
          for (final index in [offset + at])
            TouchWarm(
              onTouch: onTouch == null ? null : () => onTouch!(index),
              child: SizedBox.square(
                dimension: side,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Al cambiar la casilla, la portada nueva entra con un
                      // fundido en lugar de cambiar de golpe.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 700),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, ?current],
                        ),
                        child: Stack(
                          key: ValueKey('${item.title}|${item.url}'),
                          fit: StackFit.expand,
                          children: [
                            TrackArtwork(
                              url: item.url,
                              size: side,
                              borderRadius: 0,
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [.45, 1],
                                  colors: [
                                    Color(0x00000000),
                                    Color(0xE6000000),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 7,
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: style,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (playing != null && isActive != null)
                        ListenableBuilder(
                          listenable: playing!,
                          builder: (context, _) => isActive!(index)
                              ? DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: item.onTap,
                          onLongPress: item.onLongPress,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Las páginas del collage, que se deslizan, con un punto por página debajo.
class _DialPages extends StatefulWidget {
  const _DialPages({
    required this.pageCount,
    required this.fraction,
    required this.height,
    required this.page,
  });

  final int pageCount;
  final double fraction;
  final double height;
  final Widget Function(int index) page;

  @override
  State<_DialPages> createState() => _DialPagesState();
}

class _DialPagesState extends State<_DialPages> {
  late PageController _pages = PageController(
    viewportFraction: widget.fraction,
  );
  final _current = ValueNotifier(0);

  @override
  void didUpdateWidget(_DialPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.fraction - widget.fraction).abs() > .005) {
      final page = _current.value;
      _pages.dispose();
      _pages = PageController(
        viewportFraction: widget.fraction,
        initialPage: page,
      );
    }
    if (_current.value >= widget.pageCount) _current.value = 0;
  }

  @override
  void dispose() {
    _pages.dispose();
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pages,
            // La primera pegada a la izquierda; la siguiente asoma a la
            // derecha.
            padEnds: false,
            itemCount: widget.pageCount,
            onPageChanged: (page) => _current.value = page,
            itemBuilder: (context, index) => widget.page(index),
          ),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder(
          valueListenable: _current,
          builder: (context, current, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == current ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == current
                        ? colors.primary
                        : colors.onSurfaceVariant.withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Accesos fijados de la Biblioteca (Limusic `QuickTile`): dos columnas, 72 dp
/// de alto y radio 18. Cuadro de icono con el acento al 16 % y, si hay portada,
/// la mitad derecha de la tarjeta con la imagen fundida hacia el color de fondo.
class LibraryTiles extends StatelessWidget {
  const LibraryTiles({super.key, required this.tiles});

  final List<
    ({
      IconData icon,
      String label,
      String caption,
      VoidCallback onTap,
      String? coverUrl,
    })
  >
  tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final card = colors.surfaceContainerHigh;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final width = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                height: 72,
                child: Material(
                  color: card,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: tile.onTap,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (tile.coverUrl != null)
                          Positioned(
                            top: 0,
                            right: 0,
                            bottom: 0,
                            // Casi la mitad derecha, como en Limusic; el texto queda
                            // a la izquierda, bajo la parte opaca del fundido.
                            width: width * .48,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Las miniaturas de vídeo traen franjas negras a los
                                // lados: se amplía para dejarlas fuera del recorte.
                                ClipRect(
                                  child: Transform.scale(
                                    scale: TrackArtwork.zoomFor(tile.coverUrl),
                                    child: Image(
                                      image: ResizeImage.resizeIfNeeded(
                                        null,
                                        (72 *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .round(),
                                        DiskCachedImage(
                                          TrackArtwork.sizedUrl(
                                            tile.coverUrl!,
                                            360,
                                          ),
                                        ),
                                      ),
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.low,
                                      errorBuilder: (context, error, stack) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                                // Fundido: opaco bajo el texto (45 %) y transparente
                                // a la derecha.
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      stops: const [0, .45, 1],
                                      colors: [
                                        card,
                                        card.withValues(alpha: .78),
                                        card.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SizedBox.square(
                                  dimension: 40,
                                  child: Icon(
                                    tile.icon,
                                    size: 22,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tile.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      tile.caption,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Accesos del Inicio (Limusic `ShortcutsSection`), aquí con el nombre
/// "De one pe": dos columnas de tarjetas de 56 dp con la portada pegada a la
/// izquierda (o un cuadro con icono para las colecciones), título y subtítulo.
class OnePeShortcuts extends StatelessWidget {
  const OnePeShortcuts({super.key, required this.items, this.onAdd});

  /// «Añadir» en el título (no una tesela más, para que una última fila corta
  /// siga corta); null si la cuadrícula está llena.
  final VoidCallback? onAdd;

  final List<
    ({
      String title,
      String subtitle,
      String? url,
      IconData? icon,
      VoidCallback onTap,
      VoidCallback? onLongPress,
    })
  >
  items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 22,
                  color: colors.primary.withValues(alpha: .7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'De one pe',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
                    ),
                  ),
                ),
                if (onAdd != null && items.isNotEmpty)
                  InkWell(
                    onTap: onAdd,
                    customBorder: const StadiumBorder(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Añadir',
                            style: theme.textTheme.bodySmall?.copyWith(
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
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final width = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items.take(8))
                  SizedBox(
                    width: width,
                    height: 56,
                    child: Material(
                      color: colors.onSurface.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: item.onTap,
                        onLongPress: item.onLongPress,
                        child: Row(
                          children: [
                            // Cuadrado de 56 dp pegado al borde; lo redondea el
                            // recorte de la tarjeta (solo las esquinas izquierdas).
                            if (item.url != null)
                              TrackArtwork(
                                url: item.url,
                                size: 56,
                                borderRadius: 0,
                                fallbackIcon:
                                    item.icon ?? Icons.queue_music_rounded,
                              )
                            else
                              ColoredBox(
                                color: colors.primary.withValues(alpha: .16),
                                child: SizedBox.square(
                                  dimension: 56,
                                  child: Icon(
                                    item.icon ?? Icons.queue_music_rounded,
                                    size: 24,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      item.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
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
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Cabecera de playlist como la de Limusic: un mosaico de 2 × 2 con las
/// portadas de sus primeras canciones, a sangre bajo la barra de estado y
/// fundido con el fondo por abajo para que el título se lea encima. Con menos
/// de cuatro portadas se muestra una sola. Se desplaza con la lista.
class PlaylistMosaic extends StatelessWidget {
  const PlaylistMosaic({
    super.key,
    required this.covers,
    required this.scroll,
    required this.height,
  });

  final List<String> covers;
  final ScrollController scroll;
  final double height;

  @override
  Widget build(BuildContext context) {
    final paper = Theme.of(context).colorScheme.surface;
    final tiles = covers.length >= 4 ? covers.take(4).toList() : covers.take(1);
    Widget cover(String url) => ClipRect(
      child: Transform.scale(
        // Las miniaturas de vídeo traen franjas negras: se amplían.
        scale: TrackArtwork.zoomFor(url),
        child: Image(
          image: DiskCachedImage(TrackArtwork.sizedUrl(url, 360)),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
    );
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: scroll,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              -(scroll.hasClients ? scroll.offset : 0.0)
                  .clamp(0.0, height)
                  .toDouble(),
            ),
            child: child,
          ),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (tiles.length == 4)
                  Column(
                    children: [
                      for (final row in [0, 2])
                        Expanded(
                          child: Row(
                            children: [
                              for (final url in tiles.skip(row).take(2))
                                Expanded(child: cover(url)),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  for (final url in tiles) cover(url),
                // Arriba, sombra para la barra de estado y los botones; abajo,
                // el fundido con el fondo sobre el que va el título.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .16, .36, .58, .78, 1],
                      colors: [
                        Colors.black.withValues(alpha: .45),
                        Colors.black.withValues(alpha: 0),
                        paper.withValues(alpha: .12),
                        paper.withValues(alpha: .7),
                        paper.withValues(alpha: .94),
                        paper,
                      ],
                    ),
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

/// Cabecera de "Me gusta" y de "Recientes" (como la de Limusic): un icono grande
/// sobre un degradado del color de la app, fundido con el fondo por abajo. Se desplaza
/// con la lista. Con el color adaptado a la carátula, el degradado también.
class LikedHero extends StatelessWidget {
  const LikedHero({
    super.key,
    required this.scroll,
    required this.height,
    this.icon = Icons.favorite_rounded,
  });

  final ScrollController scroll;
  final double height;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paper = colors.surface;
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: scroll,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              -(scroll.hasClients ? scroll.offset : 0.0)
                  .clamp(0.0, height)
                  .toDouble(),
            ),
            child: child,
          ),
          child: SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .55, .9, 1],
                  colors: [
                    Color.lerp(paper, colors.primary, .62)!,
                    Color.lerp(paper, colors.primary, .26)!,
                    paper.withValues(alpha: .96),
                    paper,
                  ],
                ),
              ),
              child: Align(
                alignment: const Alignment(0, -.42),
                // Blanco arriba y apagándose hacia abajo, como el pulgar de
                // Limusic.
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Color(0x99FFFFFF)],
                  ).createShader(rect),
                  child: Icon(icon, size: height * .5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "1 escucha" / "34 escuchas".
String playsLabel(int plays) => '$plays ${plays == 1 ? 'escucha' : 'escuchas'}';

/// Primera canción de "Lo más oído": una tarjeta destacada con su puesto en
/// grande, la portada, el artista y el número de escuchas en una pastilla.
class TopSongCard extends StatelessWidget {
  const TopSongCard({
    super.key,
    required this.title,
    required this.artist,
    required this.onTap,
    this.onLongPress,
    this.plays,
    this.url,
    this.trailing,
    this.playback,
    this.isCurrent,
  });

  final String title;
  final String artist;
  final int? plays;
  final String? url;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Listenable? playback;
  final bool Function()? isCurrent;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    Widget card(bool current) => Material(
      color: Color.lerp(colors.surfaceContainer, colors.primary, .1),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              TrackArtwork(url: url, size: 92, borderRadius: 14),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '01',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: current ? colors.primary : null,
                      ),
                    ),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (plays != null) ...[
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Text(
                            playsLabel(plays!),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) SizedBox(width: 40, child: trailing),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: playback == null || isCurrent == null
          ? card(false)
          : ListenableBuilder(
              listenable: playback!,
              builder: (context, _) => card(isCurrent!()),
            ),
    );
  }
}

/// Fila de "Lo más oído" desde el segundo puesto: número, portada, título y
/// artista, y las escuchas a la derecha.
class RankedSongRow extends StatelessWidget {
  const RankedSongRow({
    super.key,
    required this.rank,
    required this.title,
    required this.artist,
    required this.onTap,
    this.onLongPress,
    this.plays,
    this.url,
    this.trailing,
    this.playback,
    this.isCurrent,
  });

  final int rank;
  final String title;
  final String artist;
  final int? plays;
  final String? url;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Listenable? playback;
  final bool Function()? isCurrent;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    Widget row(bool current) => InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
            TrackArtwork(url: url, size: 56, borderRadius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: current ? colors.primary : null,
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (plays != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  playsLabel(plays!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (trailing != null) SizedBox(width: 40, child: trailing),
          ],
        ),
      ),
    );
    return playback == null || isCurrent == null
        ? row(false)
        : ListenableBuilder(
            listenable: playback!,
            builder: (context, _) => row(isCurrent!()),
          );
  }
}

/// Fondo del Inicio (Limusic `HomeBackdrop`): la carátula de la canción que
/// suena muy desenfocada tras el saludo, fundida con el fondo. Sin canción, un
/// resplandor del acento. Se desplaza con la lista y se va con ella.
class HomeBackdrop extends StatelessWidget {
  const HomeBackdrop({
    super.key,
    required this.player,
    required this.coverUrl,
    required this.scroll,
    this.height = 440,
  });

  final Listenable player;
  final String? Function() coverUrl;
  final ScrollController scroll;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paper = colors.surface;
    final reduced = EffectsScope.reducedOf(context);
    // El fondo no se desplaza: se desvanece al bajar la lista. Antes subía con
    // ella dentro de un recorte fijo y el desenfoque dejaba una banda de color
    // (una copia de la carátula) sobre las pastillas de accesos.
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: scroll,
          builder: (context, child) {
            final offset = scroll.hasClients ? scroll.offset : 0.0;
            final fade = (1 - offset / (height * .6)).clamp(0.0, 1.0);
            // La opacidad es una capa de composición: no vuelve a desenfocar.
            return fade <= 0
                ? const SizedBox.shrink()
                : Opacity(opacity: fade.toDouble(), child: child);
          },
          child: RepaintBoundary(
            child: SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ListenableBuilder(
                    listenable: player,
                    builder: (context, _) {
                      // Con "Reducir efectos" queda el resplandor, sin la
                      // carátula desenfocada.
                      final url = reduced ? null : coverUrl();
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        child: url == null
                            ? DecoratedBox(
                                key: const ValueKey('glow'),
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(-.8, -1),
                                    radius: 1.4,
                                    colors: [
                                      colors.primary.withValues(alpha: .2),
                                      colors.primary.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              )
                            : Opacity(
                                key: ValueKey(url),
                                opacity: .7,
                                // 96 px y desenfoque de 40: barato y sin diferencia visible.
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: 40,
                                    sigmaY: 40,
                                    tileMode: TileMode.decal,
                                  ),
                                  child: Image(
                                    image: ResizeImage(
                                      // El mismo archivo que usan las filas:
                                      // ya está en disco, no se baja otro.
                                      DiskCachedImage(
                                        TrackArtwork.sizedUrl(url, 160),
                                      ),
                                      width: 96,
                                      height: 96,
                                      policy: ResizeImagePolicy.fit,
                                    ),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (context, error, stack) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
                  // Dos velos del color de la página: uno vertical que termina
                  // opaco en el borde inferior y otro horizontal.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          paper.withValues(alpha: .25),
                          paper.withValues(alpha: .7),
                          paper,
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          paper.withValues(alpha: .6),
                          paper.withValues(alpha: .15),
                          paper.withValues(alpha: 0),
                        ],
                      ),
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

/// Tarjeta de portada para cuadrículas (playlists de la Biblioteca): la
/// carátula llena la celda en 1:1 con radio 10, título a dos líneas debajo.
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.url,
    this.onLongPress,
    this.fallbackIcon = Icons.music_note,
  });

  final String title;
  final String subtitle;
  final String? url;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, box) => TrackArtwork(
                url: url,
                size: box.maxWidth,
                borderRadius: 10,
                fallbackIcon: fallbackIcon,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
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
    );
  }
}

/// Géneros y ambientes de la Búsqueda en reposo (Limusic "Moods & Genres").
const kGenres = <({String label, String query, IconData icon, Color color})>[
  (
    label: 'Pop',
    query: 'pop hits',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF8E6BFF),
  ),
  (
    label: 'Rock',
    query: 'rock clásico',
    icon: Icons.electric_bolt_rounded,
    color: Color(0xFFFF5C5C),
  ),
  (
    label: 'Hip hop',
    query: 'hip hop',
    icon: Icons.mic_external_on_rounded,
    color: Color(0xFFFFA83D),
  ),
  (
    label: 'Electrónica',
    query: 'música electrónica',
    icon: Icons.graphic_eq_rounded,
    color: Color(0xFF2FD1D1),
  ),
  (
    label: 'Lo-fi',
    query: 'lofi chill',
    icon: Icons.headphones_rounded,
    color: Color(0xFF7B8CFF),
  ),
  (
    label: 'Anime',
    query: 'anime openings',
    icon: Icons.animation_rounded,
    color: Color(0xFFFF6FB5),
  ),
  (
    label: 'Urbano',
    query: 'reggaeton',
    icon: Icons.location_city_rounded,
    color: Color(0xFF4FA3FF),
  ),
  (
    label: 'Cumbia',
    query: 'cumbia',
    icon: Icons.music_note_rounded,
    color: Color(0xFF3DDC97),
  ),
  (
    label: 'Jazz',
    query: 'jazz',
    icon: Icons.piano_rounded,
    color: Color(0xFFE0B04A),
  ),
  (
    label: 'Clásica',
    query: 'música clásica',
    icon: Icons.library_music_rounded,
    color: Color(0xFFB59AFF),
  ),
];

/// Cuadrícula de dos columnas de teselas de género: radio 20, borde de 1 dp
/// muy tenue y el fondo de la tarjeta mezclado al 24 % con el color del género.
class GenreGrid extends StatelessWidget {
  const GenreGrid({super.key, required this.onPick});

  final void Function(String label, String query) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final width = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final genre in kGenres)
              SizedBox(
                width: width,
                height: 88,
                child: Material(
                  color: Color.lerp(
                    colors.surfaceContainerHigh,
                    genre.color,
                    .24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: colors.onSurface.withValues(alpha: .07),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onPick(genre.label, genre.query),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: Icon(
                              genre.icon,
                              size: 26,
                              color: genre.color,
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              genre.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Estante de canciones del Inicio, como el de Limusic: columnas de cuatro
/// filas que se pasan de lado. Solo existen las columnas visibles.
class SongGridShelf extends StatefulWidget {
  const SongGridShelf({super.key, required this.rows, this.perColumn = 4});

  final List<Widget> rows;
  final int perColumn;

  static const rowHeight = 62.0;

  @override
  State<SongGridShelf> createState() => _SongGridShelfState();
}

class _SongGridShelfState extends State<SongGridShelf> {
  final _pages = PageController(viewportFraction: .9);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows, per = widget.perColumn;
    final columns = (rows.length / per).ceil();
    final shown = rows.length < per ? rows.length : per;
    return SizedBox(
      height: SongGridShelf.rowHeight * shown,
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        clipBehavior: Clip.none,
        itemCount: columns,
        itemBuilder: (context, column) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Column(
            children: [
              for (
                var i = column * per;
                i < rows.length && i < (column + 1) * per;
                i++
              )
                SizedBox(height: SongGridShelf.rowHeight, child: rows[i]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila de la cuadrícula de artistas: tres huecos iguales con separación.
class ArtistPhotoRow extends StatelessWidget {
  const ArtistPhotoRow({super.key, required this.tiles, this.columns = 3});

  final List<Widget> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: i < tiles.length ? tiles[i] : const SizedBox()),
        ],
      ],
    ),
  );
}

/// Aparece con un fundido y un leve ascenso, una sola vez, tras [delay]. Con
/// "Reducir efectos" (o animaciones desactivadas) se pinta de golpe.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (EffectsScope.reducedOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - _curve.value)),
        child: child,
      ),
    ),
  );
}

/// Se encoge un poco mientras se mantiene el dedo encima: respuesta táctil
/// para tarjetas y portadas.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? .95 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}
