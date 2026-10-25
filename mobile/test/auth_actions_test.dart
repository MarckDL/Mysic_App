import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';

import 'support/fake_auth_repository.dart';

void main() {
  test('impide dos inicios de sesión simultáneos', () async {
    final completion = Completer<void>();
    final repository = FakeAuthRepository()..onSignIn = () => completion.future;
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    final actions = container.read(authActionsProvider.notifier);
    final first = actions.signIn();
    await actions.signIn();
    expect(repository.signInCount, 1);
    completion.complete();
    await first;
    expect(container.read(authActionsProvider).hasError, isFalse);
  });

  test('cancelar Google vuelve al estado inicial sin error', () async {
    final repository = FakeAuthRepository()
      ..onSignIn = () async {
        throw const AuthFailure('Cancelado', cancelled: true);
      };
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    await container.read(authActionsProvider.notifier).signIn();
    expect(container.read(authActionsProvider).hasError, isFalse);
    expect(container.read(authActionsProvider).isLoading, isFalse);
  });
}
