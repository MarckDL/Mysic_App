import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/data/mysic_audio_handler.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

const a = CatalogTrack(
  id: 'youtube:abcdefghijk',
  title: 'Primera',
  artistName: 'Artista A',
  durationSeconds: 180,
);
const b = CatalogTrack(
  id: 'youtube:12345678901',
  title: 'Segunda',
  artistName: 'Artista B',
);
const c = CatalogTrack(
  id: 'youtube:ABCDEFGHIJK',
  title: 'Tercera',
  artistName: 'Artista C',
);
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
    'cola conserva orden y metadatos; anterior/siguiente reproducen ID exacto',
    () async {
      await controller.playQueue([a, b, c], initialIndex: 1);
      expect(controller.current!.title, 'Segunda');
      expect(engine.sourceId, '12345678901');
      expect(engine.prefetched, [c.id.substring(8)]);
      await controller.next();
      expect(controller.current!.id, c.id);
      expect(controller.hasNext, false);
      await controller.previous();
      expect(controller.current!.id, b.id);
      controller.remove(0);
      expect(controller.index, 0);
      expect(controller.current!.id, b.id);
      expect(controller.queue.map((track) => track.id), [b.id, c.id]);
    },
  );
  test('fin avanza una vez y termina sin bucle al final de la cola', () async {
    await controller.playQueue([a, b]);
    engine.events.add(TrackAudioPhase.completed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.current!.id, b.id);
    expect(engine.plays, 2);
    engine.events.add(TrackAudioPhase.completed);
    await Future<void>.delayed(Duration.zero);
    expect(engine.plays, 2);
    expect(controller.phase, TrackAudioPhase.completed);
  });
  test('selección B cancela A aunque A termine de cargar más tarde', () async {
    final pendingA = Completer<void>();
    engine.pendingLoad = pendingA;
    final first = controller.playTrack(a);
    await Future<void>.delayed(Duration.zero);
    final pendingB = Completer<void>();
    engine.pendingLoad = pendingB;
    final second = controller.playTrack(b);
    await Future<void>.delayed(Duration.zero);
    pendingA.complete();
    await first;
    expect(engine.plays, 0);
    pendingB.complete();
    await second;
    expect(controller.current!.id, b.id);
    expect(engine.plays, 1);
  });
  test(
    'fallo se queda en la pista seleccionada y permite salto manual',
    () async {
      engine.fail = true;
      await controller.playQueue([a, b]);
      expect(controller.phase, TrackAudioPhase.error);
      expect(controller.index, 0);
      expect(engine.plays, 0);
      engine.fail = false;
      await controller.next();
      expect(controller.current!.id, b.id);
      expect(engine.plays, 1);
    },
  );
  test(
    'cola acotada y sin duplicados al añadir; vaciar cancela reproducción',
    () async {
      controller.enqueue(a);
      controller.enqueue(a);
      expect(controller.queue.length, 1);
      for (var i = 0; i < 150; i++) {
        controller.enqueue(
          CatalogTrack(
            id: 'youtube:${i.toString().padLeft(11, '0')}',
            title: 'T$i',
            artistName: 'A',
          ),
        );
      }
      expect(controller.queue.length, 100);
      await controller.jump(0);
      await controller.clear();
      expect(controller.current, isNull);
      expect(controller.queue, isEmpty);
      expect(controller.phase, TrackAudioPhase.idle);
    },
  );
  test('interrupción durante carga cancela autoplay', () async {
    engine.pendingLoad = Completer<void>();
    final pending = controller.playTrack(a);
    await Future<void>.delayed(Duration.zero);
    engine.events.add(TrackAudioPhase.interrupted);
    await Future<void>.delayed(Duration.zero);
    engine.pendingLoad!.complete();
    await pending;
    expect(engine.plays, 0);
    expect(controller.phase, TrackAudioPhase.idle);
  });
  test(
    'notificación comparte cola/controles y no expone tokens; logout la limpia',
    () async {
      final handler = MysicAudioHandler();
      handler.bind(controller);
      await controller.playQueue([a, b]);
      expect(handler.mediaItem.value!.title, a.title);
      expect(handler.queue.value.map((item) => item.id), [a.id, b.id]);
      expect(
        handler.playbackState.value.systemActions,
        contains(MediaAction.seek),
      );
      await handler.seek(const Duration(seconds: 90));
      expect(engine.seeks, [const Duration(seconds: 90)]);
      await handler.pause();
      expect(controller.phase, TrackAudioPhase.paused);
      await handler.play();
      await handler.skipToNext();
      expect(controller.current!.id, b.id);
      await auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(controller.queue, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.playing, false);
      final plays = engine.plays;
      await handler.play();
      expect(engine.plays, plays);
      handler.unbind(controller);
    },
  );
  test(
    'desvincular una sesión antigua no borra controles de la nueva',
    () async {
      final handler = MysicAudioHandler();
      handler.bind(controller);
      await controller.playTrack(a);
      final otherAuth = FakeAuthRepository(user: const AuthUser(uid: 'b'));
      final otherEngine = FakeTrackAudioEngine();
      final other = TrackPlaybackController(otherAuth, otherEngine, 'b');
      try {
        handler.bind(other);
        await other.playTrack(b);
        handler.unbind(controller);
        expect(handler.mediaItem.value!.id, b.id);
        await handler.pause();
        expect(other.phase, TrackAudioPhase.paused);
        expect(controller.phase, TrackAudioPhase.playing);
        handler.unbind(other);
        expect(handler.queue.value, isEmpty);
        expect(handler.mediaItem.value, isNull);
      } finally {
        other.dispose();
      }
    },
  );
  test(
    'duración real del motor prevalece sobre la metadata para el progreso',
    () async {
      engine.duration = const Duration(seconds: 200);
      await controller.playTrack(a);
      expect(controller.duration, const Duration(seconds: 200));
    },
  );
}
