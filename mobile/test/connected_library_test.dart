import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';
import 'package:mysic/features/history/data/history_client.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/features/connected_library/application/connected_controller.dart';
import 'package:mysic/features/connected_library/application/connected_host.dart';
import 'package:mysic/features/connected_library/data/connected_client.dart';
import 'package:mysic/features/connected_library/data/link_platform.dart';
import 'package:mysic/features/connected_library/presentation/connected_screen.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

import 'support/fake_connected_library.dart';

void main() {
  late Client api;
  late MemoryPlatform platform;
  late ConnectedController model;
  setUp(() {
    api = Client();
    platform = MemoryPlatform();
    model = ConnectedController('a', api, platform);
  });
  tearDown(() {
    if (model.alive) model.dispose();
  });

  test(
    'reanuda desde almacenamiento privado después de recrear la app y consume el retorno una vez',
    () async {
      await model.start();
      expect(platform.opened, isTrue);
      expect(platform.storage['a'], isNot(contains(ref)));
      model.dispose();
      model = ConnectedController('a', api, platform);
      platform.incoming = (id: id, ref: ref);
      var returns = 0;
      await Future.wait([
        for (var i = 0; i < 2; i++)
          model.sync(browser: true, onReturn: () => returns++),
      ]);
      platform.incoming = (id: id, ref: ref);
      await model.sync(browser: true, onReturn: () => returns++);
      expect(returns, 1);
      expect(api.confirms, [
        {'returnRef': ref},
      ]);
      expect(model.connection?.linked, true);
      expect(platform.storage, isEmpty);
    },
  );
  test(
    'reintenta con la misma clave tras perder la respuesta; permite el regreso manual',
    () async {
      api.failStart = true;
      await model.start();
      expect(model.message, contains('Sin conexión'));
      api.failStart = false;
      await model.start();
      expect(api.keys.length, 2);
      expect(api.keys.toSet().length, 1);
      await model.sync();
      expect(api.confirms, isEmpty);
      expect(model.candidate?.title, 'Canal de prueba');
      await model.confirmCandidate();
      expect(api.confirms, [
        {'channelId': 'ch'},
      ]);
    },
  );
  test(
    'el canal anterior permanece hasta la confirmación expresa del cambio',
    () async {
      api.current = const Connection(
        'linked',
        channel: Channel('old', 'Anterior'),
        generation: 'old',
      );
      api.replace = true;
      await model.sync();
      await model.start();
      platform.incoming = (id: id, ref: ref);
      await model.sync(browser: true);
      expect(model.connection?.channel?.id, 'old');
      expect(model.replaceRequired, true);
      await model.confirmCandidate();
      expect(api.confirms.last, {'channelId': 'ch', 'replace': true});
      expect(model.connection?.channel?.id, 'ch');
    },
  );
  test(
    'cambiar de usuario o recibir otro identificador impide la confirmación automática',
    () async {
      await model.start();
      platform.incoming = (id: id, ref: ref);
      final other = ConnectedController('b', api, platform);
      await other.sync(browser: true);
      other.dispose();
      expect(platform.storage.containsKey('a'), true);
      platform.incoming = (id: 'another-attempt', ref: ref);
      var navigated = false;
      await model.sync(browser: true, onReturn: () => navigated = true);
      expect(navigated, false);
      expect(api.confirms, isEmpty);
    },
  );
  test(
    'consentimiento denegado, expiración y cancelación limpian el intento',
    () async {
      await model.start();
      api.status = 'denied';
      await model.sync();
      expect(model.message, contains('canceló'));
      expect(platform.storage, isEmpty);
      await model.sync(browser: true);
      expect(model.message, contains('canceló'));
      model.dispose();
      await platform.save('a', PendingLink(id, DateTime(2000), id: id));
      model = ConnectedController('a', api, platform);
      await model.sync();
      expect(model.message, contains('venció'));
      await model.start();
      await model.cancel();
      expect(api.cancels, [id]);
      expect(platform.storage, isEmpty);
    },
  );
  test(
    'oculta el canal anterior si se corta la red al consultar el vínculo confirmado',
    () async {
      api.current = previous;
      await model.sync();
      await model.start(restart: true);
      await model.sync();
      expect(model.replaceRequired, true);
      api.failConnection = true;
      await model.confirmCandidate();
      expect(api.confirms.single, {'channelId': 'ch', 'replace': true});
      expect(model.connection, isNull);
      expect(model.pending, isNull);
      expect(model.message, contains('Sin conexión'));
      api.failConnection = false;
      await model.sync();
      expect(model.connection, linked);
      expect(api.confirms.length, 1);
    },
  );
  test(
    'salir durante el inicio impide abrir el navegador con una respuesta tardía',
    () async {
      api.wait = Completer<void>();
      final work = model.start();
      while (api.keys.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      model.dispose();
      api.wait!.complete();
      await work;
      expect(platform.opened, false);
      expect((await platform.load('a'))?.id, isNull);
    },
  );
  test(
    'acepta solo el retorno del dominio configurado, un intento único y la ruta exacta',
    () {
      final valid = 'https://$host$returnPath#attemptId=$id&returnRef=$ref';
      expect(parseLinkReturn(valid, host), (id: id, ref: ref));
      for (final wrong in [
        valid.replaceFirst(host, 'other.test'),
        valid.replaceFirst('https', 'http'),
        valid.replaceFirst('#', '?'),
        '$valid&attemptId=$id',
        valid.replaceFirst(returnPath, '/other'),
        valid.replaceFirst(ref, 'short'),
      ]) {
        expect(parseLinkReturn(wrong, host), isNull);
      }
      expect(
        api.launchUri('https://other.test$youtubeRoot/browser/start?ref=$ref'),
        isNull,
      );
      expect(
        api.launchUri('https://$host$youtubeRoot/browser/start?ref=$ref'),
        isNotNull,
      );
    },
  );
  test('solo abre la URL oficial de un video disponible de la misma fila', () {
    const video = 'abcdefghijk',
        url = 'https://www.youtube.com/watch?v=abcdefghijk';
    LibraryRow entry(String status, String open) => LibraryRow.item({
      'playlistItemId': 'one',
      'availability': status,
      'videoId': video,
      'openUrl': open,
    });
    expect(entry('available', url).open?.toString(), url);
    expect(
      entry('available', 'https://other.test/watch?v=$video').open,
      isNull,
    );
    expect(entry('unavailable', url).open, isNull);
    expect(
      entry('available', url).musicUri(samplePlaylist)?.toString(),
      'https://music.youtube.com/watch?v=$video&list=$samplePlaylist',
    );
    expect(entry('available', url).musicUri('fake&v=malicious'), isNull);
    expect(
      entry(
        'available',
        'https://other.test/watch?v=$video',
      ).musicUri(samplePlaylist),
      isNull,
    );
    expect(entry('unavailable', url).musicUri(samplePlaylist), isNull);
    expect(youtubeMusicPlaylistUri('https://fake.test'), isNull);
  });
  testWidgets(
    'desde Biblioteca autoriza el canal, vuelve a su gestión y no consulta videos',
    (tester) async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            verifiedSessionProvider.overrideWith(
              (ref) async => const MysicProfile(
                id: 'id-a',
                firebaseUid: 'a',
                displayName: 'Ana',
              ),
            ),
            recentListeningProvider.overrideWith((ref, uid) async => []),
            trackAudioEngineFactoryProvider.overrideWithValue(
              FakeTrackAudioEngine.new,
            ),
            youtubePilotProvider.overrideWithValue(true),
            connectedControllerProvider('a').overrideWithValue(model),
          ],
          child: const MysicApp(firebaseReady: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biblioteca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular YouTube'));
      await tester.pumpAndSettle();
      expect(platform.uris.single.host, host);
      expect(find.text('Esperando autorización'), findsOneWidget);
      platform.incoming = (id: id, ref: ref);
      platform.notifyReturn!();
      await tester.pumpAndSettle();
      expect(find.text('Canal vinculado'), findsOneWidget);
      expect(api.cursors, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Favoritos'), findsOneWidget);
    },
  );
  testWidgets(
    'el canal vinculado no lista videos ni abre un reproductor externo',
    (tester) async {
      api.current = linked;
      await model.sync();
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectedScope(
            controller: model,
            child: const ConnectedScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Canal vinculado'), findsOneWidget);
      expect(find.text('Lista privada'), findsNothing);
      expect(find.byTooltip('Abrir YouTube Music'), findsNothing);
      expect(find.text('Abrir playlist en YouTube Music'), findsNothing);
      expect(platform.uris, isEmpty);
      expect(api.cursors, isEmpty);
      await model.unlink();
      await tester.pumpAndSettle();
      expect(find.text('Canal vinculado'), findsNothing);
    },
  );
  testWidgets('muestra la identidad del nuevo vínculo y descarta la anterior', (
    tester,
  ) async {
    api.current = previous;
    await model.sync();
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectedScope(controller: model, child: const ConnectedScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(previous.channel!.title), findsOneWidget);
    await model.start(restart: true);
    await model.sync();
    await model.confirmCandidate();
    await tester.pumpAndSettle();
    expect(find.text(previous.channel!.title), findsNothing);
    expect(find.text(linked.channel!.title), findsOneWidget);
    expect(api.playlists, isEmpty);
  });
  testWidgets('reintenta la desvinculación sin cerrar la sesión de Mysic', (
    tester,
  ) async {
    api.current = linked;
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          verifiedSessionProvider.overrideWith(
            (ref) async => const MysicProfile(
              id: 'id-a',
              firebaseUid: 'a',
              displayName: 'Ana',
            ),
          ),
          recentListeningProvider.overrideWith((ref, uid) async => []),
          trackAudioEngineFactoryProvider.overrideWithValue(
            FakeTrackAudioEngine.new,
          ),
          youtubePilotProvider.overrideWithValue(true),
          connectedControllerProvider('a').overrideWithValue(model),
        ],
        child: const MysicApp(firebaseReady: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca de YouTube'));
    await tester.pumpAndSettle();
    expect(find.text('Canal vinculado'), findsOneWidget);
    await tester.tap(find.byTooltip('Opciones del vínculo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desvincular YouTube'));
    await tester.pumpAndSettle();
    api.loseUnlinkResponse = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Desvincular'));
    await tester.pumpAndSettle();
    expect(find.text('Lista privada'), findsNothing);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    await model.sync(browser: true);
    await tester.pumpAndSettle();
    expect(find.text('Lista privada'), findsNothing);
    api.loseUnlinkResponse = false;
    await tester.tap(find.text('Reintentar desvinculación'));
    await tester.pumpAndSettle();
    expect(api.unlinks, 2);
    expect(find.text('Vincular YouTube'), findsOneWidget);
    expect(auth.currentUser?.uid, 'a');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Favoritos'), findsOneWidget);
  });
}
