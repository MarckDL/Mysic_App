import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/downloads/data/download_store.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

DownloadedCollection _collection(String id, List<String> tracks) =>
    DownloadedCollection(
      id: id,
      album: true,
      title: 'Álbum $id',
      subtitle: 'Artista',
      thumbnailUrl: 'https://example.com/$id.jpg',
      trackIds: tracks,
      savedAt: 1,
    );

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mysic_collections');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('se guarda y se lee en JSON, sin ids de canción inválidos', () {
    final json = _collection('MPREb_a', ['aaaaaaaaaaa']).toJson();
    final read = DownloadedCollection.fromJson({
      ...json,
      'trackIds': ['aaaaaaaaaaa', 'mal', 3],
    });
    expect(read?.id, 'MPREb_a');
    expect(read?.album, isTrue);
    expect(read?.subtitle, 'Artista');
    expect(read?.trackIds, ['aaaaaaaaaaa']);
    expect(DownloadedCollection.fromJson({'id': 'x'}), isNull);
  });

  test('una colección guardada sobrevive a un reinicio', () async {
    final store = DownloadStore.forTest(dir);
    await store.keepCollection(_collection('MPREb_a', ['aaaaaaaaaaa']));
    expect(store.collection('MPREb_a')?.title, 'Álbum MPREb_a');

    final again = DownloadStore.forTest(dir);
    await again.load();
    expect(again.collections.map((c) => c.id), ['MPREb_a']);
  });

  test('quitar un álbum borra sus archivos pero no los que otra colección '
      'también usa', () async {
    Future<void> download(DownloadStore store, String id) async {
      store.enqueue(
        CatalogTrack(id: 'youtube:$id', title: id, artistName: 'A'),
        (sourceId, {refresh = false}) => throw StateError('no se resuelve'),
      );
      while (store.isBusy(id)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    final store = DownloadStore.forTest(
      dir,
      fetcher: (id, resolve, target, onProgress) async {
        await target.writeAsBytes([1, 2, 3]);
      },
    );
    await store.load();
    // El álbum lleva a, b y c; la playlist, b y d: b es de las dos.
    for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']) {
      await download(store, id);
    }
    await download(store, 'ddddddddddd');
    await store.keepCollection(
      _collection('MPREb_a', ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']),
    );
    await store.keepCollection(
      DownloadedCollection(
        id: 'PLlista',
        album: false,
        title: 'Lista',
        trackIds: ['bbbbbbbbbbb', 'ddddddddddd'],
        savedAt: 2,
      ),
    );

    // Quitar el álbum: se van a y c; b se queda porque la playlist lo usa.
    expect(await store.releaseCollection('MPREb_a'), 2);
    expect(store.isDownloaded('aaaaaaaaaaa'), isFalse);
    expect(store.isDownloaded('ccccccccccc'), isFalse);
    expect(store.isDownloaded('bbbbbbbbbbb'), isTrue);
    expect(store.isDownloaded('ddddddddddd'), isTrue);
    expect(await store.file('aaaaaaaaaaa'), isNull);
    expect(await store.file('bbbbbbbbbbb'), isNotNull);
    expect(store.collection('PLlista'), isNotNull);
    expect(store.tracksOf(store.collection('PLlista')!).length, 2);

    // Ahora la playlist ya es la única dueña de b y d.
    expect(await store.releaseCollection('PLlista'), 2);
    expect(store.hasDownloads, isFalse);

    // Y el resultado sobrevive a reabrir.
    final again = DownloadStore.forTest(dir);
    await again.load();
    expect(again.collections, isEmpty);
    expect(again.hasDownloads, isFalse);
  });

  test('quitar una colección conserva las canciones de otra', () async {
    final store = DownloadStore.forTest(dir);
    await store.load();
    await store.keepCollection(
      _collection('MPREb_a', ['aaaaaaaaaaa', 'bbbbbbbbbbb']),
    );
    await store.keepCollection(_collection('MPREb_b', ['bbbbbbbbbbb']));
    // Sin canciones bajadas no hay nada que borrar, pero la colección se va.
    expect(await store.releaseCollection('MPREb_a'), 0);
    expect(store.collection('MPREb_a'), isNull);
    expect(store.collection('MPREb_b'), isNotNull);
  });
}
