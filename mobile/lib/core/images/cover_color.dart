import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'disk_cached_image.dart';

/// Color dominante de una portada, para teñir el tema como hace Limusic con
/// "Adaptar colores a la carátula".
///
/// Se muestrea una versión de 48 px (la imagen ya está en la caché de disco) y
/// se elige el tono con más peso: cuenta la croma y se penalizan los extremos
/// de claridad, de modo que un fondo blanco o negro no gana a la ilustración.
class CoverColor {
  CoverColor._();

  static const _sample = 48;
  static const _maxEntries = 64;
  // Se guarda el cálculo, no solo su resultado: dos peticiones del mismo
  // color (la pista actual y una vecina adelantada) comparten un cálculo.
  static final _cache = <String, Future<Color?>>{};

  /// Color de [url], o `null` si la portada no tiene un tono utilizable
  /// (blanco y negro, gris) o no se pudo cargar.
  static Future<Color?> of(String url) {
    final known = _cache[url];
    if (known != null) return known;
    if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
    return _cache[url] = _compute(
      url,
    ).then<Color?>((color) => color, onError: (Object _) => null);
  }

  static final _bars = <String, Future<bool>>{};

  /// Si la imagen de [url] trae franjas negras horizontales que seguirían
  /// viéndose tras recortarla a un cuadrado (vídeos apaisados subidos con el
  /// arte en el centro). Sirve para no ponerla en un mosaico de portadas.
  static Future<bool> hasBars(String url) {
    final known = _bars[url];
    if (known != null) return known;
    if (_bars.length >= _maxEntries) _bars.remove(_bars.keys.first);
    return _bars[url] = _pixels(url).then<bool>((image) {
      final (bytes, width, height) = image;
      return barsIn(bytes, width, height);
    }, onError: (Object _) => false);
  }

  /// Mira dos filas, al 17 % y al 83 % del alto: quedan dentro del recorte
  /// que quita las franjas normales de una miniatura de vídeo, así que si
  /// siguen negras la portada tiene franjas propias. Público para probarlo.
  static bool barsIn(ByteData bytes, int width, int height) {
    if (width <= 0 || height < 6) return false;
    bool dark(int row) {
      var sum = 0;
      for (var x = 0; x < width; x++) {
        final i = (row * width + x) * 4;
        if (i + 2 >= bytes.lengthInBytes) return false;
        sum +=
            bytes.getUint8(i) + bytes.getUint8(i + 1) + bytes.getUint8(i + 2);
      }
      return sum / (width * 3) < 18;
    }

    return dark((height * .17).round()) && dark((height * .83).round());
  }

  static Future<(ByteData, int, int)> _pixels(String url) async {
    final info = await _load(url);
    try {
      final data = await info.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) throw StateError('Sin pixeles');
      return (data, info.image.width, info.image.height);
    } finally {
      info.dispose();
    }
  }

  static Future<Color?> _compute(String url) async {
    final info = await _load(url);
    try {
      final data = await info.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return data == null ? null : fromRgba(data);
    } finally {
      info.dispose();
    }
  }

  static Future<ImageInfo> _load(String url) {
    final provider = ResizeImage(
      DiskCachedImage(url),
      width: _sample,
      height: _sample,
      policy: ResizeImagePolicy.fit,
    );
    final completer = Completer<ImageInfo>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 20));
  }

  /// Algoritmo sobre pixeles RGBA; publico para poder probarlo sin imágenes.
  static Color? fromRgba(ByteData bytes) {
    const buckets = 24;
    final weight = List<double>.filled(buckets, 0);
    final hueSum = List<double>.filled(buckets, 0);
    final chromaSum = List<double>.filled(buckets, 0);
    final toneSum = List<double>.filled(buckets, 0);
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) < 220) continue;
      final argb =
          0xFF000000 |
          (bytes.getUint8(i) << 16) |
          (bytes.getUint8(i + 1) << 8) |
          bytes.getUint8(i + 2);
      final hct = Hct.fromInt(argb);
      if (hct.chroma < 14 || hct.tone < 12 || hct.tone > 88) continue;
      final w = hct.chroma * (1 - (hct.tone - 50).abs() / 50);
      final bucket = (hct.hue / (360 / buckets)).floor() % buckets;
      weight[bucket] += w;
      hueSum[bucket] += hct.hue * w;
      chromaSum[bucket] += hct.chroma * w;
      toneSum[bucket] += hct.tone * w;
    }
    var best = 0;
    for (var i = 1; i < buckets; i++) {
      if (weight[i] > weight[best]) best = i;
    }
    if (weight[best] < 8) return null;
    final w = weight[best];
    return Color(
      Hct.from(
        hueSum[best] / w,
        chromaSum[best] / w,
        toneSum[best] / w,
      ).toInt(),
    );
  }

  /// Variante de [seed] con el mismo tono de color y la [chroma] y [tone] dadas.
  static Color tonal(Color seed, double chroma, double tone) =>
      Color(Hct.from(Hct.fromInt(seed.toARGB32()).hue, chroma, tone).toInt());

  /// Croma del color, acotada a [min]–[max]: una portada casi gris no apaga el
  /// acento y una muy saturada no lo vuelve estridente.
  static double accentChroma(Color seed, {double min = 40, double max = 84}) =>
      math.max(min, math.min(max, Hct.fromInt(seed.toARGB32()).chroma));
}
