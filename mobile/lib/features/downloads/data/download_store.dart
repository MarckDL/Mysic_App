import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/offline_mode.dart';
import '../../playback/data/audio_disk_cache.dart';
import '../../playback/domain/playback_source_resolver.dart';
import '../../search/domain/catalog_track.dart';

/// Una canción guardada en el teléfono para oírla sin internet.
class DownloadedTrack {
  const DownloadedTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.bytes,
    required this.savedAt,
    this.durationSeconds,
    this.thumbnailUrl,
    this.artistId,
    this.albumId,
    this.albumName,
  });

  /// Identificador del vídeo (11 caracteres), sin el prefijo `youtube:`.
  final String id;
  final String title;
  final String artist;
  final int bytes;
  final int savedAt;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final String? artistId;
  final String? albumId;
  final String? albumName;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'bytes': bytes,
    'savedAt': savedAt,
    'durationSeconds': durationSeconds,
    'thumbnailUrl': thumbnailUrl,
    'artistId': artistId,
    'albumId': albumId,
    'albumName': albumName,
  };

  static DownloadedTrack? fromJson(Object? data) {
    if (data is! Map) return null;
    final id = data['id'];
    final title = data['title'];
    final artist = data['artist'];
    final bytes = data['bytes'];
    final savedAt = data['savedAt'];
    if (id is! String ||
        !DownloadStore.idPattern.hasMatch(id) ||
        title is! String ||
        artist is! String ||
        bytes is! int ||
        savedAt is! int) {
      return null;
    }
    String? text(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final seconds = data['durationSeconds'];
    return DownloadedTrack(
      id: id,
      title: title,
      artist: artist,
      bytes: bytes,
      savedAt: savedAt,
      durationSeconds: seconds is int && seconds > 0 ? seconds : null,
      thumbnailUrl: text('thumbnailUrl'),
      artistId: text('artistId'),
      albumId: text('albumId'),
      albumName: text('albumName'),
    );
  }
}

/// Cómo se pide la fuente de un audio al resolvedor del teléfono.
typedef DownloadSourceResolver =
    Future<PlaybackSource> Function(String sourceId, {bool refresh});

/// Baja una fuente a [target] informando del avance (0 a 1, o -1 si no se
/// conoce el tamaño). Se puede sustituir en las pruebas.
typedef DownloadFetcher =
    Future<void> Function(
      String sourceId,
      DownloadSourceResolver resolve,
      File target,
      void Function(double progress) onProgress,
    );

/// Canciones descargadas: archivos en la carpeta de datos de la app (no en la
/// caché, que el sistema puede vaciar) y un índice con sus datos para listarlas
/// sin red. Las descargas se hacen de una en una.
class DownloadStore extends ChangeNotifier {
  DownloadStore._() : _fetcher = _httpFetch;

  @visibleForTesting
  DownloadStore.forTest(Directory directory, {DownloadFetcher? fetcher})
    : _fetcher = fetcher ?? _httpFetch,
      _dir = Future.value(directory);

  static final instance = DownloadStore._();

  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Los vídeos más largos no se guardan: un mix de varias horas ocupa
  /// cientos de MB y no es una canción.
  static const maxTrackSeconds = AudioDiskCache.maxTrackSeconds;

  /// Tope de bytes de una canción (20 min de audio AAC son ~20 MB): protege
  /// cuando la duración no se conoce.
  static const maxTrackBytes = 48 * 1024 * 1024;

  final DownloadFetcher _fetcher;
  Future<Directory?>? _dir;
  Future<void>? _loading;
  final _tracks = <String, DownloadedTrack>{};
  final _pending = <String, CatalogTrack>{};
  final _progress = <String, double>{};
  final _failed = <String, String>{};
  final _failedTitles = <String, String>{};
  Future<void> _chain = Future.value();

  /// Descargadas, de la más reciente a la más antigua.
  List<DownloadedTrack> get tracks =>
      _tracks.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  /// En cola o descargándose ahora.
  List<CatalogTrack> get pending => _pending.values.toList();

  bool get hasDownloads => _tracks.isNotEmpty;
  bool isDownloaded(String sourceId) => _tracks.containsKey(sourceId);
  bool isBusy(String sourceId) => _pending.containsKey(sourceId);

  /// Pone el álbum [albumId] / [albumName] a las descargas de [sourceIds] que
  /// no lo tienen (las bajadas desde la página del álbum antes de que se
  /// guardara), para poder ordenarlas por álbum. Devuelve cuántas cambió.
  Future<int> fillAlbum(
    Iterable<String> sourceIds,
    String albumId,
    String albumName,
  ) async {
    if (albumName.trim().isEmpty) return 0;
    var changed = 0;
    for (final id in sourceIds) {
      final track = _tracks[id];
      if (track == null || (track.albumName?.isNotEmpty ?? false)) continue;
      _tracks[id] = DownloadedTrack(
        id: track.id,
        title: track.title,
        artist: track.artist,
        bytes: track.bytes,
        savedAt: track.savedAt,
        durationSeconds: track.durationSeconds,
        thumbnailUrl: track.thumbnailUrl,
        artistId: track.artistId,
        albumId: track.albumId ?? albumId,
        albumName: albumName.trim(),
      );
      changed++;
    }
    if (changed == 0) return 0;
    notifyListeners();
    final dir = await _directory();
    if (dir != null) {
      try {
        await _writeIndex(dir);
      } on Object {
        // Vale para esta sesión; se repetirá al volver a abrir el álbum.
      }
    }
    return changed;
  }

