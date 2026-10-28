import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/demo_controller.dart';
import 'package:mysic/features/playback/data/playback_repository.dart';
import 'package:mysic/features/playback/domain/demo_audio_engine.dart';
import 'package:mysic/features/playback/domain/playback_resolution.dart';
import 'support/fake_auth_repository.dart';

PlaybackResolution direct() => PlaybackResolution.fromJson({
  'mode': 'direct',
  'delivery': 'asset',
  'assetPath': PlaybackResolution.demoAsset,
  'contentType': 'audio/wav',
  'durationSeconds': 8,
});

class FakePlaybackRepository implements PlaybackRepository {
  Completer<PlaybackResolution>? pending;
  bool fail = false;
  @override
  Future<PlaybackResolution> resolve(
    String source,
    String sourceId, {
    CancelToken? cancelToken,
  }) async {
    if (fail) throw const ApiFailure('Unavailable');
    return pending == null ? direct() : pending!.future;
  }
}

class FakeDemoEngine implements DemoAudioEngine {
  final stream = StreamController<DemoState>.broadcast(sync: true);
  String? asset;
  int plays = 0;
  int pauses = 0;
  int disposals = 0;
  @override
  Stream<DemoState> get states => stream.stream;
  @override
  Future<void> load(String assetPath) async {
    asset = assetPath;
  }

  @override
  Future<void> play() async {
    plays++;
    stream.add(const DemoState(DemoPhase.playing));
  }

  @override
  Future<void> pause() async {
    pauses++;
    stream.add(const DemoState(DemoPhase.paused));
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await stream.close();
  }
}

void main() {
  test('solo acepta asset autorizado; rechaza URLs y rutas arbitrarias', () {
    expect(direct().available, isTrue);
    for (final data in [
      {'mode': 'direct', 'delivery': 'asset', 'assetPath': '../secret'},
      {'mode': 'direct', 'url': 'https://example.test/audio.mp3'},
      {'mode': 'embedded', 'url': 'https://example.test'},
    ]) {
      expect(
        () => PlaybackResolution.fromJson(data),
        throwsA(isA<PlaybackFailure>()),
      );
    }
    expect(
      PlaybackResolution.fromJson({
        'mode': 'unavailable',
        'reason': 'No source',
      }).available,
      isFalse,
    );
  });
  test('resolve usa POST con token sin reintentar una escritura 401', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    var attempts = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          attempts++;
          expect(options.method, 'POST');
          expect(options.data, {
            'source': 'demo',
            'sourceId': PlaybackResolution.demoId,
          });
          expect(
            options.headers['Authorization'],
            'Bearer firebase-id-token-for-test',
          );
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: 401),
            ),
          );
        },
      ),
    );
    final api = AuthenticatedApiClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(api.close);
    await expectLater(
      ApiPlaybackRepository(api).resolve('demo', PlaybackResolution.demoId),
      throwsA(isA<AuthFailure>()),
    );
    expect(attempts, 1);
    expect(auth.signOutCount, 1);
  });
  test(
    'carga sin autoplay, reproduce, pausa y dispone el motor una sola vez',
    () async {
      final engine = FakeDemoEngine();
      final controller = DemoController(
        FakePlaybackRepository(),
        engine,
        'a',
        () => 'a',
      );
      await controller.load();
      expect(controller.state.phase, DemoPhase.ready);
      expect(engine.asset, PlaybackResolution.demoAsset);
      expect(engine.plays, 0);
      await controller.play();
      expect(controller.state.phase, DemoPhase.playing);
      await controller.pause();
      expect(controller.state.phase, DemoPhase.paused);
      engine.stream.add(const DemoState(DemoPhase.completed));
      expect(controller.state.phase, DemoPhase.completed);
      await controller.play();
      expect(engine.plays, 2);
      await controller.dispose();
      await controller.dispose();
      expect(engine.disposals, 1);
    },
  );
  test('error de resolución permite recarga sin tocar la sesión', () async {
    final repository = FakePlaybackRepository()..fail = true;
    final engine = FakeDemoEngine();
    final controller = DemoController(repository, engine, 'a', () => 'a');
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.state.phase, DemoPhase.error);
    expect(engine.asset, isNull);
    repository.fail = false;
    await controller.load();
    expect(controller.state.phase, DemoPhase.ready);
    engine.stream.add(const DemoState(DemoPhase.error, message: 'Audio error'));
    engine.stream.add(const DemoState(DemoPhase.paused));
    expect(controller.state.phase, DemoPhase.error);
  });
  test(
    'cambio de cuenta mientras resuelve no carga ni reproduce audio',
    () async {
      var uid = 'a';
      final repository = FakePlaybackRepository()
        ..pending = Completer<PlaybackResolution>();
      final engine = FakeDemoEngine();
      final controller = DemoController(repository, engine, 'a', () => uid);
      final load = controller.load();
      await Future<void>.delayed(Duration.zero);
      uid = 'b';
      repository.pending!.complete(direct());
      await load;
      await controller.play();
      expect(engine.asset, isNull);
      expect(engine.plays, 0);
      await controller.dispose();
    },
  );
  test('salir durante resolución no carga el asset tardío', () async {
    final repository = FakePlaybackRepository()
      ..pending = Completer<PlaybackResolution>();
    final engine = FakeDemoEngine();
    final controller = DemoController(repository, engine, 'a', () => 'a');
    final load = controller.load();
    await Future<void>.delayed(Duration.zero);
    await controller.dispose();
    repository.pending!.complete(direct());
    await load;
    expect(engine.asset, isNull);
    expect(engine.disposals, 1);
  });
}
