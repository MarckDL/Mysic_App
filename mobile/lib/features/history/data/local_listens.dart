import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../connected_library/domain/music_mode.dart';
import '../../search/domain/catalog_track.dart';

/// Una escucha guardada en el teléfono.
class LocalListen {
  const LocalListen({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.at,
    required this.listenedMs,
    this.durationSeconds,
    this.thumbnailUrl,
    this.artistId,
    this.albumId,
    this.albumName,
  });

  /// La escucha de [track] (un `youtube:<id>`), o null si no es una canción
  /// de YouTube.
  static LocalListen? of(CatalogTrack track, int listenedMs, DateTime at) {
    if (!track.id.startsWith('youtube:')) return null;
    return LocalListen(
      videoId: track.id.substring('youtube:'.length),
      title: track.title,
      artist: track.artistName,
      at: at,
      listenedMs: listenedMs,
      durationSeconds: track.durationSeconds,
      thumbnailUrl: track.thumbnailUrl,
      artistId: track.artistId,
      albumId: track.albumId,
      albumName: track.albumName,
    );
  }

  final String videoId;
  final String title;
  final String artist;
  final DateTime at;
  final int listenedMs;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final String? artistId;
  final String? albumId;
  final String? albumName;
}

/// Dónde se guardan las escuchas y de dónde salen Recientes y Lo más oído.
abstract interface class ListenStore {
  /// Con la actividad en pausa (Ajustes) no se guarda nada nuevo.
  set paused(bool value);

  /// Guarda una escucha. Un fallo no se propaga: la música no depende de esto.
  Future<void> record(LocalListen listen);

  /// Las últimas canciones escuchadas, una vez cada una, la más reciente
  /// primero.
  Future<List<MusicTrack>> recent({int limit = 100});

  /// Las canciones más escuchadas en los últimos [days] días, con su número de
  /// escuchas, solo las que suman al menos [minPlays].
  Future<List<MusicTrack>> mostPlayed({
    int days = 30,
    int minPlays = 2,
    int limit = 50,
  });

  /// Borra todo lo guardado de esta cuenta.
  Future<void> clear();

  /// Con la identidad nueva (YouTube Music), pasa a esta cuenta el historial
  /// guardado con la anterior (la anterior, de 28 caracteres), si esta aún no tiene.
  Future<void> adoptLegacy();

  /// Si aún falta traer el historial que esta cuenta tenía en el servidor.
  Future<bool> importPending();

  /// Guarda de golpe [listens] (el historial antiguo) y anota que ya se
  /// importó, para no repetirlo.
  Future<void> importAll(List<LocalListen> listens);
}

/// Las escuchas de cada cuenta en la base SQLite del teléfono.
///
/// Cada fila es una escucha (una canción que sonó el tiempo suficiente para
/// contar). Recientes y Lo más oído son consultas sobre esas filas, así que
/// nada se calcula ni se guarda dos veces.
class SqliteListens implements ListenStore {
  SqliteListens(this.uid, [Future<Database> Function()? open])
    : _open = open ?? _openDefault;

  final String uid;
  final Future<Database> Function() _open;
  bool _paused = false;

  @override
  set paused(bool value) => _paused = value;
  Future<Database>? _db;

  static const _file = 'mysic_listens.db';

