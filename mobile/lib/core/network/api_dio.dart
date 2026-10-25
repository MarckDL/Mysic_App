import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/authentication/domain/auth_repository.dart';

Dio configureApiDio(String baseUrl, [Dio? dio]) {
  final uri = Uri.parse(baseUrl);
  final local =
      kDebugMode && ['10.0.2.2', '127.0.0.1', 'localhost'].contains(uri.host);
  if (uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.scheme != 'https' && !(uri.scheme == 'http' && local))) {
    throw const AuthFailure('La dirección del servidor no es válida.');
  }
  final client = dio ?? Dio();
  client.options = BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    followRedirects: false,
  );
  return client;
}
