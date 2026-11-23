import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

/// Un motor que sabe pausar con desvanecido, y apunta cómo se le pidió.
class _FadingEngine extends FakeTrackAudioEngine implements TrackAudioFade {
  final fades = <Duration>[];
  int instantPauses = 0;

  @override
  Future<void> pauseFading(Duration duration) async {
    fades.add(duration);
    events.add(TrackAudioPhase.paused);
  }

  @override
  Future<void> pause() async {
    instantPauses++;
    await super.pause();
  }
}

void main() {
  late _FadingEngine engine;
  late TrackPlaybackController controller;

  setUp(() {
    engine = _FadingEngine();
    controller = TrackPlaybackController(
      FakeAuthRepository(user: const AuthUser(uid: 'a')),
      engine,
      'a',
    );
  });
  tearDown(() => controller.dispose());

  test('pausar una canción que suena la desvanece medio segundo', () async {
    await controller.start('aqz-KE-bpKQ');
    expect(controller.phase, TrackAudioPhase.playing);

    await controller.pause();

    expect(engine.fades, [const Duration(milliseconds: 500)]);
    expect(engine.instantPauses, 0);
    expect(controller.phase, TrackAudioPhase.paused);
  });

  test('reanudar sigue funcionando después del desvanecido', () async {
    await controller.start('aqz-KE-bpKQ');
    await controller.pause();
    await controller.resume();

    expect(engine.plays, 2);
    expect(controller.phase, TrackAudioPhase.playing);
  });

  test('sin estar sonando, pausar es inmediato y no desvanece', () async {
    await controller.start('aqz-KE-bpKQ');
    await controller.pause();
    engine.fades.clear();

    // Ya en pausa: otra pausa no vuelve a desvanecer.
    await controller.pause();

    expect(engine.fades, isEmpty);
  });
}
