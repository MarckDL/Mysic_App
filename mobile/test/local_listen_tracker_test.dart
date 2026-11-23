import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/history/application/listening_tracker.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

class _Clock implements Stopwatch {
  int ms = 0;
  bool running = false;
  @override
  int get elapsedMilliseconds => ms;
  @override
  Duration get elapsed => Duration(milliseconds: ms);
  @override
  int get elapsedMicroseconds => ms * 1000;
  @override
  int get elapsedTicks => ms;
  @override
  int get frequency => 1000;
  @override
  bool get isRunning => running;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void reset() => ms = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = CatalogTrack(
    id: 'youtube:abcdefghijk',
    title: 'Canción',
    artistName: 'Artista',
    durationSeconds: 200,
    albumId: 'MPREb_4U7yfKKFZLv',
    albumName: 'Disco',
    // Como las de la cuenta musical: pasan por el resolvedor del teléfono.
    musicAccountTrack: true,
  );
  late _Clock clock;
  late List<(CatalogTrack, int, DateTime)> counted;
  late ListeningTracker tracker;

  setUp(() {
    clock = _Clock();
    counted = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.mysic/history'),
          (call) async => call.method == 'load' ? '{}' : null,
        );
    tracker = ListeningTracker(
      () => true,
      clock: clock,
      onListened: (t, ms, at) => counted.add((t, ms, at)),
    );
    addTearDown(tracker.dispose);
  });

  test('una escucha cuenta una sola vez al pasar los 30 segundos', () {
    tracker.begin(track);
    tracker.phase(TrackAudioPhase.playing);
    clock.ms = 20000;
    tracker.checkpoint();
    // Antes del umbral no cuenta.
    expect(counted, isEmpty);
    clock.ms = 31000;
    tracker.checkpoint();
    clock.ms = 61000;
    tracker.checkpoint();
    expect(counted, hasLength(1));
    expect(counted.single.$1.id, 'youtube:abcdefghijk');
    expect(counted.single.$1.albumName, 'Disco');
    expect(counted.single.$2, 31000);
  });

  test('la misma canción escuchada otra vez cuenta de nuevo', () {
    for (var i = 0; i < 2; i++) {
      tracker.begin(track);
      tracker.phase(TrackAudioPhase.playing);
      clock.ms = 40000;
      tracker.checkpoint();
      tracker.finish();
    }
    expect(counted, hasLength(2));
  });

  test('una canción corta cuenta al llegar a la mitad', () {
    const short = CatalogTrack(
      id: 'youtube:zzzzzzzzzzz',
      title: 'Corta',
      artistName: 'Artista',
      durationSeconds: 40,
      musicAccountTrack: true,
    );
    tracker.begin(short);
    tracker.phase(TrackAudioPhase.playing);
    clock.ms = 21000;
    tracker.checkpoint();
    expect(counted, hasLength(1));
  });
}
