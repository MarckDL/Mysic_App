import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/favorites/data/api_favorite_repository.dart';
import 'package:mysic/features/ratings/data/api_rating_repository.dart';

import 'support/fake_auth_repository.dart';

const trackId = 'youtube:abcdefghijk';
const trackPath = 'youtube/abcdefghijk';

Map<String, dynamic> trackJson() => {
  'id': trackId,
  'source': 'youtube',
  'sourceId': 'abcdefghijk',
  'title': 'Song',
  'artistName': 'Artist',
  'durationSeconds': 123,
  'thumbnailUrl': null,
};

void main() {
  test('favoritos usa endpoints autenticados e idempotentes', () async {
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(
              options.headers['Authorization'],
              'Bearer firebase-id-token-for-test',
            );
            requests.add('${options.method} ${options.path}');
            final data = switch ((options.method, options.path)) {
              ('GET', '/api/v1/favorites') => {
                'items': [
                  {
                    'track': trackJson(),
                    'createdAt': '2026-11-12T00:00:00.000Z',
                  },
                ],
              },
              ('GET', '/api/v1/favorites/$trackPath') => {'favorite': true},
              ('PUT', '/api/v1/favorites/$trackPath') => {
                'track': trackJson(),
                'createdAt': '2026-11-12T00:00:00.000Z',
              },
              _ => {'deleted': true},
            };
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
          },
        ),
      );
    final api = AuthenticatedApiClient(
      FakeAuthRepository(user: const AuthUser(uid: 'a')),
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(api.close);
    final repository = ApiFavoriteRepository(api);

    expect((await repository.list()).single.track.id, trackId);
    expect(await repository.status(trackId), isTrue);
    expect((await repository.add(trackId)).track.title, 'Song');
    expect(await repository.remove(trackId), isTrue);
    expect(requests, [
      'GET /api/v1/favorites',
      'GET /api/v1/favorites/$trackPath',
      'PUT /api/v1/favorites/$trackPath',
      'DELETE /api/v1/favorites/$trackPath',
    ]);
  });

  test('calificaciones consulta, actualiza y elimina la propia nota', () async {
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add('${options.method} ${options.path}');
            if (options.method == 'PUT') {
              expect(options.data, {'score': 4});
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'myScore': options.method == 'DELETE' ? null : 4,
                  'averageScore': 4.5,
                  'ratingCount': 2,
                },
              ),
            );
          },
        ),
      );
    final api = AuthenticatedApiClient(
      FakeAuthRepository(user: const AuthUser(uid: 'a')),
      baseUrl: 'https://mysic.example',
      dio: dio,
    );
    addTearDown(api.close);
    final repository = ApiRatingRepository(api);

    expect((await repository.get(trackId)).myScore, 4);
    expect((await repository.set(trackId, 4)).averageScore, 4.5);
    expect((await repository.remove(trackId)).myScore, isNull);
    expect(requests, [
      'GET /api/v1/ratings/$trackPath',
      'PUT /api/v1/ratings/$trackPath',
      'DELETE /api/v1/ratings/$trackPath',
    ]);
  });

  test('rechaza identificadores inválidos', () async {
    final api = AuthenticatedApiClient(
      FakeAuthRepository(user: const AuthUser(uid: 'a')),
      baseUrl: 'https://mysic.example',
    );
    addTearDown(api.close);
    final favorites = ApiFavoriteRepository(api);
    final ratings = ApiRatingRepository(api);
    await expectLater(
      favorites.status('spotify:bad'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(ratings.get('youtube:short'), throwsA(isA<ApiFailure>()));
  });
}
