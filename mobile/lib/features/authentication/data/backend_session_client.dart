import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/auth_repository.dart';

class BackendSessionClient {
  BackendSessionClient(this._auth, {required String baseUrl, Dio? dio})
      : _dio = dio ?? Dio() {
    final uri = Uri.parse(baseUrl);
    final localDevelopment =
        kDebugMode && ['10.0.2.2', '127.0.0.1', 'localhost'].contains(uri.host);
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && localDevelopment))) {
      throw const AuthFailure('La dirección del servidor no es válida.');
    }
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
    );
  }

  final AuthRepository _auth;
  final Dio _dio;

  Future<void> verifySession() async {
    final expectedUid = _auth.currentUser?.uid;
    if (expectedUid == null) {
      throw const AuthFailure('Inicia sesión con Google.');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_auth.currentUser?.uid != expectedUid) {
        throw const AuthFailure(
            'La cuenta cambió. Verifica tu sesión de nuevo.');
      }
      try {
        final token = await _auth.getIdToken(forceRefresh: attempt == 1);
        if (_auth.currentUser?.uid != expectedUid) {
          throw const AuthFailure(
              'La cuenta cambió. Verifica tu sesión de nuevo.');
        }
        if (token == null || token.isEmpty) {
          await _auth.signOut();
          throw const AuthFailure('Tu sesión terminó. Inicia sesión de nuevo.');
        }
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/auth/session',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (response.data?['firebaseUid'] != expectedUid ||
            response.data?['provider'] != 'google.com' ||
            _auth.currentUser?.uid != expectedUid) {
          throw const AuthFailure('No se pudo confirmar tu sesión.');
        }
        return;
      } on DioException catch (error) {
        if (_auth.currentUser?.uid != expectedUid) {
          throw const AuthFailure(
              'La cuenta cambió. Verifica tu sesión de nuevo.');
        }
        final status = error.response?.statusCode;
        if (status == 401 && attempt == 0) continue;
        if (status == 401 || status == 403) {
          await _auth.signOut();
          throw const AuthFailure('Tu sesión terminó. Inicia sesión de nuevo.');
        }
        throw const AuthFailure(
            'No se pudo conectar con Mysic. Inténtalo de nuevo.');
      }
    }
  }

  void close() => _dio.close(force: true);
}
