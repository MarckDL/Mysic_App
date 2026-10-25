import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';

import 'support/fake_auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';

void main() {
  testWidgets(
      'sin configuración Firebase no permite entrar con identidad ficticia',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MysicApp()));
    expect(find.text('Mysic'), findsOneWidget);
    expect(find.textContaining('todavía no está disponible'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsNothing);
  });

  testWidgets('sin sesión muestra Google y permite iniciar el flujo',
      (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: const MysicApp(firebaseReady: true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsNothing);
    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();
    expect(repository.signInCount, 1);
  });

  testWidgets('una cuenta Firebase no entra si el backend rechaza su sesión',
      (tester) async {
    final repository = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        verifiedSessionProvider.overrideWith((ref) async {
          throw const AuthFailure('Sesión rechazada');
        }),
      ],
      child: const MysicApp(firebaseReady: true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos verificar tu sesión.'), findsOneWidget);
    expect(find.text('Tu sesión con Google está verificada.'), findsNothing);
    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('la sesión verificada muestra inicio y logout', (tester) async {
    final repository =
        FakeAuthRepository(user: const AuthUser(uid: 'a', displayName: 'Ana'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        verifiedSessionProvider.overrideWith((ref) async => const MysicProfile(
            id: '00000000-0000-4000-8000-000000000001',
            firebaseUid: 'a',
            displayName: 'Ana',
            email: 'ana@example.test')),
      ],
      child: const MysicApp(firebaseReady: true),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido, Ana'), findsOneWidget);
    expect(find.text('ana@example.test'), findsOneWidget);
    expect(find.text('Tu perfil está guardado en Mysic.'), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(repository.signOutCount, 1);
    expect(find.text('Bienvenido, Ana'), findsNothing);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });
}
