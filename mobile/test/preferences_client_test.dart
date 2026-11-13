import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/favorites/data/api_favorite_repository.dart';
import 'package:mysic/features/ratings/data/api_rating_repository.dart';
import 'package:mysic/features/ratings/domain/track_interactions.dart';
import 'support/fake_auth_repository.dart';

const trackId = 'youtube:abcdefghijk';
const encodedTrackId = 'youtube%3Aabcdefghijk';

void main() {
  test('ejecuta el contrato autenticado de favoritos y ratings', () async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final dio = Dio();
    final methods = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(
            options.headers['Authorization'],
            'Bearer firebase-id-token-for-test',
          );
          methods.add('${options.method} ${options.path}');
          final data = switch ((options.method, options.path)) {
            ('GET', '/api/v1/favorites') => {
              'items': [
                {
                  'createdAt': '2026-11-12T18:00:00.000Z',
                  'track': {
                    'id': trackId,
                    'source': 'youtube',
                    'sourceId': 'abcdefghijk',
                    'title': 'Song',
                    'artistName': 'Artist',
                    'durationSeconds': 123,
                    'thumbnailUrl': null,
                  },
                },
              ],
            },
            ('PUT', '/api/v1/favorites/$encodedTrackId') => {
              'isFavorite': true,
            },
            ('DELETE', '/api/v1/favorites/$encodedTrackId') => {
              'isFavorite': false,
            },
            ('GET', '/api/v1/tracks/$encodedTrackId/interactions') => {
              'isFavorite': true,
              'myRating': null,
              'ratingAverage': null,
              'ratingCount': 0,
            },
            ('PUT', '/api/v1/ratings/$encodedTrackId') => {
              'myRating': 4,
              'ratingAverage': 4.5,
              'ratingCount': 2,
            },
            _ => throw StateError('Solicitud inesperada'),
          };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
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
    final favorites = ApiFavoriteRepository(api);
    final ratings = ApiRatingRepository(api);
    expect((await favorites.list()).single.track.title, 'Song');
    await favorites.add(trackId);
    await favorites.remove(trackId);
    final status = await ratings.interactions(trackId);
    expect(status.isFavorite, isTrue);
    expect(status.ratingCount, 0);
    final rated = await ratings.rate(trackId, 4, isFavorite: true);
    expect(rated.myRating, 4);
    expect(rated.ratingAverage, 4.5);
    expect(rated.isFavorite, isTrue);
    expect(methods, [
      'GET /api/v1/favorites',
      'PUT /api/v1/favorites/$encodedTrackId',
      'DELETE /api/v1/favorites/$encodedTrackId',
      'GET /api/v1/tracks/$encodedTrackId/interactions',
      'PUT /api/v1/ratings/$encodedTrackId',
    ]);
  });

  test('rechaza agregados incoherentes', () {
    expect(
      () => TrackInteractions.fromJson(const {
        'isFavorite': false,
        'myRating': null,
        'ratingAverage': 4,
        'ratingCount': 0,
      }),
      throwsA(isA<ApiFailure>()),
    );
  });
}
