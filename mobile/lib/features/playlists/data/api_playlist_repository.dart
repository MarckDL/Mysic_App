import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/playlist.dart';
import '../domain/playlist_repository.dart';

class ApiPlaylistRepository implements PlaylistRepository {
  ApiPlaylistRepository(this._api);
  final AuthenticatedApiClient _api;

  @override
  Future<List<PlaylistSummary>> list({CancelToken? cancelToken}) async {
    final data = await _api.get('/api/v1/playlists', cancelToken: cancelToken);
    final items = data['items'];
    if (items is! List) {
      throw const ApiFailure('Respuesta de playlists inválida.');
    }
    return items
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const ApiFailure('Respuesta de playlists inválida.');
          }
          return PlaylistSummary.fromJson(value);
        })
        .toList(growable: false);
  }

  @override
  Future<PlaylistDetail> detail(String id, {CancelToken? cancelToken}) async =>
      PlaylistDetail.fromJson(
        await _api.get(
          '/api/v1/playlists/${Uri.encodeComponent(id)}',
          cancelToken: cancelToken,
        ),
      );

  @override
  Future<PlaylistDetail> create({
    required String name,
    String? description,
    PlaylistVisibility visibility = PlaylistVisibility.private,
  }) async => PlaylistDetail.fromJson(
    await _api.post(
      '/api/v1/playlists',
      body: {
        'name': name,
        'description': description,
        'visibility': visibility.apiValue,
      },
    ),
  );

  @override
  Future<PlaylistDetail> update(
    String id, {
    String? name,
    String? description,
    bool clearDescription = false,
    PlaylistVisibility? visibility,
  }) async => PlaylistDetail.fromJson(
    await _api.patch(
      '/api/v1/playlists/${Uri.encodeComponent(id)}',
      body: {
        if (name != null) 'name': name,
        if (description != null || clearDescription)
          'description': clearDescription ? null : description,
        if (visibility != null) 'visibility': visibility.apiValue,
      },
    ),
  );

  @override
  Future<void> delete(String id) async {
    await _api.delete('/api/v1/playlists/${Uri.encodeComponent(id)}');
  }

  @override
  Future<PlaylistDetail> addTrack(String id, String catalogTrackId) async =>
      PlaylistDetail.fromJson(
        await _api.post(
          '/api/v1/playlists/${Uri.encodeComponent(id)}/tracks',
          body: {'catalogTrackId': catalogTrackId},
        ),
      );

  @override
  Future<PlaylistDetail> removeTrack(
    String id,
    String itemId,
  ) async => PlaylistDetail.fromJson(
    await _api.delete(
      '/api/v1/playlists/${Uri.encodeComponent(id)}/tracks/${Uri.encodeComponent(itemId)}',
    ),
  );

  @override
  Future<PlaylistDetail> reorder(String id, List<String> itemIds) async =>
      PlaylistDetail.fromJson(
        await _api.put(
          '/api/v1/playlists/${Uri.encodeComponent(id)}/tracks/order',
          body: {'itemIds': itemIds},
        ),
      );
}
