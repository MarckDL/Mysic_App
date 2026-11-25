import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/data/profile_cache.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_music.dart';

const _ana = MysicProfile(
  id: '00000000-0000-4000-8000-000000000001',
  uid: 'a',
  displayName: 'Ana',
);

class _MemoryCache extends ProfileCache {
  _MemoryCache([this.stored]);

  MysicProfile? stored;
  int clears = 0;

  @override
  Future<MysicProfile?> read(String uid) async =>
      stored?.uid == uid ? stored : null;

  @override
  Future<void> write(MysicProfile profile) async => stored = profile;

  @override
  Future<void> clear() async {
    clears++;
    stored = null;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    _MemoryCache cache,
    Future<MysicProfile> Function() verify, {
    String uid = 'a',
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: AuthUser(uid: uid)),
        ),
        fakeMusicOverride,
        profileCacheProvider.overrideWithValue(cache),
        verifiedSessionProvider.overrideWith((ref) => verify()),
      ],
      child: const MysicApp(),
    ),
  );

  test('el perfil sobrevive a guardarse y leerse', () {
    const profile = MysicProfile(
      id: '00000000-0000-4000-8000-000000000001',
      uid: 'a',
      displayName: 'Ana',
      email: 'ana@example.test',
      nickname: 'Anita',
      canModerateComments: true,
    );
    final copy = MysicProfile.fromJson(profile.toJson());
    expect(copy.id, profile.id);
    expect(copy.uid, 'a');
    expect(copy.email, 'ana@example.test');
    expect(copy.preferredName, 'Anita');
    expect(copy.canModerateComments, isTrue);
  });

  testWidgets('con perfil guardado la app abre sin esperar al servidor', (
    tester,
  ) async {
    final pending = Completer<MysicProfile>();
    await mount(tester, _MemoryCache(_ana), () => pending.future);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    // Al llegar la verificación, el perfil del servidor sustituye al guardado.
    pending.complete(
      const MysicProfile(
        id: '00000000-0000-4000-8000-000000000001',
        uid: 'a',
        displayName: 'Ana María',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Ana María'), findsOneWidget);
  });

  testWidgets('sin perfil guardado se espera a la verificación', (
    tester,
  ) async {
    final pending = Completer<MysicProfile>();
    final cache = _MemoryCache();
    await mount(tester, cache, () => pending.future);
    await tester.pump();
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);

    pending.complete(_ana);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    // La verificación correcta deja el perfil para el próximo arranque.
    expect(cache.stored, same(_ana));
  });

  testWidgets('el perfil guardado de otra cuenta no abre la app', (
    tester,
  ) async {
    final pending = Completer<MysicProfile>();
    await mount(tester, _MemoryCache(_ana), () => pending.future, uid: 'b');
    await tester.pump();
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('un rechazo del servidor cierra la app y borra el perfil', (
    tester,
  ) async {
    final cache = _MemoryCache(_ana);
    await mount(
      tester,
      cache,
      () async => throw const AuthFailure('Sesión rechazada'),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pudimos verificar tu sesión.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(cache.stored, isNull);
  });

  testWidgets('si el servidor no responde, la app sigue con el perfil', (
    tester,
  ) async {
    final cache = _MemoryCache(_ana);
    await mount(
      tester,
      cache,
      () async => throw const AuthFailure('Sin conexión', unreachable: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(cache.stored, same(_ana));
  });

  testWidgets('sin perfil guardado, un servidor caído deja entrar igualmente', (
    tester,
  ) async {
    // Una cuenta recién iniciada no tiene perfil guardado: si YouTube Music no
    // responde a la comprobación, la app no se queda atascada sin poder entrar.
    final cache = _MemoryCache();
    await mount(
      tester,
      cache,
      () async => throw const AuthFailure('Sin conexión', unreachable: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pudimos verificar tu sesión.'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    // El perfil provisional no se guarda como si estuviera verificado.
    expect(cache.stored, isNull);
  });
}
