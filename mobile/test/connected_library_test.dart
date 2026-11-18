import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';
import 'package:mysic/features/history/data/history_client.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/connected_library/application/connected_controller.dart';
import 'package:mysic/features/connected_library/application/connected_host.dart';
import 'package:mysic/features/connected_library/data/connected_client.dart';
import 'package:mysic/features/connected_library/data/link_platform.dart';
import 'package:mysic/features/connected_library/presentation/connected_screen.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

const host = 'pilot.example.test';
const id = '01234567-0123-4123-8123-0123456789ab';
final ref = 'r' * 43;
const linked = Connection(
  'linked',
  channel: Channel('ch', 'Canal de prueba'),
  generation: 'g1',
);
final future = DateTime.now().add(const Duration(minutes: 9));

class MemoryPlatform extends LinkPlatform {
  final storage = <String, String>{};
  LinkReturn? incoming;
  VoidCallback? notifyReturn;
  @override
  void onReturn(void Function()? callback) {
    notifyReturn = callback;
  }

  bool opened = false;
  final uris = <Uri>[];
  @override
  Future<PendingLink?> load(String uid) async =>
      PendingLink.decode(storage[uid]);
  @override
  Future<void> save(String uid, PendingLink? pending) async {
    if (pending == null) {
      storage.remove(uid);
    } else {
      storage[uid] = pending.encode();
    }
  }

  @override
  Future<LinkReturn?> takeReturn() async {
    final value = incoming;
    incoming = null;
    return value;
  }

  @override
  Future<bool> open(Uri uri) async {
    uris.add(uri);
    opened = true;
    return true;
  }
}

class Client extends ConnectedClient {
  Client()
    : super(
        AuthenticatedApiClient(FakeAuthRepository(), baseUrl: 'https://$host'),
        Uri.https(host),
      );
  Connection current = const Connection('unlinked');
  final keys = <String>[], cancels = <String>[], confirms = <Json>[];
  final cursors = <String?>[];
  String status = 'awaiting_confirmation';
  String? reason;
  bool failStart = false, replace = false, throttle = false;
  Completer<void>? wait;
  Attempt snapshot({bool launch = false}) => Attempt({
    'attemptId': id,
    'status': status,
    'expiresAt': future.toIso8601String(),
    'reason': reason,
    if (status == 'awaiting_confirmation')
      'channel': {'id': 'ch', 'title': 'Canal de prueba'},
    if (launch) 'launchUrl': 'https://$host$youtubeRoot/browser/start?ref=$ref',
  });
  @override
  Future<Connection> connection(CancelToken cancel) async => current;
  @override
  Future<Attempt> start(String key, bool force, CancelToken cancel) async {
    keys.add(key);
    await wait?.future;
    if (failStart) throw const ApiFailure('offline');
    return snapshot(launch: true);
  }

  @override
  Future<Attempt> attempt(String id, CancelToken cancel) async => snapshot();
  @override
  Future<void> confirm(String id, Json data, CancelToken cancel) async {
    confirms.add(data);
    if (replace && data['replace'] != true) {
      throw const ApiFailure(
        'replacement',
        statusCode: 409,
        code: 'CONFIRM_REPLACEMENT',
      );
    }
    current = linked;
  }

  @override
  Future<void> cancelAttempt(String id, CancelToken cancel) async {
    cancels.add(id);
  }

  @override
  Future<void> unlink(CancelToken cancel) async {
    current = const Connection('unlinked');
  }

  @override
  Future<LibraryPage> page(
    String? playlist,
    String? cursor,
    CancelToken cancel,
  ) async {
    cursors.add(cursor);
    const a = LibraryRow(
      'a',
      'Lista privada',
      subtitle: 'Privada · 11 elementos',
    );
    if (cursor == null) return (items: [a], next: 'page2');
    if (throttle) {
      throw const ApiFailure(
        'quota',
        statusCode: 429,
        code: 'TOO_MANY_REQUESTS',
        retryAfter: Duration(seconds: 2),
      );
    }
    return (items: [a, const LibraryRow('b', 'Lista pública')], next: null);
  }
}

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
  });
  testWidgets(
    'desde Biblioteca abre el navegador, vuelve al canal y carga la primera página',
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
      expect(find.text('Lista privada'), findsOneWidget);
      expect(api.cursors, [null]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Favoritos'), findsOneWidget);
    },
  );
  testWidgets(
    'conserva la página durante el límite de cuota, reintenta y elimina duplicados',
    (tester) async {
      api.current = linked;
      api.throttle = true;
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
      expect(find.text('Privada · 11 elementos'), findsOneWidget);
      await tester.tap(find.text('Cargar más'));
      await tester.pumpAndSettle();
      expect(find.text('Lista privada'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Reintentar'))
            .onPressed,
        isNull,
      );
      api.throttle = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(api.cursors, [null, 'page2', 'page2']);
      expect(find.text('Lista pública'), findsOneWidget);
      expect(find.text('Lista privada'), findsOneWidget);
      expect(find.text('Cargar más'), findsNothing);
      await model.unlink();
      await tester.pumpAndSettle();
      expect(find.text('Vincular YouTube'), findsOneWidget);
      expect(find.text('Lista privada'), findsNothing);
    },
  );
}
