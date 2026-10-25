import 'package:dio/dio.dart';

import '../../features/authentication/domain/auth_repository.dart';
import 'api_dio.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

class AuthenticatedApiClient {
  AuthenticatedApiClient(this._auth, {required String baseUrl, Dio? dio})
    : _dio = configureApiDio(baseUrl, dio);
  final AuthRepository _auth;
  final Dio _dio;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthFailure('Inicia sesión con Google.');
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _auth.getIdToken(forceRefresh: attempt == 1);
        if (_auth.currentUser?.uid != uid) {
          throw const AuthFailure('La cuenta cambió.');
        }
        if (token == null || token.isEmpty) {
          await _auth.signOut();
          throw const AuthFailure('Tu sesión terminó.');
        }
        final response = await _dio.get<Map<String, dynamic>>(
          path,
          queryParameters: query,
          cancelToken: cancelToken,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (_auth.currentUser?.uid != uid) {
          throw const AuthFailure('La cuenta cambió.');
        }
        if (response.data == null) {
          throw const ApiFailure('Respuesta de catálogo inválida.');
        }
        return response.data!;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) rethrow;
        if (_auth.currentUser?.uid != uid) {
          throw const AuthFailure('La cuenta cambió.');
        }
        final status = error.response?.statusCode;
        if (status == 401 && attempt == 0) continue;
        if (status == 401 || status == 403) {
          await _auth.signOut();
          throw const AuthFailure('Tu sesión terminó. Inicia sesión de nuevo.');
        }
        final message = switch (status) {
          404 => 'Esta pista no está disponible.',
          429 => 'Espera un minuto antes de buscar de nuevo.',
          504 => 'El catálogo tardó demasiado en responder.',
          _ => 'No se pudo consultar el catálogo. Inténtalo de nuevo.',
        };
        throw ApiFailure(message, statusCode: status);
      }
    }
    throw const AuthFailure('No se pudo verificar la sesión.');
  }

  void close() => _dio.close(force: true);
}
