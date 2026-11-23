import 'package:flutter/material.dart';

import '../../../core/images/disk_cached_image.dart';
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;

/// Una carátula que llena la caja que le den (no cuadrada como
/// `TrackArtwork`): pasa por la caché de disco, se decodifica a [pixels] y
/// aparece con un fundido. Si falla no pinta nada: quien la usa ya se ve
/// terminado sin ella.
class CoverArt extends StatelessWidget {
  const CoverArt(this.url, {super.key, this.pixels = 360});

  final String url;
  final int pixels;

  @override
  Widget build(BuildContext context) => Image(
    image: ResizeImage.resizeIfNeeded(
      null,
      pixels,
      DiskCachedImage(TrackArtwork.sizedUrl(url, pixels)),
    ),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    filterQuality: FilterQuality.low,
    frameBuilder: (context, child, frame, synchronous) => synchronous
        ? child
        : AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          ),
    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
  );
}
