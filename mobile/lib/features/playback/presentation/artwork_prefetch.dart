import 'package:flutter/material.dart';

import '../../../core/images/disk_cached_image.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/track_playback_controller.dart';

/// Precarga de portadas de la cola, como la que ya hay de audio: las [reach]
/// anteriores y las [reach] siguientes a la que suena quedan descargadas y
/// decodificadas al tamaño exacto con que las pinta el reproductor (y también
/// su fondo desenfocado), así que al deslizar, saltar o abrir el reproductor
/// aparecen sin verse cargar.
abstract final class ArtworkPrefetch {
  /// Cuántas portadas a cada lado de la que suena.
  static const reach = 5;

  /// Lado de la portada del reproductor la última vez que se pintó; antes de
  /// abrirlo se estima por el ancho de la pantalla.
  static double? lastSide;

  /// Lo ya pedido (URL y tamaño): pedirlo otra vez no hace nada. Tope para
  /// que una sesión larga no lo haga crecer sin fin.
  static final _asked = <String>{};
  static const _askedLimit = 400;

  /// Estimación del lado de la portada del reproductor: el ancho menos los
  /// márgenes que dejan asomar a las vecinas, como lo calcula la página.
  static double sideFor(BuildContext context) {
    final known = lastSide;
    if (known != null && known > 0) return known;
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 520.0);
    return (width - 72 * 2).clamp(120.0, 440.0).toDouble();
  }

  /// Precarga las portadas alrededor de la que suena en [controller], de la
  /// más cercana a la más lejana.
  static void around(
    BuildContext context,
    TrackPlaybackController controller, {
    double? side,
  }) {
    if (controller.isBundledTrack) return;
    final urls = urlsAround([
      for (final track in controller.queue) track.thumbnailUrl,
    ], controller.index);
    if (urls.isEmpty) return;
    final cover = side ?? sideFor(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    for (final url in urls) {
      _fetch(context, url, cover, ratio);
    }
  }

  /// Las portadas que precargar para la canción [index] de una cola con
  /// estas [covers]: la suya y las [reach] de cada lado, de la más cercana a
  /// la más lejana (siguiente antes que anterior), sin huecos ni repetidas.
  static List<String> urlsAround(List<String?> covers, int index) {
    if (index < 0 || index >= covers.length) return const [];
    final urls = <String>[];
    for (var step = 0; step <= reach; step++) {
      for (final at in step == 0 ? [index] : [index + step, index - step]) {
        if (at < 0 || at >= covers.length) continue;
        final url = covers[at];
        if (url != null && url.isNotEmpty && !urls.contains(url)) {
          urls.add(url);
        }
      }
    }
    return urls;
  }

  static void _fetch(
    BuildContext context,
    String url,
    double side,
    double ratio,
  ) {
    if (!_asked.add('$url|${side.round()}|$ratio')) return;
    if (_asked.length > _askedLimit) {
      _asked.remove(_asked.first);
    }
    // La portada del carrusel, a su tamaño exacto.
    _precache(context, TrackArtwork.providerFor(url, side, ratio));
    // El fondo desenfocado del reproductor: el archivo pequeño, sin recortar
    // (de él se saca el color) y a 256 px (el que se pinta).
    final small = DiskCachedImage(TrackArtwork.sizedUrl(url, 160));
    _precache(context, small);
    _precache(context, ResizeImage.resizeIfNeeded(null, 256, small));
  }

  static void _precache(BuildContext context, ImageProvider provider) {
    // Un fallo (sin red, «solo descargadas») no importa: la portada se pedirá
    // al pintarse, como siempre.
    precacheImage(provider, context, onError: (_, _) {});
  }
}
