import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/offline_mode.dart';
import 'package:mysic/features/downloads/data/download_store.dart';
import 'package:mysic/features/playback/data/audio_disk_cache.dart';
import 'package:mysic/features/playback/domain/playback_source_resolver.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

const _track = CatalogTrack(
  id: 'youtube:abcdefghijk',
  title: 'Una canción',
  artistName: 'Artista',
  durationSeconds: 200,
);

Future<PlaybackSource> _noSource(String id, {bool refresh = false}) =>
    throw StateError('no debe resolverse');

void main() {
  late Directory dir;

  setUp(() async {
    OfflineMode.instance.reset();
    dir = await Directory.systemTemp.createTemp('mysic_downloads_test');
  });

  tearDown(() async {
    OfflineMode.instance.reset();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DownloadFetcher writes(List<int> bytes, {List<String>? log}) =>
      (id, resolve, target, onProgress) async {
        log?.add(id);
        onProgress(.5);
        await target.writeAsBytes(bytes);
        onProgress(1);
      };

  group('qué se puede descargar', () {
    test('una canción normal sí', () {
      expect(DownloadStore.refusal(_track), isNull);
    });

    test('un vídeo de más de 20 minutos no', () {
      const long = CatalogTrack(
        id: 'youtube:abcdefghijk',
        title: 'Mix de 2 horas',
        artistName: 'Canal',
        durationSeconds: 2 * 60 * 60,
      );
      expect(DownloadStore.refusal(long), contains('20 minutos'));
      const limit = CatalogTrack(
        id: 'youtube:abcdefghijk',
        title: 'Justo 20 min',
        artistName: 'Canal',
        durationSeconds: 20 * 60,
      );
      expect(DownloadStore.refusal(limit), isNull);
      const over = CatalogTrack(
        id: 'youtube:abcdefghijk',
        title: '20 min y un segundo',
        artistName: 'Canal',
        durationSeconds: 20 * 60 + 1,
      );
      expect(DownloadStore.refusal(over), isNotNull);
    });

    test('un archivo propio, una muestra o la prueba no', () {
      final file = CatalogTrack(
        id: 'youtube:abcdefghijk',
        title: 'Archivo',
        artistName: 'Yo',
        deviceAudio: Uri.file('/tmp/a'),
      );
      expect(DownloadStore.refusal(file), isNotNull);
      const preview = CatalogTrack(
        id: '${CatalogTrack.musicPreviewPrefix}abcdefghijk',
        title: 'Muestra',
        artistName: 'Mysic',
      );
      expect(DownloadStore.refusal(preview), isNotNull);
      const demo = CatalogTrack(
        id: 'demo:xyz',
        title: 'Prueba',
        artistName: 'Mysic',
      );
      expect(DownloadStore.refusal(demo), isNotNull);
    });
  });

  group('el audio guardado solo cubre canciones normales', () {
    test('worthKeeping respeta el límite y no guarda sin duración', () {
      expect(AudioDiskCache.worthKeeping(200), isTrue);
      expect(AudioDiskCache.worthKeeping(20 * 60), isTrue);
      expect(AudioDiskCache.worthKeeping(20 * 60 + 1), isFalse);
      expect(AudioDiskCache.worthKeeping(3 * 60 * 60), isFalse);
      expect(AudioDiskCache.worthKeeping(null), isFalse);
      expect(AudioDiskCache.worthKeeping(0), isFalse);
    });

    test('las descargas usan el mismo límite', () {
      expect(DownloadStore.maxTrackSeconds, AudioDiskCache.maxTrackSeconds);
    });
  });

  group('descargar', () {
    test('baja la canción, la indexa y sobrevive a reabrir', () async {
      final log = <String>[];
      final store = DownloadStore.forTest(
        dir,
        fetcher: writes([1, 2, 3, 4], log: log),
      );
      await store.load();
      expect(store.hasDownloads, isFalse);

      expect(store.enqueue(_track, _noSource), contains('Descargando'));
      expect(store.isBusy('abcdefghijk'), isTrue);
      // Se vuelve a pedir mientras baja: no se duplica.
      expect(store.enqueue(_track, _noSource), 'Ya se está descargando.');

      // Espera a que acabe la cola.
      while (store.isBusy('abcdefghijk')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(log, ['abcdefghijk']);
      expect(store.isDownloaded('abcdefghijk'), isTrue);
      expect(store.failures, isEmpty);
      final file = await store.file('abcdefghijk');
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [1, 2, 3, 4]);
      expect(await store.size(), 4);
      expect(store.enqueue(_track, _noSource), 'Ya está descargada.');
      // No quedan descargas a medias.
      expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);

      // Otra instancia sobre la misma carpeta ve lo guardado.
      final reopened = DownloadStore.forTest(dir);
      await reopened.load();
      final info = reopened.infoOf('abcdefghijk');
      expect(info?.title, 'Una canción');
      expect(info?.artist, 'Artista');
      expect(info?.durationSeconds, 200);
      expect(info?.bytes, 4);
    });

    test('una descarga que falla queda como fallo y no como canción', () async {
      final store = DownloadStore.forTest(
        dir,
        fetcher: (id, resolve, target, onProgress) async {
          await target.writeAsBytes([9]);
          throw const FileSystemException('se cortó');
        },
      );
      await store.load();
      store.enqueue(_track, _noSource);
      while (store.isBusy('abcdefghijk')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.isDownloaded('abcdefghijk'), isFalse);
      expect(store.failures, hasLength(1));
      expect(store.failures.single.title, 'Una canción');
      // El archivo a medias se borra.
      expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      store.dismissFailure('abcdefghijk');
      expect(store.failures, isEmpty);
    });

    test('con el modo sin conexión activo no se descarga', () async {
      final store = DownloadStore.forTest(dir, fetcher: writes([1]));
      await store.load();
      OfflineMode.instance.manual = true;
      expect(store.enqueue(_track, _noSource), contains('Sin conexión'));
      expect(store.isBusy('abcdefghijk'), isFalse);
    });

    test('quitar una descarga borra el archivo y el índice', () async {
      final store = DownloadStore.forTest(dir, fetcher: writes([1, 2]));
      await store.load();
      store.enqueue(_track, _noSource);
      while (store.isBusy('abcdefghijk')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.isDownloaded('abcdefghijk'), isTrue);
      await store.remove('abcdefghijk');
      expect(store.isDownloaded('abcdefghijk'), isFalse);
      expect(await store.file('abcdefghijk'), isNull);
      final reopened = DownloadStore.forTest(dir);
      await reopened.load();
      expect(reopened.hasDownloads, isFalse);
    });

    test(
      'al abrir se descartan las descargas sin archivo y las a medias',
      () async {
        final store = DownloadStore.forTest(dir, fetcher: writes([5, 6, 7]));
        await store.load();
        store.enqueue(_track, _noSource);
        while (store.isBusy('abcdefghijk')) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        // Se pierde el archivo y queda una descarga a medias de otra canción.
        await File('${dir.path}/abcdefghijk').delete();
        await File('${dir.path}/zzzzzzzzzzz.part').writeAsBytes([1]);
        final reopened = DownloadStore.forTest(dir);
        await reopened.load();
        expect(reopened.hasDownloads, isFalse);
        expect(File('${dir.path}/zzzzzzzzzzz.part').existsSync(), isFalse);
      },
    );

    test('la pista descargada se reproduce desde su archivo', () async {
      final store = DownloadStore.forTest(dir, fetcher: writes([1]));
      await store.load();
      store.enqueue(_track, _noSource);
      while (store.isBusy('abcdefghijk')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final playable = store.playable(store.tracks.single, dir);
      expect(playable.id, 'youtube:abcdefghijk');
      expect(playable.deviceAudio?.scheme, 'file');
      expect(
        playable.deviceAudio?.toFilePath(),
        '${dir.path}${Platform.pathSeparator}abcdefghijk',
      );
      expect(File(playable.deviceAudio!.toFilePath()).existsSync(), isTrue);
      expect(playable.isConnectedAudio, isTrue);
    });
  });

  group('modo sin conexión', () {
    test(
      'sin el ajuste manual la app nunca se pone sola en modo sin conexión',
      () {
        // Antes, arrancar sin internet con descargas encerraba la app en
        // «solo descargadas» y bloqueaba toda la red. Ahora solo lo activa el
        // usuario; lo descargado se ve y suena desde Biblioteca → Descargas.
        final mode = OfflineMode.instance;
        expect(mode.active, isFalse);
        expect(mode.manual, isFalse);
      },
    );

    test('el ajuste manual activa el modo y reset lo apaga', () {
      final mode = OfflineMode.instance..manual = true;
      expect(mode.active, isTrue);
      mode.reset();
      expect(mode.active, isFalse);
    });
    test('con el modo activo ninguna petición de Dio sale', () async {
      var reached = false;
      final dio = Dio()
        ..interceptors.add(OfflineMode.dioGuard)
        ..httpClientAdapter = _CountingAdapter(() => reached = true);
      OfflineMode.instance.manual = true;
      await expectLater(
        dio.get<dynamic>('https://example.test/'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<OfflineFailure>(),
          ),
        ),
      );
      expect(reached, isFalse);
      OfflineMode.instance.manual = false;
      await dio.get<dynamic>('https://example.test/');
      expect(reached, isTrue);
    });

    test('ensureOnline lanza solo con el modo activo', () {
      expect(OfflineMode.ensureOnline, returnsNormally);
      OfflineMode.instance.manual = true;
      expect(OfflineMode.ensureOnline, throwsA(isA<OfflineFailure>()));
    });
  });
}

class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.onFetch);

  final void Function() onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onFetch();
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}
