import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
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
    'reproduce ID exacto sin pedir ningún token y permite pausa/continuación',
    () async {
      await controller.start('aqz-KE-bpKQ');
      expect(engine.sourceId, 'aqz-KE-bpKQ');
      expect(engine.token, 'device');
      expect(auth.refreshes, isEmpty);
      expect(controller.phase, TrackAudioPhase.playing);
      await controller.pause();
      expect(controller.phase, TrackAudioPhase.paused);
      await controller.resume();
      expect(engine.plays, 2);
    },
  );
  test('repetir canción se activa y desactiva desde la notificación', () async {
    await controller.start('aqz-KE-bpKQ');
    expect(controller.repeat, PlaybackRepeat.off);
    controller.toggleRepeatOne();
    expect(controller.repeat, PlaybackRepeat.one);
    controller.toggleRepeatOne();
    expect(controller.repeat, PlaybackRepeat.off);
    // Si estaba en repetir todo, el botón lo pasa a repetir una.
    controller.cycleRepeat();
    expect(controller.repeat, PlaybackRepeat.all);
    controller.toggleRepeatOne();
    expect(controller.repeat, PlaybackRepeat.one);
  });
  test('seek usa la duración confirmada y limita el destino', () async {
    engine.duration = const Duration(seconds: 200);
    await controller.start('aqz-KE-bpKQ');
    await controller.seek(const Duration(seconds: 90));
    await controller.seek(const Duration(seconds: 250));
    expect(engine.seeks, [
      const Duration(seconds: 90),
      const Duration(seconds: 200),
    ]);
    expect(controller.position, const Duration(seconds: 200));
  });
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
