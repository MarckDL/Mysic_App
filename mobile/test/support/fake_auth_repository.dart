import 'dart:async';

import 'package:mysic/features/authentication/domain/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user});
  AuthUser? user;
  final _changes = StreamController<AuthUser?>.broadcast();
  int signInCount = 0;
  int signOutCount = 0;
  final refreshes = <bool>[];
  Future<void> Function()? onSignIn;

  @override
  AuthUser? get currentUser => user;
  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield user;
    yield* _changes.stream;
  }

  @override
  Future<void> signInWithGoogle() async {
    signInCount++;
    await onSignIn?.call();
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    user = null;
    _changes.add(null);
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    refreshes.add(forceRefresh);
    return user == null ? null : 'firebase-id-token-for-test';
  }
}