  /// Avance de [sourceId] (0 a 1; -1 si no se conoce) o null si no se baja.
  double? progressOf(String sourceId) => _progress[sourceId];

  /// Motivo del último fallo de [sourceId], si falló.
  String? failureOf(String sourceId) => _failed[sourceId];

  /// Descargas que fallaron y el usuario aún no descartó.
  List<({String id, String title, String reason})> get failures => [
    for (final entry in _failed.entries)
      (
        id: entry.key,
        title: _failedTitles[entry.key] ?? entry.key,
        reason: entry.value,
      ),
  ];

  void dismissFailure(String sourceId) {
    if (_failed.remove(sourceId) != null) {
      _failedTitles.remove(sourceId);
      notifyListeners();
    }
  }

  DownloadedTrack? infoOf(String sourceId) => _tracks[sourceId];

  Future<Directory?> _directory() => _dir ??= () async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}mysic_downloads',
      );
      await dir.create(recursive: true);
      return dir;
    } on Object {
      // Sin plugin (pruebas) o sin disco no hay descargas.
      return null;
    }
  }();

  File _file(Directory dir, String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  /// Lee el índice y descarta lo que ya no tiene archivo. Se puede llamar
  /// varias veces: solo trabaja la primera.
  Future<void> load() => _loading ??= () async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      final index = _file(dir, 'index.json');
      if (await index.exists()) {
        final data = jsonDecode(await index.readAsString());
        if (data is List) {
          for (final entry in data) {
            final track = DownloadedTrack.fromJson(entry);
            if (track == null) continue;
            final audio = _file(dir, track.id);
            if (await audio.exists() && await audio.length() > 0) {
              _tracks[track.id] = track;
            }
          }
        }
      }
      // Las descargas a medias de una ejecución anterior no sirven.
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
    } on Object {
      // Un índice ilegible deja la lista vacía; los archivos siguen ahí.
    }
    notifyListeners();
  }();

  Future<void> _writeIndex(Directory dir) async {
    final temp = _file(dir, 'index.json.tmp');
    await temp.writeAsString(
      jsonEncode([for (final track in _tracks.values) track.toJson()]),
      flush: true,
    );
    await temp.rename(_file(dir, 'index.json').path);
  }

  /// El archivo de audio de [sourceId], si está descargado entero.
  Future<File?> file(String sourceId) async {
    await load();
    if (!_tracks.containsKey(sourceId)) return null;
    final dir = await _directory();
    if (dir == null) return null;
    final audio = _file(dir, sourceId);
    return await audio.exists() ? audio : null;
  }

  /// La portada guardada de [sourceId], si hay.
  Future<File?> coverFile(String sourceId) async {
    if (!_tracks.containsKey(sourceId)) return null;
    final dir = await _directory();
    if (dir == null) return null;
    final cover = _file(dir, '$sourceId.jpg');
    return await cover.exists() ? cover : null;
  }

  /// Motivo por el que [track] no se puede descargar, o null si se puede.
  static String? refusal(CatalogTrack track) {
    final id = track.id.startsWith('youtube:') ? track.id.substring(8) : '';
    if (!idPattern.hasMatch(id) ||
        track.isMusicPreview ||
        track.deviceAudio != null ||
        track.licensedAudio != null ||
        track.readAudio != null) {
      return 'Esta canción no se puede descargar.';
    }
    final seconds = track.durationSeconds;
    if (seconds != null && seconds > maxTrackSeconds) {
      return 'Los vídeos de más de ${maxTrackSeconds ~/ 60} minutos no se '
          'descargan.';
    }
    return null;
  }

  /// Pone [track] en la cola de descargas. Devuelve un aviso para el usuario
  /// o null si no hay nada que decir.
  String? enqueue(CatalogTrack track, DownloadSourceResolver resolve) {
    final refused = refusal(track);
    if (refused != null) return refused;
    final id = track.id.substring(8);
    if (_tracks.containsKey(id)) return 'Ya está descargada.';
    if (_pending.containsKey(id)) return 'Ya se está descargando.';
    if (OfflineMode.instance.active) {
      return 'Sin conexión: desactiva «Solo canciones descargadas» para '
          'descargar.';
    }
    _failed.remove(id);
    _failedTitles.remove(id);
    _pending[id] = track;
    _progress[id] = 0;
    notifyListeners();
    _chain = _chain.then((_) => _run(track, id, resolve));
    return 'Descargando «${track.title}»';
  }

  Future<void> _run(
    CatalogTrack track,
    String id,
    DownloadSourceResolver resolve,
  ) async {
    final dir = await _directory();
    try {
      if (dir == null) throw const FileSystemException('Sin almacenamiento');
      final part = _file(dir, '$id.part');
      final target = _file(dir, id);
      final cached = await AudioDiskCache.instance.complete(id);
      if (cached != null) {
        // Ya se había escuchado entera: se copia sin gastar datos.
        await cached.copy(part.path);
      } else {
        OfflineMode.ensureOnline();
        await _fetcher(id, resolve, part, (progress) {
          _progress[id] = progress;
          notifyListeners();
        });
      }
      final bytes = await part.length();
      if (bytes <= 0) throw const FileSystemException('Archivo vacío');
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      final url = track.thumbnailUrl;
      if (url != null) await _saveCover(url, _file(dir, '$id.jpg'));
      _tracks[id] = DownloadedTrack(
        id: id,
        title: track.title,
        artist: track.artistName,
        bytes: bytes,
        savedAt: DateTime.now().millisecondsSinceEpoch,
        durationSeconds: track.durationSeconds,
        thumbnailUrl: url,
        artistId: track.artistId,
        albumId: track.albumId,
        albumName: track.albumName,
      );
      await _writeIndex(dir);
    } on Object catch (error) {
      if (dir != null) {
        try {
          final part = _file(dir, '$id.part');
          if (await part.exists()) await part.delete();
        } on Object {
          // Se limpia al arrancar.
        }
      }
      _failed[id] = error is OfflineFailure
          ? 'Sin conexión'
          : 'No se pudo descargar';
      _failedTitles[id] = track.title;
    } finally {
      _pending.remove(id);
      _progress.remove(id);
      notifyListeners();
    }
  }

  Future<void> _saveCover(String url, File target) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' || uri.host.isEmpty) return;
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > 2 * 1024 * 1024) return;
      }
      if (builder.isNotEmpty) await target.writeAsBytes(builder.takeBytes());
    } on Object {
      // Sin portada la canción se lista igual.
    } finally {
      client.close(force: true);
    }
  }

  /// Quita la descarga de [sourceId] (audio, portada y entrada del índice).
  Future<void> remove(String sourceId) async {
    await load();
    final dir = await _directory();
    if (_tracks.remove(sourceId) == null || dir == null) return;
    for (final name in [sourceId, '$sourceId.jpg']) {
      try {
        final file = _file(dir, name);
        if (await file.exists()) await file.delete();
      } on Object {
        // Un archivo que no se pudo borrar queda huérfano pero sin índice.
      }
    }
    try {
      await _writeIndex(dir);
    } on Object {
      // Se corrige en la próxima escritura.
    }
    notifyListeners();
  }

  Future<void> clear() async {
    for (final id in _tracks.keys.toList()) {
      await remove(id);
    }
  }

  /// Bytes que ocupan las descargas.
  Future<int> size() async {
    await load();
    var total = 0;
    for (final track in _tracks.values) {
      total += track.bytes;
    }
    return total;
  }

  /// Una canción descargada, como pista reproducible desde el archivo.
  CatalogTrack playable(DownloadedTrack track, Directory directory) =>
      CatalogTrack(
        id: 'youtube:${track.id}',
        title: track.title,
        artistName: track.artist,
        durationSeconds: track.durationSeconds,
        thumbnailUrl: track.thumbnailUrl,
        deviceAudio: Uri.file(
          '${directory.path}${Platform.pathSeparator}${track.id}',
        ),
        artistId: track.artistId,
        albumId: track.albumId,
        albumName: track.albumName,
      );

  /// La carpeta de las descargas (para armar las pistas reproducibles).
  Future<Directory?> directory() => _directory();
}

Future<void> _httpFetch(
  String sourceId,
  DownloadSourceResolver resolve,
  File target,
  void Function(double progress) onProgress,
) async {
  Object? last;
  // El segundo intento pide una URL nueva por si la primera caducó o falló.
  for (var attempt = 0; attempt < 2; attempt++) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final source = await resolve(sourceId, refresh: attempt > 0);
      final request = await client.getUrl(source.uri);
      source.headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: source.uri);
      }
      final total = response.contentLength;
      if (total > DownloadStore.maxTrackBytes) {
        await response.drain<void>().catchError((Object _) {});
        throw const FileSystemException('Archivo demasiado grande');
      }
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 25),
        )) {
          received += chunk.length;
          if (received > DownloadStore.maxTrackBytes) {
            throw const FileSystemException('Archivo demasiado grande');
          }
          sink.add(chunk);
          onProgress(total > 0 ? received / total : -1);
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || (total > 0 && received < total)) {
        throw const FileSystemException('Descarga incompleta');
      }
      return;
    } on Object catch (error) {
      last = error;
      if (error is FileSystemException || error is OfflineFailure) break;
    } finally {
      client.close(force: true);
    }
  }
  throw last ?? const FileSystemException('Descarga fallida');
}
