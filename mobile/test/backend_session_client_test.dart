import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/data/backend_session_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';

import 'support/fake_auth_repository.dart';

void main() {
  test('envía un Firebase ID token y confirma el UID con el backend', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(
            options.headers['Authorization'],
            'Bearer firebase-id-token-for-test',
          );
          expect(options.path, '/api/v1/auth/session');
          expect(options.queryParameters, isEmpty);
          expect(options.followRedirects, isFalse);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'firebaseUid': 'a',
                'provider': 'google.com',
              },
            ),
          );
        },
      ),
    );
    final client = BackendSessionClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(client.close);
    await client.verifySession();
    expect(auth.refreshes, [false]);
  });

  test(
    'ante 401 renueva una vez y cierra la sesión si vuelve a fallar',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: options, statusCode: 401),
              ),
            );
          },
        ),
      );
      final client = BackendSessionClient(
        auth,
        baseUrl: 'https://mysic.example',
        dio: dio,
      );
      addTearDown(client.close);
      await expectLater(client.verifySession(), throwsA(isA<AuthFailure>()));
      expect(requests, 2);
      expect(auth.refreshes, [false, true]);
      expect(auth.signOutCount, 1);
    },
  );

  test('no acepta la identidad de otra cuenta', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'firebaseUid': 'b',
                'provider': 'google.com',
              },
            ),
          );
        },
      ),
    );
    final client = BackendSessionClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(client.close);
    await expectLater(client.verifySession(), throwsA(isA<AuthFailure>()));
  });

  test('sync envía solo el token y obtiene el perfil persistido', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    final paths = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          paths.add(options.path);
          expect(
            options.headers['Authorization'],
            'Bearer firebase-id-token-for-test',
          );
          expect(options.data, isNull);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('/session')
                  ? <String, dynamic>{
                      'firebaseUid': 'a',
                      'provider': 'google.com',
                    }
                  : <String, dynamic>{
                      'id': '00000000-0000-4000-8000-000000000001',
                      'firebaseUid': 'a',
                      'displayName': 'Ana',
                      'email': 'ana@example.test',
                    },
            ),
          );
        },
      ),
    );
    final client = BackendSessionClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(client.close);
    final profile = await client.syncProfile();
    expect(profile.displayName, 'Ana');
    expect(profile.id, isNot('a'));
    expect(paths, ['/api/v1/auth/session', '/api/v1/auth/sync']);
  });

  test('un fallo PostgreSQL permite reintentar sin cerrar sesión', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    var writes = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/session')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'firebaseUid': 'a',
                  'provider': 'google.com',
                },
              ),
            );
          } else {
            writes++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: options, statusCode: 503),
              ),
            );
          }
        },
      ),
    );
    final client = BackendSessionClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(client.close);
    await expectLater(client.syncProfile(), throwsA(isA<AuthFailure>()));
    expect(auth.signOutCount, 0);
    expect(writes, 1);
  });

  test('descarta un perfil tardío después de cambiar de cuenta', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/sync')) {
            auth.user = const AuthUser(uid: 'b');
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('/session')
                  ? <String, dynamic>{
                      'firebaseUid': 'a',
                      'provider': 'google.com',
                    }
                  : <String, dynamic>{
                      'id': '00000000-0000-4000-8000-000000000001',
                      'firebaseUid': 'a',
                      'displayName': 'Ana',
                    },
            ),
          );
        },
      ),
    );
    final client = BackendSessionClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(client.close);
    await expectLater(client.syncProfile(), throwsA(isA<AuthFailure>()));
    expect(auth.signOutCount, 0);
  });

  test('rechaza HTTP hacia un servidor remoto', () {
    expect(
      () => BackendSessionClient(
        FakeAuthRepository(),
        baseUrl: 'http://mysic.example',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });
}
