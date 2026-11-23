import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

String _id(int n) => 'youtube:${n.toString().padLeft(11, '0')}';

CatalogTrack _t(int n, {bool account = true}) => CatalogTrack(
  id: _id(n),
  title: 'T$n',
  artistName: 'A',
  durationSeconds: 200,
  musicAccountTrack: account,
);

void main() {
  late FakeAuthRepository auth;
  late FakeTrackAudioEngine engine;
  late TrackPlaybackController controller;
  final seeds = <String>[];
  final cursors = <String?>[];
  late List<RadioBatch> batches;
  Completer<void>? gate;

  Future<RadioBatch> radio(String id, {String? cursor}) async {
    seeds.add(id);
    cursors.add(cursor);
    await gate?.future;
    return batches.isEmpty ? const RadioBatch([], null) : batches.removeAt(0);
  }

  setUp(() {
    seeds.clear();
    cursors.clear();
    gate = null;
    batches = [];
    auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    engine = FakeTrackAudioEngine();
    controller = TrackPlaybackController(auth, engine, 'a', radio: radio);
  });
  tearDown(() => controller.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'una canción suelta pide la radio y la deja detrás como autoplay',
    () async {
      batches = [
        RadioBatch([_t(2), _t(3), _t(4)], 'tok1'),
      ];
      await controller.playQueue([_t(1)]);
      await settle();
      expect(seeds, [_id(1).substring(8)]);
      expect(cursors, [null]);
      expect(controller.queue.map((t) => t.title), ['T1', 'T2', 'T3', 'T4']);
      expect(controller.isAutoplayTrack(_t(1)), isFalse);
      expect(controller.isAutoplayTrack(_t(2)), isTrue);
      // La siguiente ya está adelantada y la pista sigue siendo la elegida.
      expect(controller.current!.title, 'T1');
      expect(controller.hasNext, isTrue);
    },
  );

  test(
    'la radio no repite lo que ya está en la cola y respeta el lote',
    () async {
      batches = [
        RadioBatch([
          _t(1), // la propia canción
          _t(2),
          _t(2), // repetida dentro del lote
          for (var i = 3; i < 40; i++) _t(i),
        ], null),
      ];
      await controller.playQueue([_t(1)]);
      await settle();
      expect(
        controller.queue.length,
        1 + TrackPlaybackController.autoplayBatch,
      );
      expect(
        controller.queue.map((t) => t.id).toSet().length,
        controller.queue.length,
      );
    },
  );

  test(
    'al acercarse el final pide más con el cursor; con muchas por delante no',
    () async {
      batches = [
        RadioBatch([for (var i = 2; i < 12; i++) _t(i)], 'tok1'),
        RadioBatch([for (var i = 12; i < 20; i++) _t(i)], null),
      ];
      await controller.playQueue([_t(1)]);
      await settle();
      expect(seeds, hasLength(1));
      // Aún quedan 10 por delante: no se pide más.
      await controller.jump(1);
      await settle();
      expect(seeds, hasLength(1));
      // Con ≤ 2 por delante sí, siguiendo el cursor.
      await controller.jump(8);
      await settle();
      expect(seeds, hasLength(2));
      expect(cursors.last, 'tok1');
      expect(controller.queue.last.title, 'T19');
    },
  );

  test(
    'con autoplay apagado no pide nada y al apagarlo se quita lo propuesto',
    () async {
      batches = [
        RadioBatch([_t(2), _t(3)], 't'),
      ];
      controller.setAutoplay(false);
      await controller.playQueue([_t(1)]);
      await settle();
      expect(seeds, isEmpty);
      controller.setAutoplay(true);
      await settle();
      expect(controller.queue, hasLength(3));
      controller.setAutoplay(false);
      expect(controller.queue.map((t) => t.title), ['T1']);
      expect(controller.isAutoplayTrack(_t(2)), isFalse);
    },
  );

  test('una cola nueva descarta la respuesta tardía de la anterior', () async {
    gate = Completer<void>();
    batches = [
      RadioBatch([_t(10), _t(11)], null),
    ];
    await controller.playQueue([_t(1)]);
    await settle();
    // Antes de que conteste la radio de T1 se reemplaza la cola.
    final late = gate!;
    gate = null;
    await controller.playQueue([_t(5), _t(6), _t(7), _t(8)]);
    late.complete();
    await settle();
    expect(controller.queue.map((t) => t.title), ['T5', 'T6', 'T7', 'T8']);
  });

  test(
    'añadir a la cola va delante del autoplay y siguiente justo tras la actual',
    () async {
      batches = [
        RadioBatch([_t(2), _t(3)], null),
      ];
      await controller.playQueue([_t(1)]);
      await settle();
      expect(controller.queueConnected([_t(7)], next: false), isTrue);
      // Detrás de la actual y delante de lo de la radio.
      expect(controller.queue.map((t) => t.title), ['T1', 'T7', 'T2', 'T3']);
      expect(controller.isAutoplayTrack(_t(7)), isFalse);
      expect(controller.queueConnected([_t(8)], next: true), isTrue);
      expect(controller.queue.map((t) => t.title), [
        'T1',
        'T8',
        'T7',
        'T2',
        'T3',
      ]);
      // Una propuesta de la radio que el usuario añade pasa a ser suya.
      expect(controller.queueConnected([_t(3)], next: false), isTrue);
      expect(controller.isAutoplayTrack(_t(3)), isFalse);
      expect(controller.queue.map((t) => t.title), [
        'T1',
        'T8',
        'T7',
        'T3',
        'T2',
      ]);
    },
  );

  test(
    'mover una pista reordena sin interrumpir el audio y el puntero la sigue',
    () async {
      controller.setAutoplay(false);
      await controller.playQueue([_t(1), _t(2), _t(3), _t(4)], initialIndex: 1);
      final plays = engine.plays;
      controller.move(3, 2);
      expect(controller.queue.map((t) => t.title), ['T1', 'T2', 'T4', 'T3']);
      expect(controller.current!.title, 'T2');
      // Mover la actual: el puntero la acompaña.
      controller.move(1, 3);
      expect(controller.queue.map((t) => t.title), ['T1', 'T4', 'T3', 'T2']);
      expect(controller.current!.title, 'T2');
      expect(controller.index, 3);
      expect(engine.plays, plays);
      // Movimientos inválidos no hacen nada.
      controller.move(9, 0);
      controller.move(0, 0);
      expect(controller.queue.map((t) => t.title), ['T1', 'T4', 'T3', 'T2']);
    },
  );

  test('vaciar siguientes deja la actual y lo ya oído', () async {
    controller.setAutoplay(false);
    await controller.playQueue([_t(1), _t(2), _t(3), _t(4)], initialIndex: 1);
    controller.clearUpcoming();
    expect(controller.queue.map((t) => t.title), ['T1', 'T2']);
    expect(controller.current!.title, 'T2');
    expect(controller.hasNext, isFalse);
  });

  test(
    'anterior reinicia la pista si lleva más de 3 s y solo si no, retrocede',
    () async {
      controller.setAutoplay(false);
      await controller.playQueue([_t(1), _t(2)], initialIndex: 1);
      engine.positionEvents.add(const Duration(seconds: 10));
      await controller.previous();
      expect(controller.current!.title, 'T2');
      expect(controller.index, 1);
      engine.positionEvents.add(const Duration(seconds: 1));
      await controller.previous();
      expect(controller.current!.title, 'T1');
    },
  );

  test(
    'aleatorio solo baraja lo que viene después de la pista actual',
    () async {
      controller.setAutoplay(false);
      final tracks = [for (var i = 1; i <= 30; i++) _t(i)];
      await controller.playQueue(tracks, initialIndex: 10);
      controller.toggleShuffle();
      expect(controller.queue.sublist(0, 11), tracks.sublist(0, 11));
      expect(controller.queue.sublist(11).toSet(), tracks.sublist(11).toSet());
      expect(controller.current!.title, 'T11');
      controller.toggleShuffle();
      expect(controller.queue, tracks);
    },
  );

  test(
    'la cola entera de una lista larga entra sin partirla en trozos de 100',
    () async {
      controller.setAutoplay(false);
      final tracks = [for (var i = 1; i <= 250; i++) _t(i)];
      await controller.playQueue(tracks, initialIndex: 180);
      expect(controller.queue, hasLength(250));
      expect(controller.index, 180);
      expect(controller.upcomingCount, 69);
    },
  );

  test('lo ya oído que pasa de 200 se recorta por detrás', () async {
    controller.setAutoplay(false);
    final tracks = [for (var i = 1; i <= 260; i++) _t(i)];
    await controller.playQueue(tracks, initialIndex: 250);
    expect(controller.index, TrackPlaybackController.maxHistory);
    expect(controller.current!.title, 'T251');
    expect(controller.queue.first.title, 'T51');
  });

  test(
    'si la última pista termina antes de que conteste la radio, espera y sigue',
    () async {
      gate = Completer<void>();
      batches = [
        RadioBatch([_t(2), _t(3)], null),
      ];
      await controller.playQueue([_t(1)]);
      await settle();
      engine.events.add(TrackAudioPhase.completed);
      await settle();
      // Aún no hay siguiente: la cola espera a la radio.
      expect(controller.current!.title, 'T1');
      gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.current!.title, 'T2');
    },
  );

  test(
    'sin radio o con una cola que no es de la cuenta, nada se añade solo',
    () async {
      final bare = TrackPlaybackController(auth, FakeTrackAudioEngine(), 'a');
      addTearDown(bare.dispose);
      await bare.playQueue([_t(1)]);
      await settle();
      expect(bare.queue, hasLength(1));
      expect(bare.hasRadio, isFalse);
      batches = [
        RadioBatch([_t(2)], null),
      ];
      await controller.playQueue([_t(1, account: false)]);
      await settle();
      expect(seeds, isEmpty);
    },
  );

  test('con repetir activado no hay autoplay', () async {
    batches = [
      RadioBatch([_t(2)], null),
    ];
    controller.cycleRepeat();
    await controller.playQueue([_t(1)]);
    await settle();
    expect(seeds, isEmpty);
  });

  test(
    'deja preparadas la siguiente (precarga), las 3 siguientes y la anterior',
    () async {
      controller.setAutoplay(false);
      final tracks = [for (var i = 1; i <= 8; i++) _t(i)];
      String sid(int n) => _id(n).substring(8);
      await controller.playQueue(tracks, initialIndex: 3);
      // La siguiente con prioridad y alrededor, en segundo plano.
      expect(engine.prefetched.last, sid(5));
      expect(engine.warmed.last, [sid(5), sid(6), sid(7), sid(3)]);
      // Al avanzar se preparan las nuevas vecinas.
      await controller.next();
      expect(engine.prefetched.last, sid(6));
      expect(engine.warmed.last, [sid(6), sid(7), sid(8), sid(4)]);
      // Reordenar o quitar vuelve a calcular lo adyacente.
      // T7 pasa justo delante de la actual (T5): ahora es su anterior.
      controller.move(6, 4);
      expect(engine.warmed.last, [sid(6), sid(8), sid(7)]);
      controller.remove(4);
      expect(engine.warmed.last.first, sid(6));
      // Al principio no hay anterior; al final no hay siguientes.
      await controller.jump(0);
      expect(engine.warmed.last.contains(sid(1)), isFalse);
    },
  );

  test(
    'lo propio del dispositivo o sin URL que resolver no se calienta',
    () async {
      controller.setAutoplay(false);
      final own = CatalogTrack(
        id: _id(9),
        title: 'Archivo',
        artistName: 'A',
        deviceAudio: Uri.file('/privado/a.media'),
      );
      await controller.playQueue([_t(1), own, _t(3)]);
      expect(engine.warmed.last, [_id(3).substring(8)]);
    },
  );
  test('un fallo de la radio no rompe la cola', () async {
    final failing = TrackPlaybackController(
      auth,
      FakeTrackAudioEngine(),
      'a',
      radio: (id, {cursor}) => throw StateError('sin red'),
    );
    addTearDown(failing.dispose);
    await failing.playQueue([_t(1)]);
    await settle();
    expect(failing.queue, hasLength(1));
    expect(failing.loadingAutoplay, isFalse);
  });
}
