import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/presentation/playback_progress.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
  setUpAll(() => PlaybackProgress.animationsEnabled = false);
  testWidgets('la barra permite adelantar y retroceder con un gesto', (
    tester,
  ) async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final engine = FakeTrackAudioEngine()
      ..duration = const Duration(seconds: 200);
    final controller = TrackPlaybackController(auth, engine, 'a');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, child) =>
                PlaybackProgress(controller: controller),
          ),
        ),
      ),
    );
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    await controller.playTrack(TrackPlaybackController.demoTrack);
    await tester.pump();
    final rect = tester.getRect(slider);
    Offset at(double fraction) =>
        Offset(rect.left + rect.width * fraction, rect.center.dy);
    await tester.dragFrom(at(.1), at(.8) - at(.1));
    await tester.pumpAndSettle();
    expect(engine.seeks, hasLength(1));
    expect(engine.seeks.first.inSeconds, greaterThan(140));
    await tester.dragFrom(at(.8), at(.2) - at(.8));
    await tester.pumpAndSettle();
    expect(engine.seeks, hasLength(2));
    expect(engine.seeks.last.inSeconds, lessThan(60));
    expect(controller.position, engine.seeks.last);
  });
}
