import 'package:mysic/features/playback/domain/playback_resolution.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
  test('contrato nativo liga ID y ruta sin URL externa ni promesa de seek', () {
    final data = <String, dynamic>{
      'mode': 'direct',
      'delivery': 'api-stream',
      'sourceId': 'aqz-KE-bpKQ',
      'path': '/api/v1/playback/audio/aqz-KE-bpKQ',
      'contentType': 'audio/mp4',
      'seekable': false,
      'availabilityVerified': false,
    };
    expect(PlaybackResolution.fromJson(data).streamPath, data['path']);
    expect(
      () => PlaybackResolution.fromJson({...data, 'path': 'https://evil.test'}),
      throwsA(isA<PlaybackFailure>()),
    );
    expect(
      () => PlaybackResolution.fromJson({...data, 'sourceId': 'abcdefghijk'}),
      throwsA(isA<PlaybackFailure>()),
    );
    expect(
      () => PlaybackResolution.fromJson({...data, 'seekable': true}),
      throwsA(isA<PlaybackFailure>()),
    );
  });

  late FakeAuthRepository auth;
  late FakeTrackAudioEngine engine;
  late TrackPlaybackController controller;
  setUp(() {
    auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    engine = FakeTrackAudioEngine();
    controller = TrackPlaybackController(auth, engine, 'a');
  });
  tearDown(() => controller.dispose());
  test(
    'reproduce ID exacto con token renovado y permite pausa/continuación',
    () async {
      await controller.start('aqz-KE-bpKQ');
      expect(engine.sourceId, 'aqz-KE-bpKQ');
      expect(engine.token, 'firebase-id-token-for-test');
      expect(auth.refreshes, [true]);
      expect(controller.phase, TrackAudioPhase.playing);
      await controller.pause();
      expect(controller.phase, TrackAudioPhase.paused);
      await controller.resume();
      expect(engine.plays, 2);
    },
  );
  test('detener durante carga impide autoplay tardío', () async {
    engine.pendingLoad = Completer<void>();
    final pending = controller.start('aqz-KE-bpKQ');
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    engine.pendingLoad!.complete();
    await pending;
    expect(engine.plays, 0);
    expect(controller.phase, TrackAudioPhase.idle);
  });
  test('logout/cambio de UID descarta la carga anterior', () async {
    engine.pendingLoad = Completer<void>();
    final pending = controller.start('aqz-KE-bpKQ');
    await Future<void>.delayed(Duration.zero);
    auth.user = const AuthUser(uid: 'b');
    engine.pendingLoad!.complete();
    await pending;
    expect(engine.plays, 0);
    await controller.resume();
    expect(engine.plays, 0);
  });
  test('destruir controlador detiene motor y descarta su respuesta', () async {
    engine.pendingLoad = Completer<void>();
    final pending = controller.start('aqz-KE-bpKQ');
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    engine.pendingLoad!.complete();
    await pending;
    expect(engine.disposals, 1);
    expect(engine.plays, 0);
  });
  test(
    'fuente inválida no toca motor ni token y fallo permite reintentar',
    () async {
      await controller.start('https://evil.test');
      expect(engine.sourceId, isNull);
      expect(auth.refreshes, isEmpty);
      engine.fail = true;
      await controller.start('aqz-KE-bpKQ');
      expect(controller.phase, TrackAudioPhase.error);
      engine.fail = false;
      await controller.start('aqz-KE-bpKQ');
      expect(controller.phase, TrackAudioPhase.playing);
    },
  );
}
