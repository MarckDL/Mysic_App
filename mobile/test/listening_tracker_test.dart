import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/history/application/listening_tracker.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';
import 'support/fake_auth_repository.dart';

class TestClock implements Stopwatch {
  int ms = 0;
  bool running = false;
  void advance(int delta) {
    if (running) ms += delta;
  }

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
  void start() {
    running = true;
  }

  @override
  void stop() {
    running = false;
  }

  @override
  void reset() {
    ms = 0;
  }
}

Future<void> drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mysic/history');
  const track = CatalogTrack(
    id: 'youtube:abcdefghijk',
    title: 'Song',
    artistName: 'Artist',
    durationSeconds: 120,
  );
  late Map<String, String> storage;
  late List<Map<String, dynamic>> sent;
  late TestClock clock;
  late FakeAuthRepository auth;
  late bool offline;
  ListeningTracker create() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (offline) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          sent.add({
            'path': options.path,
            ...Map<String, dynamic>.from(options.data as Map),
          });
          handler.resolve(Response(requestOptions: options, statusCode: 204));
        },
      ),
    );
    return ListeningTracker(
      AuthenticatedApiClient(auth, baseUrl: 'https://example.test', dio: dio),
      () => auth.currentUser?.uid == 'a',
      'a',
      clock: clock,
    );
  }

  setUp(() {
    storage = {};
    sent = [];
    clock = TestClock();
    auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    offline = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final uid = args['uid'] as String;
          if (call.method == 'load') return storage[uid] ?? '{}';
          storage[uid] = args['data'] as String;
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'counts playing time, excludes pauses and preserves session identity',
    () async {
      final tracker = create();
      tracker.begin(track);
      tracker.phase(TrackAudioPhase.playing);
      clock.advance(20000);
      tracker.phase(TrackAudioPhase.paused);
      clock.advance(60000);
      await drain();
      expect(sent, isEmpty);
      tracker.phase(TrackAudioPhase.playing);
      clock.advance(10000);
      tracker.checkpoint();
      await drain();
      expect(sent.single['listenedMs'], 30000);
      final path = sent.single['path'];
      clock.advance(10000);
      tracker.checkpoint();
      await drain();
      expect(sent.last['path'], path);
      expect(sent.last['listenedMs'], 40000);
      tracker.dispose();
      await drain();
    },
  );
  test(
    'restores pending events after network failure under the original account',
    () async {
      offline = true;
      final tracker = create();
      tracker.begin(track);
      tracker.phase(TrackAudioPhase.playing);
      clock.advance(30000);
      tracker.finish();
      await drain();
      expect(sent, isEmpty);
      expect((jsonDecode(storage['a']!) as Map).length, 1);
      tracker.dispose();
      await drain();
      offline = false;
      final restored = create();
      restored.checkpoint();
      await drain();
      expect(sent.single['listenedMs'], 30000);
      expect(jsonDecode(storage['a']!), isEmpty);
      restored.dispose();
      await drain();
    },
  );
  test('does not send a session after switching accounts', () async {
    final tracker = create();
    tracker.begin(track);
    tracker.phase(TrackAudioPhase.playing);
    clock.advance(30000);
    auth.user = const AuthUser(uid: 'b');
    tracker.checkpoint();
    await drain();
    expect(sent, isEmpty);
    expect((jsonDecode(storage['a']!) as Map).length, 1);
    expect(storage.containsKey('b'), isFalse);
    tracker.dispose();
    await drain();
  });
  test('reselecting a song creates a new session', () async {
    final tracker = create();
    for (var i = 0; i < 2; i++) {
      tracker.begin(track);
      tracker.phase(TrackAudioPhase.playing);
      clock.advance(30000);
      tracker.finish();
      await drain();
    }
    expect(sent.map((e) => e['path']).toSet().length, 2);
    tracker.dispose();
    await drain();
  });
  test(
    'shutdown during restore preserves previously persisted sessions',
    () async {
      offline = true;
      final first = create();
      first.begin(track);
      first.phase(TrackAudioPhase.playing);
      clock.advance(30000);
      first.finish();
      await drain();
      first.dispose();
      await drain();
      final saved = storage['a'];
      final restored = create();
      restored.dispose();
      await drain();
      expect(storage['a'], saved);
    },
  );
  test('loading and interruption do not inflate listening time', () async {
    final tracker = create();
    tracker.begin(track);
    tracker.phase(TrackAudioPhase.loading);
    clock.advance(60000);
    tracker.phase(TrackAudioPhase.playing);
    clock.advance(15000);
    tracker.phase(TrackAudioPhase.interrupted);
    clock.advance(60000);
    tracker.phase(TrackAudioPhase.playing);
    clock.advance(15000);
    tracker.finish();
    await drain();
    expect(sent.single['listenedMs'], 30000);
    tracker.dispose();
    await drain();
  });
  test('a natural ending below ninety percent is not completed', () async {
    final tracker = create();
    tracker.begin(track);
    tracker.phase(TrackAudioPhase.playing);
    clock.advance(30000);
    tracker.phase(TrackAudioPhase.completed);
    await drain();
    expect(sent.single['completed'], isFalse);
    tracker.dispose();
    await drain();
  });
  test('a full pending queue still drains when connectivity returns', () async {
    offline = true;
    final tracker = create();
    for (var i = 0; i < 100; i++) {
      tracker.begin(track);
      tracker.phase(TrackAudioPhase.playing);
      clock.advance(30000);
      tracker.finish();
      await drain();
    }
    tracker.begin(track);
    tracker.phase(TrackAudioPhase.playing);
    clock.advance(30000);
    tracker.checkpoint();
    await drain();
    expect((jsonDecode(storage['a']!) as Map).length, 100);
    offline = false;
    tracker.checkpoint();
    await drain();
    for (var i = 0; i < 100 && sent.length < 100; i++) {
      await drain();
    }
    await drain();
    expect(sent.length, 100);
    expect(jsonDecode(storage['a']!), isEmpty);
    tracker.dispose();
    await drain();
  });
}
