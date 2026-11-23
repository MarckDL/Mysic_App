import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/history/data/local_listens.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LocalListen listen(
  String id, {
  required DateTime at,
  String title = 'Tema',
  String? thumbnail,
}) => LocalListen(
  videoId: id,
  title: title,
  artist: 'Artista',
  at: at,
  listenedMs: 60000,
  durationSeconds: 200,
  thumbnailUrl: thumbnail,
);

void main() {
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 22, 12);
  late SqliteListens store;

  setUp(() async {
    final db = await SqliteListens.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    store = SqliteListens('a', () async => db);
  });

  test('adoptLegacy pasa el historial de la identidad anterior', () async {
    final db = await SqliteListens.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    const old =
        'abcdefghijklmnopqrstuvwxyz12'; // 28 caracteres, como los de la identidad anterior
    final before = SqliteListens(old, () async => db);
    await before.record(listen('aaaaaaaaaaa', at: now));
    final fresh = SqliteListens('0123456789abcdef01234567', () async => db);
    expect(await fresh.recent(), isEmpty);
    await fresh.adoptLegacy();
    expect((await fresh.recent()).map((t) => t.id), ['aaaaaaaaaaa']);
    // Una cuenta que ya tiene escuchas no adopta nada más.
    await before.record(listen('bbbbbbbbbbb', at: now));
    await fresh.adoptLegacy();
    expect((await fresh.recent()).map((t) => t.id), ['aaaaaaaaaaa']);
  });

  test('el historial antiguo se importa una sola vez por cuenta', () async {
    expect(await store.importPending(), isTrue);
    await store.importAll([
      listen('aaaaaaaaaaa', at: now.subtract(const Duration(days: 2))),
      listen('aaaaaaaaaaa', at: now.subtract(const Duration(days: 1))),
    ]);
    expect(await store.importPending(), isFalse);
    expect((await store.recent()).map((t) => t.id), ['aaaaaaaaaaa']);
  });

  test('Recientes: cada canción una vez, la última escucha primero', () async {
    await store.record(
      listen(
        'aaaaaaaaaaa',
        at: now.subtract(const Duration(hours: 5)),
        title: 'Vieja',
      ),
    );
    await store.record(
      listen('bbbbbbbbbbb', at: now.subtract(const Duration(hours: 3))),
    );
    await store.record(
      listen(
        'aaaaaaaaaaa',
        at: now.subtract(const Duration(hours: 1)),
        title: 'Nueva',
      ),
    );
    final recent = await store.recent();
    expect(recent.map((t) => t.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    // El título y la fecha son los de la última escucha.
    expect(recent.first.title, 'Nueva');
    expect(recent.first.listenedAt, now.subtract(const Duration(hours: 1)));
    expect(recent.first.playCount, isNull);
    expect(recent.first.canPlayInMysic, isTrue);
  });

  test(
    'Lo más oído: cuenta escuchas de 30 días y exige al menos dos',
    () async {
      // Tres veces la A, dos la B, una la C y una A antigua (no cuenta).
      for (final h in [1, 2, 3]) {
        await store.record(
          listen('aaaaaaaaaaa', at: now.subtract(Duration(hours: h))),
        );
      }
      for (final h in [4, 5]) {
        await store.record(
          listen('bbbbbbbbbbb', at: now.subtract(Duration(hours: h))),
        );
      }
      await store.record(
        listen('ccccccccccc', at: now.subtract(const Duration(hours: 6))),
      );
      await store.record(
        listen('ddddddddddd', at: now.subtract(const Duration(days: 40))),
      );
      await store.record(
        listen('ddddddddddd', at: now.subtract(const Duration(days: 41))),
      );
      final top = await store.mostPlayed(now: now);
      expect(top.map((t) => t.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
      expect(top.map((t) => t.playCount), [3, 2]);
    },
  );

  test('en un empate gana la escuchada más recientemente', () async {
    await store.record(
      listen('aaaaaaaaaaa', at: now.subtract(const Duration(days: 3))),
    );
    await store.record(
      listen('aaaaaaaaaaa', at: now.subtract(const Duration(days: 2))),
    );
    await store.record(
      listen('bbbbbbbbbbb', at: now.subtract(const Duration(hours: 5))),
    );
    await store.record(
      listen('bbbbbbbbbbb', at: now.subtract(const Duration(hours: 4))),
    );
    final top = await store.mostPlayed(now: now);
    expect(top.map((t) => t.id), ['bbbbbbbbbbb', 'aaaaaaaaaaa']);
  });

  test('cada cuenta ve solo lo suyo y puede borrarlo', () async {
    final db = await SqliteListens.openWith(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final alice = SqliteListens('alice', () async => db);
    final bob = SqliteListens('bob', () async => db);
    await alice.record(listen('aaaaaaaaaaa', at: now));
    await bob.record(listen('bbbbbbbbbbb', at: now));
    expect((await alice.recent()).map((t) => t.id), ['aaaaaaaaaaa']);
    expect((await bob.recent()).map((t) => t.id), ['bbbbbbbbbbb']);
    await alice.clear();
    expect(await alice.recent(), isEmpty);
    expect(await bob.recent(), hasLength(1));
  });

  test(
    'el límite recorta la lista y guarda los metadatos de la canción',
    () async {
      await store.record(
        listen('aaaaaaaaaaa', at: now, thumbnail: 'https://example.test/a.jpg'),
      );
      for (var i = 0; i < 5; i++) {
        await store.record(
          listen('b${i}bbbbbbbbbb', at: now.subtract(Duration(hours: i + 1))),
        );
      }
      final two = await store.recent(limit: 2);
      expect(two, hasLength(2));
      expect(two.first.thumbnailUrl, 'https://example.test/a.jpg');
      expect(two.first.durationSeconds, 200);
    },
  );

  test('con la actividad en pausa no se guarda nada nuevo', () async {
    store.paused = true;
    await store.record(listen('aaaaaaaaaaa', at: now));
    expect(await store.recent(), isEmpty);
    store.paused = false;
    await store.record(listen('aaaaaaaaaaa', at: now));
    expect(await store.recent(), hasLength(1));
  });

  test('sin base de datos, guardar y leer no fallan', () async {
    final broken = SqliteListens(
      'a',
      () async => throw StateError('sin disco'),
    );
    await broken.record(listen('aaaaaaaaaaa', at: now));
    expect(await broken.recent(), isEmpty);
    expect(await broken.mostPlayed(), isEmpty);
    await broken.clear();
  });
}