  static Future<Database> _openDefault() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/$_file',
      version: 2,
      onCreate: _create,
      onUpgrade: (db, from, to) async {
        if (from < 2) await _createImported(db);
      },
    );
  }

  static Future<void> _createImported(Database db) =>
      db.execute('CREATE TABLE IF NOT EXISTS imported (uid TEXT PRIMARY KEY)');

  /// Abre (o crea) la base en [path] con otra fábrica; para las pruebas.
  static Future<Database> openWith(DatabaseFactory factory, String path) =>
      factory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 2, onCreate: _create),
      );

  static Future<void> _create(Database db, int version) async {
    await _createImported(db);
    await db.execute('''
      CREATE TABLE listen (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL,
        video_id TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        duration_s INTEGER,
        thumbnail TEXT,
        artist_id TEXT,
        album_id TEXT,
        album_name TEXT,
        at_ms INTEGER NOT NULL,
        listened_ms INTEGER NOT NULL
      )
    ''');
    // Los dos recorridos que hacen las pantallas: por fecha, y por canción.
    await db.execute('CREATE INDEX listen_at ON listen (uid, at_ms DESC)');
    await db.execute(
      'CREATE INDEX listen_video ON listen (uid, video_id, at_ms)',
    );
  }

  Future<Database> get _database => _db ??= _open();

  @override
  Future<void> record(LocalListen listen) async {
    if (_paused) return;
    try {
      final db = await _database;
      await db.insert('listen', {
        'uid': uid,
        'video_id': listen.videoId,
        'title': listen.title,
        'artist': listen.artist,
        'duration_s': listen.durationSeconds,
        'thumbnail': listen.thumbnailUrl,
        'artist_id': listen.artistId,
        'album_id': listen.albumId,
        'album_name': listen.albumName,
        'at_ms': listen.at.millisecondsSinceEpoch,
        'listened_ms': listen.listenedMs,
      });
    } on Object {
      // Sin base de datos (o sin disco) la escucha no se guarda; la música
      // sigue sonando igual.
      _db = null;
    }
  }

  // Las columnas sueltas de un GROUP BY con MAX(at_ms) salen de la fila más
  // reciente de cada canción: así el título y la portada son los últimos.
  static const _columns = '''
    video_id, title, artist, duration_s, thumbnail, artist_id, album_id,
    album_name, MAX(at_ms) AS last_at
  ''';

  @override
  Future<List<MusicTrack>> recent({int limit = 100}) async {
    try {
      final db = await _database;
      final rows = await db.rawQuery(
        'SELECT $_columns FROM listen WHERE uid = ? '
        'GROUP BY video_id ORDER BY last_at DESC LIMIT ?',
        [uid, limit],
      );
      return [for (final row in rows) _track(row)];
    } on Object {
      _db = null;
      return const [];
    }
  }

  @override
  Future<List<MusicTrack>> mostPlayed({
    int days = 30,
    int minPlays = 2,
    int limit = 50,
    DateTime? now,
  }) async {
    try {
      final db = await _database;
      final since = (now ?? DateTime.now())
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;
      final rows = await db.rawQuery(
        'SELECT $_columns, COUNT(*) AS plays FROM listen '
        'WHERE uid = ? AND at_ms >= ? GROUP BY video_id '
        'HAVING plays >= ? ORDER BY plays DESC, last_at DESC LIMIT ?',
        [uid, since, minPlays, limit],
      );
      return [for (final row in rows) _track(row)];
    } on Object {
      _db = null;
      return const [];
    }
  }

  @override
  Future<void> clear() async {
    try {
      final db = await _database;
      await db.delete('listen', where: 'uid = ?', whereArgs: [uid]);
    } on Object {
      _db = null;
    }
  }

  @override
  Future<void> adoptLegacy() async {
    try {
      final db = await _database;
      final own = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM listen WHERE uid = ?', [uid]),
      );
      if ((own ?? 0) > 0) return;
      await db.update('listen', {'uid': uid}, where: 'LENGTH(uid) = 28');
    } on Object {
      _db = null;
    }
  }

  @override
  Future<bool> importPending() async {
    try {
      final db = await _database;
      final rows = await db.query(
        'imported',
        where: 'uid = ?',
        whereArgs: [uid],
      );
      return rows.isEmpty;
    } on Object {
      _db = null;
      return false;
    }
  }

  @override
  Future<void> importAll(List<LocalListen> listens) async {
    try {
      final db = await _database;
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final listen in listens) {
          batch.insert('listen', {
            'uid': uid,
            'video_id': listen.videoId,
            'title': listen.title,
            'artist': listen.artist,
            'duration_s': listen.durationSeconds,
            'thumbnail': listen.thumbnailUrl,
            'artist_id': listen.artistId,
            'album_id': listen.albumId,
            'album_name': listen.albumName,
            'at_ms': listen.at.millisecondsSinceEpoch,
            'listened_ms': listen.listenedMs,
          });
        }
        batch.insert('imported', {'uid': uid});
        await batch.commit(noResult: true);
      });
    } on Object {
      _db = null;
    }
  }

  static MusicTrack _track(Map<String, Object?> row) => MusicTrack(
    row['video_id']! as String,
    row['title']! as String,
    row['artist']! as String,
    (row['duration_s'] as int?) ?? 0,
    false,
    DateTime.fromMillisecondsSinceEpoch(row['last_at']! as int),
    nativePlayback: true,
    artistId: row['artist_id'] as String?,
    albumId: row['album_id'] as String?,
    albumName: row['album_name'] as String?,
    playCount: row['plays'] as int?,
    thumbnailUrl: row['thumbnail'] as String?,
  );
}

/// Las escuchas de la cuenta [uid] en este teléfono.
final localListensProvider = Provider.family<ListenStore, String>(
  (ref, uid) => SqliteListens(uid),
);
