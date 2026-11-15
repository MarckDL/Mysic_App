import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/authentication/domain/auth_repository.dart';
import 'api_dio.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

class AuthenticatedApiClient {
  AuthenticatedApiClient(
    this._auth, {
    required String baseUrl,
    Dio? dio,
    this.keepSessionOnForbidden = false,
  }) : _dio = configureApiDio(baseUrl, dio);
  final AuthRepository _auth;
  final Dio _dio;
  final bool keepSessionOnForbidden;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _request('GET', path, query: query, cancelToken: cancelToken);

  Future<Map<String, dynamic>> post(
    String path, {
    required Map<String, dynamic> body,
    CancelToken? cancelToken,
  }) => _request('POST', path, body: body, cancelToken: cancelToken);

  Future<Map<String, dynamic>> patch(
    String path, {
    required Map<String, dynamic> body,
    CancelToken? cancelToken,
  }) => _request('PATCH', path, body: body, cancelToken: cancelToken);

  Future<Map<String, dynamic>> put(
    String path, {
    required Map<String, dynamic> body,
    CancelToken? cancelToken,
  }) => _request('PUT', path, body: body, cancelToken: cancelToken);

  Future<Map<String, dynamic>> delete(
    String path, {
    CancelToken? cancelToken,
  }) => _request('DELETE', path, cancelToken: cancelToken);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthFailure('Inicia sesión con Google.');
    for (var attempt = 0; attempt < (method == 'GET' ? 2 : 1); attempt++) {
      try {
        final token = await _auth.getIdToken(forceRefresh: attempt == 1);
        if (_auth.currentUser?.uid != uid) {
          throw const AuthFailure('La cuenta cambió.');
        }
        if (token == null || token.isEmpty) {
          await _auth.signOut();
          throw const AuthFailure('Tu sesión terminó.');
        }
        final response = await _dio.request<Map<String, dynamic>>(
          path,
          queryParameters: query,
          data: body,
          cancelToken: cancelToken,
          options: Options(
            method: method,
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        if (_auth.currentUser?.uid != uid) {
          throw const AuthFailure('La cuenta cambió.');
        }
        if (response.statusCode == 204) return const {};
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
        debugPrint(
          'api_request_failed method=$method type=${error.type.name} '
          'status=$status',
        );
        if (method == 'GET' && status == 401 && attempt == 0) continue;
        final responseData = error.response?.data;
        final errorDetails = responseData is Map ? responseData['error'] : null;
        final googleRequired =
            errorDetails is Map && errorDetails['code'] == 'GOOGLE_REQUIRED';
        if (status == 401 ||
            (status == 403 && (!keepSessionOnForbidden || googleRequired))) {
          await _auth.signOut();
          throw const AuthFailure('Tu sesión terminó. Inicia sesión de nuevo.');
        }
        final message = switch (status) {
          403 => 'No tienes permiso para realizar esta acción.',
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
