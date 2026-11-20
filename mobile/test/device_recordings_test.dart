import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/data/device_recordings.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

void main() {
  const id = 'ABCDEFGHIJK';
  late Directory root;
  late Stream<List<int>>? Function() selection;
  DeviceRecordings store(String uid) => DeviceRecordings(
    uid,
    directory: () async => root,
    pick: () async => selection(),
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mysic-recordings-');
    selection = () => Stream.fromIterable([
      [1, 2],
      [3],
    ]);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'una copia se reabre solo con su usuario y vínculo; desvincular conserva el original',
    () async {
      final original = File('${root.path}/original.wav');
      await original.writeAsBytes([1, 2, 3, 4]);
      selection = original.openRead;
      final a = store('uid-A'), b = store('uid-B');
      final a1 = (await a.attach('gen-1', id, () => true))!;
      final b1 = (await b.attach('gen-1', id, () => true))!;
      expect(a1, isNot(b1));
      expect((await store('uid-A').open('gen-1', () => true))[id], a1);
      expect(await a.open('gen-2', () => true), isEmpty);
      expect(await File.fromUri(a1).exists(), isFalse);
      expect((await b.open('gen-1', () => true))[id], b1);
      expect(await b.open(null, () => true), isEmpty);
      expect(await File.fromUri(b1).exists(), isFalse);
      expect(await original.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'cancelar, cambiar de cuenta durante la lectura o elegir un archivo vacío conserva la copia anterior',
    () async {
      final a = store('a');
      var active = true;
      final uri = (await a.attach('g', id, () => active))!;
      final file = File.fromUri(uri);
      selection = () => null;
      expect(await a.attach('g', id, () => active), isNull);
      selection = () => const Stream<List<int>>.empty();
      await expectLater(a.attach('g', id, () => active), throwsFormatException);
      Stream<List<int>> interrupted() async* {
        yield [4];
        active = false;
        yield [5];
      }

      selection = interrupted;
      expect(await a.attach('g', id, () => active), isNull);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(await file.parent.list().length, 1);
      active = true;
      selection = () => Stream.value([8, 9]);
      expect(await a.attach('g', id, () => active), uri);
      expect(await file.readAsBytes(), [8, 9]);
      await a.remove('g', id);
      expect(await a.open('g', () => true), isEmpty);
    },
  );

  test('las rutas de archivo solo se obtienen del dispositivo', () async {
    selection = () => throw StateError('No debe abrir el selector');
    expect(await store('a').attach('g', '../privado', () => true), isNull);
    final item = MusicTrack.fromJson({
      'id': id,
      'title': 'Tema',
      'artist': 'Canal',
      'durationSeconds': 10,
      'playback': 'licensed',
      'audioUrl': 'file:///otro/archivo',
      'deviceAudio': 'file:///otro/archivo',
    });
    expect(item.canPlayInMysic, isFalse);
    expect(item.toPlaybackTrack().isConnectedAudio, isFalse);
  });
}
