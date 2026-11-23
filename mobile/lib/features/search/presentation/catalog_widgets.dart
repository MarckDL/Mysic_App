import 'package:flutter/material.dart';
import '../../../core/images/disk_cached_image.dart';
import '../../../core/network/api_failure.dart';
import '../../authentication/domain/auth_repository.dart';
import '../domain/catalog_track.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    this.url,
    this.size = 56,
    this.borderRadius = 8,
    this.fallbackIcon = Icons.music_note,
  });
  final String? url;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHigh, colors.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: size / 2.2,
          color: colors.onSurfaceVariant.withValues(alpha: .55),
        ),
      ),
    );
    // Mientras la portada carga se ve el degradado sin icono, no un hueco.
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHigh, colors.surfaceContainerHighest],
        ),
      ),
    );
    // Decodifica a la resolución en que se pinta: una portada de 1200 px en
    // una fila de 52 px ocuparía ~5 MB de memoria de imagen en vez de ~80 KB.
    // Las miniaturas de vídeo de YouTube (default, hqdefault, sddefault) son
    // 4:3 con el fotograma 16:9 entre dos franjas negras. Ampliarlas 4/3
    // deja las franjas fuera del recorte y la portada llena el cuadrado.
    final zoom = zoomFor(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? fallback
            : Stack(
                fit: StackFit.expand,
                children: [
                  placeholder,
                  Transform.scale(
                    scale: zoom,
                    child: Image(
                      image: providerFor(
                        url!,
                        size,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                      frameBuilder: (context, child, frame, synchronous) =>
                          synchronous
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: child,
                            ),
                      errorBuilder: (context, error, stack) => fallback,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// La imagen tal como la pinta una portada de [size] dp: pasa por la caché
  /// de disco y se decodifica al tamaño que se pinta (por alto: las
  /// miniaturas 16:9 recortadas a cuadrado siguen cubriendo la caja). Es la
  /// misma clave de la caché de memoria que usa [build], así que precargarla
  /// deja la portada lista para pintarse sin esperar.
  static ImageProvider<Object> providerFor(
    String url,
    double size,
    double devicePixelRatio,
  ) {
    final pixels = (size * zoomFor(url) * devicePixelRatio).round();
    return ResizeImage.resizeIfNeeded(
      null,
      pixels > 0 ? pixels : null,
      DiskCachedImage(sizedUrl(url, pixels)),
    );
  }

  /// Las carátulas de Google llevan el tamaño en la URL (`=w120-h120`).
  /// Pedir el que se va a pintar evita portadas borrosas en grande y
  /// descargas de 544 px para una fila de 48.
  static final _sizeSuffix = RegExp(r'=w\d+-h\d+');
  static String sizedUrl(String url, int pixels) {
    if (pixels <= 0 || !url.contains('googleusercontent.com')) return url;
    // Escalones fijos: la misma portada no se descarga una vez por tamaño.
    final side = pixels <= 160
        ? 160
        : pixels <= 360
        ? 360
        : pixels <= 720
        ? 720
        : 1080;
    return url.replaceFirst(_sizeSuffix, '=w$side-h$side');
  }

  /// Ampliación que quita las franjas negras de las miniaturas de vídeo de
  /// YouTube (1 para las portadas cuadradas, que ya vienen limpias).
  static double zoomFor(String? url) =>
      url != null && _letterboxed.hasMatch(url) ? 4 / 3 : 1.0;

  static final _letterboxed = RegExp(
    r'ytimg\.com/vi(_webp)?/[^/]+/(hq|sd)?default\.',
  );
}

class TrackHeading extends StatelessWidget {
  const TrackHeading({super.key, required this.track});

  final CatalogTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TrackArtwork(url: track.thumbnailUrl, size: 184),
        const SizedBox(height: 16),
        Text(
          track.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          track.artistName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class CatalogError extends StatelessWidget {
  const CatalogError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error is ApiFailure
                ? (error as ApiFailure).message
                : error is AuthFailure
                ? (error as AuthFailure).message
                : 'No se pudo cargar el catálogo.',
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: retry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
