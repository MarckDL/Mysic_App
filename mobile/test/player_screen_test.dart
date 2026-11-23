import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/lyrics/data/lyrics_repository.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/features/playback/application/track_playback_controller.dart';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';
import 'package:mysic/features/playback/presentation/playback_progress.dart';
import 'package:mysic/features/playback/presentation/player_screen.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

const _first = CatalogTrack(
  id: 'youtube:aaaaaaaaaaa',
  title: 'Around the World',
  artistName: 'Daft Punk',
  durationSeconds: 200,
  musicAccountTrack: true,
);
const _second = CatalogTrack(
  id: 'youtube:bbbbbbbbbbb',
  title: 'One More Time',
  artistName: 'Daft Punk',
  durationSeconds: 200,
  musicAccountTrack: true,
);

(TrackPlaybackController, FakeTrackAudioEngine) _controller() {
  final engine = FakeTrackAudioEngine()
    ..duration = const Duration(seconds: 200);
  final controller = TrackPlaybackController(
    FakeAuthRepository(user: const AuthUser(uid: 'a')),
    engine,
    'a',
  );
  addTearDown(controller.dispose);
  return (controller, engine);
}

Future<TrackPlaybackController> _pump(WidgetTester tester) async {
  final (controller, _) = _controller();
  await controller.playQueue(const [_first, _second]);
  // Alto de teléfono: la página cabe sin encoger.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trackPlaybackControllerProvider.overrideWithValue(controller),
        likedTracksProvider.overrideWithValue(null),
        // Sin fuentes de letra: la prueba no sale a la red.
        lyricsRepositoryProvider.overrideWithValue(LyricsRepository(const [])),
      ],
      child: const MaterialApp(home: PlayerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUpAll(() {
    PlaybackProgress.animationsEnabled = false;
    NowPlayingBars.animationsEnabled = false;
  });

  testWidgets('la página lleva la portada, el título y sus dos filas', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Reproduciendo'), findsOneWidget);
    expect(find.text('Around the World'), findsOneWidget);
    expect(find.text('Daft Punk'), findsOneWidget);
    // Tres píldoras de transporte.
    for (final tip in ['Anterior', 'Siguiente']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    // Los cuadrados del pie y el menú.
    for (final tip in [
      'Guardar en playlist',
      'Repetir desactivado',
      'Letra',
      'Aleatorio',
      'Cola',
      'Opciones de la canción',
      'Salida de audio',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cola y Letra son vistas de la misma página', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Cola'));
    await tester.pumpAndSettle();
    // La cola ocupa el sitio de la portada; los controles siguen ahí.
    expect(find.text('Reproduciendo'), findsNothing);
    expect(find.text('Reproduciendo ahora'), findsOneWidget);
    expect(find.text('One More Time'), findsOneWidget);
    expect(find.byTooltip('Siguiente'), findsOneWidget);

    // Tocar el cuadrado de la vista abierta vuelve a la portada.
    await tester.tap(find.byTooltip('Cola'));
    await tester.pumpAndSettle();
    expect(find.text('Reproduciendo'), findsOneWidget);

    await tester.tap(find.byTooltip('Letra'));
    // El esqueleto de la letra anima mientras carga: no se espera a que pare.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reproduciendo'), findsNothing);
    expect(find.text('Letra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en Cola las píldoras se recogen solas y un toque las devuelve', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Cola'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Siguiente'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Siguiente'), findsNothing);
    // La barra y los cuadrados no se van.
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byTooltip('Aleatorio'), findsOneWidget);

    await tester.tap(find.byTooltip('Aleatorio'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Siguiente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el menú inicia el temporizador de apagado', (tester) async {
    final controller = await _pump(tester);
    await tester.tap(find.byTooltip('Opciones de la canción'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Temporizador de apagado'));
    await tester.pumpAndSettle();
    expect(find.text('Fin de la canción'), findsOneWidget);
    await tester.tap(find.text('15 min'));
    await tester.pumpAndSettle();
    expect(controller.sleepActive, isTrue);
    expect(controller.sleepMinutesLeft, 15);
    controller.cancelSleepTimer();
    expect(controller.sleepActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('«al acabar la canción» no pasa a la siguiente', () async {
    final (controller, engine) = _controller();
    await controller.playQueue(const [_first, _second]);
    controller.sleepAfterTrack();
    expect(controller.sleepAtTrackEnd, isTrue);
    engine.events.add(TrackAudioPhase.completed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.index, 0);
    expect(controller.sleepActive, isFalse);

    // Sin temporizador, el final de la pista sí avanza.
    await controller.resume();
    engine.events.add(TrackAudioPhase.completed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.index, 1);
  });
}
