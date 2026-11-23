import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_music.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';

class FakeEditedProfile extends EditedProfile {
  final changes = <String?>[];

  @override
  Future<void> updateNickname(String uid, String? nickname) async {
    changes.add(nickname);
    state = MysicProfile(
      id: '00000000-0000-4000-8000-000000000001',
      uid: uid,
      displayName: 'Ana',
      nickname: nickname,
    );
  }
}

void main() {
  testWidgets('sin sesión muestra YouTube Music y permite iniciar el flujo', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MysicApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión con YouTube Music'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsNothing);
    await tester.tap(find.text('Iniciar sesión con YouTube Music'));
    await tester.pumpAndSettle();
    expect(repository.signInCount, 1);
  });

  testWidgets('una cuenta no entra si YouTube Music rechaza su sesión', (
    tester,
  ) async {
    final repository = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          verifiedSessionProvider.overrideWith((ref) async {
            throw const AuthFailure('Sesión rechazada');
          }),
        ],
        child: const MysicApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pudimos verificar tu sesión.'), findsOneWidget);
    expect(find.text('Tu sesión con Google está verificada.'), findsNothing);
    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('la sesión verificada muestra inicio y logout', (tester) async {
    final repository = FakeAuthRepository(
      user: const AuthUser(uid: 'a', displayName: 'Ana'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          fakeMusicOverride,
          verifiedSessionProvider.overrideWith(
            (ref) async => const MysicProfile(
              id: '00000000-0000-4000-8000-000000000001',
              uid: 'a',
              displayName: 'Ana',
              email: 'ana@example.test',
            ),
          ),
        ],
        child: const MysicApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('ana@example.test'), findsOneWidget);
    expect(find.text('Moderar comentarios'), findsNothing);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(repository.signOutCount, 1);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Iniciar sesión con YouTube Music'), findsOneWidget);
  });

  testWidgets('editar o borrar el apodo actualiza el saludo sin relogin', (
    tester,
  ) async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final editedProfile = FakeEditedProfile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          fakeMusicOverride,
          verifiedSessionProvider.overrideWith(
            (ref) async => const MysicProfile(
              id: '00000000-0000-4000-8000-000000000001',
              uid: 'a',
              displayName: 'Ana',
            ),
          ),
          editedProfileProvider.overrideWith(() => editedProfile),
        ],
        child: const MysicApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar apodo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'x' * 25);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Usa hasta 24 caracteres.'), findsOneWidget);
    expect(editedProfile.changes, isEmpty);
    await tester.enterText(find.byType(TextFormField), '  Melo  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Melo'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Abrir cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar apodo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(editedProfile.changes, ['Melo', null]);
  });
}
