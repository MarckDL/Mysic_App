import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Audio ya escuchado, guardado por canción para repetirlo sin red (Limusic
/// lo hace con su caché de reproducción). Un archivo por identificador de
/// vídeo; solo cuenta como guardado cuando se descargó entero.
class AudioDiskCache {
  AudioDiskCache._();

  static final instance = AudioDiskCache._();

  /// Tope de la carpeta; al pasarlo se borran las canciones menos recientes.
  static const maxBytes = 512 * 1024 * 1024;

  /// Los vídeos más largos no se guardan: un mix de horas son cientos de MB
  /// que se bajarían enteros en segundo plano aunque solo se escuche un rato.
  static const maxTrackSeconds = 20 * 60;

  /// Si el audio de una pista de [seconds] de duración merece guardarse. Sin
  /// duración conocida no se guarda: podría ser un vídeo largo.
  static bool worthKeeping(int? seconds) =>
      seconds != null && seconds > 0 && seconds <= maxTrackSeconds;

  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');
  Future<Directory?>? _dir;

  Future<Directory?> _directory() => _dir ??= () async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}mysic_audio');
      await dir.create(recursive: true);
      return dir;
    } on Object {
      // Sin plugin (pruebas) o sin disco no se guarda audio.
      return null;
    }
  }();

  /// Dónde va el audio de [sourceId], o null si no se puede guardar.
  Future<File?> target(String sourceId) async {
    if (!_id.hasMatch(sourceId)) return null;
    final dir = await _directory();
    return dir == null
        ? null
        : File('${dir.path}${Platform.pathSeparator}$sourceId');
  }

  /// El archivo de [sourceId] si está entero en disco.
  Future<File?> complete(String sourceId) async {
    try {
      final file = await target(sourceId);
      if (file == null || !await file.exists() || await file.length() == 0) {
        return null;
      }
      // Marca de uso para el recorte por antigüedad.
      unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
      return file;
    } on Object {
      return null;
    }
  }

  Future<void> remove(String sourceId) async {
    try {
      final file = await target(sourceId);
      if (file != null && await file.exists()) await file.delete();
    } on Object {
      // Un archivo que no se pudo borrar se sobrescribe al volver a guardarlo.
    }
  }

  /// Bytes que ocupa el audio guardado, incluidas las descargas a medias.
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

  /// Borra lo menos reciente hasta quedar en el 80 % del tope.
  Future<void> trim() async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      final entries = <(File, int, DateTime)>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        entries.add((entity, stat.size, stat.modified));
        total += stat.size;
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (file, size, _) in entries) {
        if (total <= maxBytes * .8) break;
        await file.delete();
        total -= size;
      }
    } on Object {
      // El recorte es una optimización; un fallo no afecta a la reproducción.
    }
  }

  Future<void> clear() async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
    } on Object {
      // Lo que quede se recorta más adelante.
    }
  }
}
