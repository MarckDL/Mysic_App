import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/auth/firebase_client_config.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._google);
  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _initialization;

  AuthUser? _mapUser(User? user) => user == null
      ? null
      : AuthUser(uid: user.uid, displayName: user.displayName);

  @override
  AuthUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => _auth.idTokenChanges().map(_mapUser);

  @override
  Future<void> signInWithGoogle() async {
    try {
      await (_initialization ??= _google.initialize(
        serverClientId: FirebaseClientConfig.googleServerClientId,
      ));
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure(
          'Google no pudo completar el inicio de sesión.',
        );
      }
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure('Inicio de sesión cancelado.', cancelled: true);
      }
      throw const AuthFailure(
        'No se pudo iniciar sesión con Google. Inténtalo de nuevo.',
      );
    } on FirebaseAuthException {
      throw const AuthFailure(
        'No se pudo completar el inicio de sesión. Revisa tu conexión.',
      );
    }
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      return await _auth.currentUser?.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (error) {
      if ([
        'user-disabled',
        'user-token-expired',
        'invalid-user-token',
        'user-not-found',
      ].contains(error.code)) {
        await signOut();
        throw const AuthFailure('Tu sesión terminó. Inicia sesión de nuevo.');
      }
      throw const AuthFailure(
        'No se pudo renovar tu sesión. Revisa tu conexión.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    // Firebase se cierra primero aunque falle la limpieza de sesión de Google.
    await _auth.signOut();
    if (_initialization != null) {
      await _google.signOut();
    }
  }
}
