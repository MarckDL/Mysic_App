class AuthUser {
  const AuthUser({required this.uid, this.displayName});
  final String uid;
  final String? displayName;
}

class AuthFailure implements Exception {
  const AuthFailure(
    this.message, {
    this.cancelled = false,
    this.unreachable = false,
  });
  final String message;
  final bool cancelled;

  /// El servidor no respondió o falló por su lado: la sesión no fue
  /// rechazada, solo no se pudo comprobar.
  final bool unreachable;
}

abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> authStateChanges();
  Future<void> signIn();
  Future<void> signOut();
  Future<String?> getIdToken({bool forceRefresh = false});
}
