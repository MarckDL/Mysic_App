import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../network/offline_mode.dart';

/// Caché de portadas en disco (equivalente a la de Coil en Limusic, 512 MB).
///
/// Flutter solo cachea en memoria: al reiniciar la app, o al salir una portada
/// del límite de 100 MB de memoria, había que volver a descargarla. Aquí cada
/// URL https se guarda una vez en la carpeta de caché del sistema (que Android
/// puede vaciar si falta espacio) y se recorta por antigüedad de uso.
class DiskImageCache {
  DiskImageCache._();

  static final instance = DiskImageCache._();

  /// Tope del disco: al pasarlo se borran las portadas menos usadas.
  static const maxBytes = 256 * 1024 * 1024;

  /// Una portada de más de esto no es una portada: se rechaza.
  static const _maxImage = 8 * 1024 * 1024;

  final _inFlight = <String, Future<Uint8List>>{};
  Directory? _dir;
  Future<Directory?>? _resolving;
  int _writes = 0;

  // Se guarda la consulta, no una marca de "ya resuelto": al arrancar llegan
  // muchas portadas a la vez y todas deben esperar a la misma carpeta. Con la
  // marca, las que llegaban mientras se resolvía la veían vacía y se iban a
  // la red aunque su archivo estuviera en disco.
  Future<Directory?> _directory() => _resolving ??= () async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}mysic_covers',
      );
      await dir.create(recursive: true);
      return _dir = dir;
    } on Object {
      // Sin plugin (pruebas) o sin disco: se descarga sin guardar.
      return null;
    }
  }();

  /// Bytes de la imagen de [url], del disco si ya estaba. Las peticiones
  /// simultáneas de una misma URL comparten una sola descarga.
  Future<Uint8List> bytes(String url) {
    final pending = _inFlight[url];
    if (pending != null) return pending;
    final future = _fetch(url);
    _inFlight[url] = future;
    unawaited(
      future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _inFlight.remove(url);
      }),
    );
    return future;
  }

  Future<Uint8List> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('Solo se cargan portadas https: $url');
    }
    final dir = await _directory();
    File? file;
    if (dir != null) {
      file = File(
        '${dir.path}${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}',
      );
      try {
        if (await file.exists()) {
          final data = await file.readAsBytes();
          if (data.isNotEmpty) {
            // Marca de uso para el recorte por antigüedad.
            unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
            return data;
          }
        }
      } on Object {
        // Un archivo ilegible se vuelve a descargar.
      }
    }
    final data = await _download(uri);
    if (file != null) unawaited(_store(file, data));
    return data;
  }

  // Un solo cliente para todas las portadas: las conexiones se reutilizan y
  // una pantalla con veinte carátulas no negocia TLS veinte veces. El tope
  // por servidor evita saturar la red de un teléfono modesto.
  late final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 6;

  Future<Uint8List> _download(Uri uri) async {
    // Con «solo canciones descargadas» solo se muestran las portadas que ya
    // están en disco.
    OfflineMode.ensureOnline();
    final request = await _http.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      // Se consume el cuerpo para que la conexión vuelva al grupo.
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final builder = BytesBuilder(copy: false);
    // Salir del bucle con un error cancela la lectura, y dart:io cierra la
    // conexión de una respuesta a medias en vez de reutilizarla.
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > _maxImage) {
        throw HttpException('Imagen demasiado grande', uri: uri);
      }
    }
    if (builder.isEmpty) throw HttpException('Imagen vacía', uri: uri);
    return builder.takeBytes();
  }

  Future<void> _store(File file, Uint8List data) async {
    try {
      // Escritura en un temporal y renombrado: nunca queda una imagen a medias.
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(data, flush: true);
      await temp.rename(file.path);
      if (++_writes % 40 == 0) unawaited(_trim());
    } on Object {
      // El disco lleno o sin permiso no impide mostrar la imagen.
    }
  }

  Future<void> _trim() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final entries = <(File, int, DateTime)>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        final stat = await entity.stat();
        entries.add((entity, stat.size, stat.modified));
        total += stat.size;
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      // Se libera hasta el 80 % para no recortar en cada descarga.
      for (final (file, size, _) in entries) {
        if (total <= maxBytes * .8) break;
        await file.delete();
        total -= size;
      }
    } on Object {
      // El recorte es una optimización; un fallo no afecta a la app.
    }
  }

  /// Bytes que ocupan las portadas guardadas.
  Future<int> size() async {
    final dir = await _directory();
    if (dir == null) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list()) {
        if (entity is File) total += (await entity.stat()).size;
      }
    } on Object {
      // Un fallo de lectura solo deja el tamaño a medias.
    }
    return total;
  }

  /// Borra todas las portadas guardadas.
  Future<void> clear() async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } on Object {
      // Se ignora: la caché se rellenará sola.
    }
  }
}

/// Proveedor de imagen que pasa por [DiskImageCache]. Envolverlo en
/// `ResizeImage` decodifica al tamaño con que se pinta.
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url);

  final String url;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DiskCachedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decode(key, decode),
    scale: 1,
    debugLabel: key.url,
    informationCollector: () => [
      DiagnosticsProperty<ImageProvider>('Image provider', this),
      DiagnosticsProperty<DiskCachedImage>('Image key', key),
    ],
  );

  Future<ui.Codec> _decode(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) async {
    final data = await DiskImageCache.instance.bytes(key.url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(data);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiskCachedImage("$url")';
}
