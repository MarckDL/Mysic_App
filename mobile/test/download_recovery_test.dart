import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/offline_mode.dart';
import 'package:mysic/features/downloads/data/download_store.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

const _ids = [
  'aaaaaaaaaaa',
  'bbbbbbbbbbb',
  'ccccccccccc',
  'ddddddddddd',
  'eeeeeeeeeee',
  'fffffffffff',
];

CatalogTrack _track(String id, {String? album}) => CatalogTrack(
  id: 'youtube:$id',
  title: 'Canción $id',
  artistName: 'Artista',
  albumName: album,
);

void main() {
  late Directory dir;

  setUp(() async {
    OfflineMode.instance.reset();
    dir = await Directory.systemTemp.createTemp('mysic_recovery');
  });

  tearDown(() async {
    OfflineMode.instance.reset();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DownloadStore store() => DownloadStore.forTest(
    dir,
    fetcher: (id, resolve, target, onProgress) async {
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await target.writeAsBytes([1, 2, 3]);
    },
  );

  Future<void> download(DownloadStore s, List<String> ids) async {
    for (final id in ids) {
      s.enqueue(_track(id), (sourceId, {refresh = false}) => throw 'no');
    }
    while (ids.any(s.isBusy)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'varias escrituras a la vez no dañan el índice ni pierden canciones',
    () async {
      final s = store();
      await s.load();
      // Descargas en marcha mientras se rellena un álbum, se guarda una
      // colección y se quita una canción: todo escribe el índice a la vez.
      final running = download(s, _ids);
      await Future<void>.delayed(const Duration(milliseconds: 8));
      await Future.wait([
        s.fillAlbum([_ids[0], _ids[1]], 'MPREb_x', 'Un álbum'),
        s.keepCollection(
          DownloadedCollection(
            id: 'MPREb_x',
            album: true,
            title: 'Un álbum',
            trackIds: _ids,
            savedAt: 1,
          ),
        ),
        s.remove(_ids[0]),
      ]);
      await running;
      // Que la fila de escritura termine antes de reabrir.
      await s.keepCollection(
        DownloadedCollection(
          id: 'MPREb_y',
          album: true,
          title: 'Otro',
          trackIds: [_ids[2]],
          savedAt: 2,
        ),
      );

      final again = store();
      await again.load();
      expect(
        again.tracks.map((t) => t.id).toSet(),
        s.tracks.map((t) => t.id).toSet(),
      );
      expect(again.tracks.length, greaterThanOrEqualTo(5));
      expect(again.collections.length, 2);
      // El índice se puede leer como JSON y no quedan temporales.
      final index = jsonDecode(
        await File('${dir.path}/index.json').readAsString(),
      );
      expect(index, isA<List<dynamic>>());
      expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    },
  );

  test(
    'un índice dañado se reconstruye con las fichas de cada canción',
    () async {
      final s = store();
      await s.load();
      await download(s, _ids.take(4).toList());
      await s.keepCollection(
        DownloadedCollection(
          id: 'MPREb_x',
          album: true,
          title: 'Un álbum',
          trackIds: _ids.take(4).toList(),
          savedAt: 1,
        ),
      );

      // El índice y su copia quedan ilegibles.
      await File(
        '${dir.path}/index.json',
      ).writeAsString('[{"id":"aaaaaaaaaaa"');
      await File('${dir.path}/index.json.bak').writeAsString('basura');

      final again = store();
      await again.load();
      expect(again.tracks.length, 4, reason: 'las fichas recuperan las 4');
      expect(again.collections.map((c) => c.id), ['MPREb_x']);
      // Y el índice vuelve a ser válido para el próximo arranque.
      final third = store();
      await third.load();
      expect(third.tracks.length, 4);
    },
  );

  test('sin índice, las canciones siguen ahí gracias a sus fichas', () async {
    final s = store();
    await s.load();
    await download(s, _ids.take(3).toList());
    await File('${dir.path}/index.json').delete();
    await File(
      '${dir.path}/index.json.bak',
    ).delete().catchError((_) => File(''));

    final again = store();
    await again.load();
    expect(again.tracks.length, 3);
    expect(await again.file(_ids[0]), isNotNull);
  });

  test('un índice dañado se recupera de su copia anterior', () async {
    final s = store();
    await s.load();
    await download(s, _ids.take(2).toList());
    // Tras dos escrituras existe la copia con la primera.
    expect(File('${dir.path}/index.json.bak').existsSync(), isTrue);
    await File('${dir.path}/index.json').writeAsString('no es json');
    for (final id in _ids.take(2)) {
      await File('${dir.path}/$id.json').delete();
    }

    final again = store();
    await again.load();
    expect(again.tracks, isNotEmpty);
  });

  test(
    'las descargas anteriores a las fichas reciben la suya al arrancar',
    () async {
      // Un teléfono con la versión anterior: audio e índice, sin fichas.
      for (final id in _ids.take(2)) {
        await File('${dir.path}/$id').writeAsBytes([9, 9]);
      }
      await File('${dir.path}/index.json').writeAsString(
        jsonEncode([
          for (final id in _ids.take(2))
            DownloadedTrack(
              id: id,
              title: 'Vieja $id',
              artist: 'A',
              bytes: 2,
              savedAt: 1,
            ).toJson(),
        ]),
      );

      final s = store();
      await s.load();
      expect(s.tracks.length, 2);
      for (final id in _ids.take(2)) {
        expect(File('${dir.path}/$id.json').existsSync(), isTrue);
      }

      // Ahora el índice se pierde y las fichas, nacidas de la migración,
      // salvan la lista.
      await File('${dir.path}/index.json').delete();
      final again = store();
      await again.load();
      expect(again.tracks.map((t) => t.title).toSet(), {
        'Vieja aaaaaaaaaaa',
        'Vieja bbbbbbbbbbb',
      });
    },
  );

  test('quitar una canción borra también su ficha', () async {
    final s = store();
    await s.load();
    await download(s, [_ids[0]]);
    expect(File('${dir.path}/${_ids[0]}.json').existsSync(), isTrue);
    await s.remove(_ids[0]);
    expect(File('${dir.path}/${_ids[0]}.json').existsSync(), isFalse);
    final again = store();
    await again.load();
    expect(again.hasDownloads, isFalse);
  });

  test('un audio sin ficha ni índice no aparece pero no rompe nada', () async {
    await File('${dir.path}/${_ids[0]}').writeAsBytes([1]);
    final s = store();
    await s.load();
    expect(s.hasDownloads, isFalse);
  });
}
