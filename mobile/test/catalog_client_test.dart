import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/search/data/api_catalog_repository.dart';
import 'support/fake_auth_repository.dart';

Map<String, dynamic> trackData([String id = 'abcdefghijk']) => {
  'id': 'youtube:$id',
  'source': 'youtube',
  'sourceId': id,
  'title': 'Song',
  'artistName': 'Artist',
  'durationSeconds': 123,
  'thumbnailUrl': null,
};

void main() {
  test(
    'busca con token sin exponer SDK y valida el detalle solicitado',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(
              options.headers['Authorization'],
              'Bearer firebase-id-token-for-test',
            );
            expect(options.followRedirects, isFalse);
            if (options.path.endsWith('/search')) {
              expect(options.queryParameters, {'q': 'artist'});
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: options.path.endsWith('/search')
                    ? {
                        'items': [trackData()],
                      }
                    : trackData(),
              ),
            );
          },
        ),
      );
      final api = AuthenticatedApiClient(
        auth,
        baseUrl: 'https://mysic.example',
        dio: dio,
      );
      addTearDown(api.close);
      final repository = ApiCatalogRepository(api);
      final songs = await repository.search('artist');
      expect(songs.single.durationLabel, '2:03');
      expect((await repository.detail(songs.single.id)).title, 'Song');
    },
  );

  test(
    'renueva una sola vez ante 401 y cierra si el segundo token falla',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
      final dio = Dio();
      var attempts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            attempts++;
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
      final api = AuthenticatedApiClient(
        auth,
        baseUrl: 'https://mysic.example',
        dio: dio,
      );
      addTearDown(api.close);
      await expectLater(api.get('/api/v1/search'), throwsA(isA<AuthFailure>()));
      expect(attempts, 2);
      expect(auth.refreshes, [false, true]);
      expect(auth.signOutCount, 1);
    },
  );

  test(
    'el error externo conserva la sesión y no reintenta automáticamente',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
      final dio = Dio();
      var attempts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            attempts++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: options, statusCode: 503),
              ),
            );
          },
        ),
      );
      final api = AuthenticatedApiClient(
        auth,
        baseUrl: 'https://mysic.example',
        dio: dio,
      );
      addTearDown(api.close);
      await expectLater(api.get('/api/v1/search'), throwsA(isA<ApiFailure>()));
      expect(auth.signOutCount, 0);
      expect(attempts, 1);
    },
  );

  test('descarta respuesta tardía de una cuenta anterior', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          auth.user = const AuthUser(uid: 'b');
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'items': [trackData()],
              },
            ),
          );
        },
      ),
    );
    final api = AuthenticatedApiClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(api.close);
    await expectLater(
      ApiCatalogRepository(api).search('artist'),
      throwsA(isA<AuthFailure>()),
    );
    expect(auth.signOutCount, 0);
  });

  test('rechaza respuesta de otra pista e ID arbitrario', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: trackData('12345678901'),
            ),
          );
        },
      ),
    );
    final api = AuthenticatedApiClient(
      auth,
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(api.close);
    final repository = ApiCatalogRepository(api);
    await expectLater(
      repository.detail('youtube:abcdefghijk'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      repository.detail('https://evil.test'),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, 1);
  });
}
