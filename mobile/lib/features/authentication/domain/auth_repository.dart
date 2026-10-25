class AuthUser {
  const AuthUser({required this.uid, this.displayName});
  final String uid;
  final String? displayName;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
}

abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> authStateChanges();
  Future<void> signInWithGoogle();
  Future<void> signOut();
  Future<String?> getIdToken({bool forceRefresh = false});
}
