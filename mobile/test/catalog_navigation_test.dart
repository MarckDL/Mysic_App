import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';
import 'package:mysic/features/history/data/history_client.dart';
import 'package:mysic/features/home/presentation/home_screen.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeAuthRepository auth,
    Future<List<ListeningEntry>> Function(String uid) recent,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          verifiedSessionProvider.overrideWith((ref) async {
            final uid = ref.watch(authStateProvider).requireValue!.uid;
            return MysicProfile(
              id: 'test-$uid',
              firebaseUid: uid,
              displayName: uid,
              canModerateComments: uid == 'Ana',
            );
          }),
          recentListeningProvider.overrideWith((ref, uid) => recent(uid)),
          trackAudioEngineFactoryProvider.overrideWithValue(
            FakeTrackAudioEngine.new,
          ),
        ],
        child: const MysicApp(firebaseReady: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('recupera actividad y separa estado privado por cuenta', (
    tester,
  ) async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'Ana'));
    var offline = true;
    await mount(tester, auth, (uid) async {
      if (uid != 'Ana') return [];
      if (offline) throw StateError('offline');
      return [
        (
          track: const CatalogTrack(
            id: 'youtube:abcdefghijk',
            title: 'Actividad de Ana',
            artistName: 'Artista',
          ),
          startedAt: DateTime(2026, 11, 14),
        ),
      ];
    });
    expect(
      find.text('No se pudieron cargar tus escuchas recientes.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Actividad de Ana'), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsOneWidget);

    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Moderar comentarios'), findsOneWidget);

    auth.changeUser(const AuthUser(uid: 'Luis'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido, Luis'), findsOneWidget);
    expect(find.text('Actividad de Ana', skipOffstage: false), findsNothing);
    expect(find.text('Explorar catálogo'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    router.push('/moderation/comments');
    await tester.pumpAndSettle();
    expect(find.text('Cuenta'), findsOneWidget);
    expect(find.text('Moderar comentarios'), findsNothing);
    expect(find.text('Moderación de comentarios'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('navega con texto al 200 % en modo ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final auth = FakeAuthRepository(user: const AuthUser(uid: 'Luis'));
      await mount(tester, auth, (uid) async => []);
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).brightness,
        brightness,
      );
      for (final label in ['Inicio', 'Explorar', 'Biblioteca']) {
        final destination = find.text(label);
        expect(destination.hitTestable(), findsOneWidget);
        await tester.tap(destination);
        await tester.pumpAndSettle();
      }
      expect(find.text('Playlists').hitTestable(), findsOneWidget);
      expect(find.text('Favoritos').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Descargas'), 100);
      expect(find.text('Descargas').hitTestable(), findsOneWidget);
      expect(find.text('Próximamente'), findsOneWidget);
      await tester.tap(find.byTooltip('Abrir cuenta'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cerrar sesión'), 100);
      await tester.pumpAndSettle();
      expect(find.text('Cerrar sesión').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
