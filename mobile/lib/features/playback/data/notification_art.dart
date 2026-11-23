import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../../../core/network/offline_mode.dart';

/// La portada que ve el sistema en la notificación y en la pantalla de
/// bloqueo. Android la usa como imagen grande, así que tiene que ser cuadrada
/// y nítida: las miniaturas de vídeo de YouTube llegan en 4:3 con franjas
/// negras y muy pequeñas, y estiradas se ven mal y se salen del recuadro.
class NotificationArt {
  NotificationArt._();

  /// Lado de la portada generada.
  static const side = 544;

  static final _letterboxed = RegExp(
    r'^https://(?:i\d?\.)?ytimg\.com/vi(?:_webp)?/([^/]+)/(?:hq|sd|mq)?default\.',
  );
  static final _sizeSuffix = RegExp(r'=[wsh]\d+[^/]*$');

  /// La portada que se puede dar ya, sin descargar nada: las de Google ya son
  /// cuadradas y solo hace falta pedirlas más grandes. Con una miniatura de
  /// vídeo devuelve null hasta que [square] la genere.
  static Uri? immediate(String? url) {
    if (url == null) return null;
    if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
      return Uri.tryParse(
        url.contains(_sizeSuffix)
            ? url.replaceFirst(_sizeSuffix, '=w$side-h$side-l90-rj')
            : url,
      );
    }
    if (_letterboxed.hasMatch(url)) return null;
    return Uri.tryParse(url);
  }

  /// Si [url] es una miniatura de vídeo, el archivo con su portada cuadrada
  /// recortada (sin franjas negras); null si no hace falta o no se pudo.
  static Future<Uri?> square(String url) async {
    final match = _letterboxed.firstMatch(url);
    if (match == null) return null;
    try {
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/notification_art',
      );
      await dir.create(recursive: true);
      final file = File('${dir.path}/${match.group(1)}.png');
      if (await file.exists()) return file.uri;
      // La miniatura de 480×360 (la pequeña de 120×90 se vería borrosa).
      final source = 'https://i.ytimg.com/vi/${match.group(1)}/hqdefault.jpg';
      final bytes = await _download(source);
      if (bytes == null) return null;
      final png = await _cropSquare(bytes);
      if (png == null) return null;
      await file.writeAsBytes(png, flush: true);
      unawaited(_trim(dir));
      return file.uri;
    } on Object {
      return null;
    }
  }

  static Future<Uint8List?> _download(String url) async {
    // Con «solo canciones descargadas» no se abre ninguna conexión.
    if (OfflineMode.instance.active) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > 2000000) return null;
      }
      return builder.takeBytes();
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Recorta el cuadrado central del fotograma 16:9, que ocupa tres cuartos
  /// del alto de la miniatura 4:3: ahí no hay franjas negras.
  static Future<Uint8List?> _cropSquare(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final cut = image.height * 3 / 4;
      final source = ui.Rect.fromLTWH(
        (image.width - cut) / 2,
        (image.height - cut) / 2,
        cut,
        cut,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(side, side);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      picture.dispose();
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Guarda solo las últimas 30 portadas generadas.
  static Future<void> _trim(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      if (files.length <= 30) return;
      final dated = [for (final f in files) (f, (await f.stat()).modified)]
        ..sort((a, b) => a.$2.compareTo(b.$2));
      for (final (file, _) in dated.take(files.length - 30)) {
        await file.delete();
      }
    } on Object {
      // Es solo limpieza.
    }
  }
}
