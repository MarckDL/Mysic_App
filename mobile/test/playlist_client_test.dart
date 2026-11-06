import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playlists/data/api_playlist_repository.dart';
import 'package:mysic/features/playlists/domain/playlist.dart';
import 'support/fake_auth_repository.dart';

const playlistId = '11111111-1111-4111-8111-111111111111';
const itemId = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> summaryJson() => {
  'id': playlistId,
  'name': 'Lista',
  'description': null,
  'visibility': 'private',
  'trackCount': 1,
  'createdAt': '2026-11-06T00:00:00.000Z',
  'updatedAt': '2026-11-06T00:00:00.000Z',
};

Map<String, dynamic> detailJson() => {
  ...summaryJson(),
  'ownedByCurrentUser': true,
  'tracks': [
    {
      'id': itemId,
      'position': 0,
      'addedAt': '2026-11-06T00:00:00.000Z',
      'track': {
        'id': 'youtube:abcdefghijk',
        'source': 'youtube',
        'sourceId': 'abcdefghijk',
        'title': 'Song',
        'artistName': 'Artist',
        'durationSeconds': 123,
        'thumbnailUrl': null,
      },
    },
  ],
};

void main() {
  test('ejecuta todo el contrato de playlists con token Firebase', () async {
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
          final data =
              options.path == '/api/v1/playlists' && options.method == 'GET'
              ? {
                  'items': [summaryJson()],
                }
              : options.method == 'DELETE' && !options.path.contains('/tracks/')
              ? {'deleted': true}
              : detailJson();
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
    final repository = ApiPlaylistRepository(api);
    expect((await repository.list()).single.name, 'Lista');
    expect((await repository.detail(playlistId)).tracks.single.position, 0);
    await repository.create(name: 'Nueva');
    await repository.update(
      playlistId,
      name: 'Editada',
      clearDescription: true,
      visibility: PlaylistVisibility.public,
    );
    await repository.addTrack(playlistId, 'youtube:abcdefghijk');
    await repository.removeTrack(playlistId, itemId);
    await repository.reorder(playlistId, [itemId]);
    await repository.delete(playlistId);
    expect(methods, [
      'GET /api/v1/playlists',
      'GET /api/v1/playlists/$playlistId',
      'POST /api/v1/playlists',
      'PATCH /api/v1/playlists/$playlistId',
      'POST /api/v1/playlists/$playlistId/tracks',
      'DELETE /api/v1/playlists/$playlistId/tracks/$itemId',
      'PUT /api/v1/playlists/$playlistId/tracks/order',
      'DELETE /api/v1/playlists/$playlistId',
    ]);
  });

  test('rechaza un orden remoto con huecos', () {
    final invalid = detailJson();
    invalid['tracks'] = <dynamic>[
      ...(invalid['tracks'] as List),
      {
        ...(invalid['tracks'] as List).first as Map<String, dynamic>,
        'id': '33333333-3333-4333-8333-333333333333',
        'position': 2,
      },
    ];
    invalid['trackCount'] = 2;
    expect(() => PlaylistDetail.fromJson(invalid), throwsA(isA<ApiFailure>()));
  });
}
