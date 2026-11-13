import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/favorite.dart';
import '../domain/favorite_repository.dart';

class ApiFavoriteRepository implements FavoriteRepository {
  ApiFavoriteRepository(this._api);
  final AuthenticatedApiClient _api;

  @override
  Future<List<FavoriteItem>> list({CancelToken? cancelToken}) async {
    final data = await _api.get('/api/v1/favorites', cancelToken: cancelToken);
    final items = data['items'];
    if (items is! List) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
    return items
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const ApiFailure('Respuesta de favoritos inválida.');
          }
          return FavoriteItem.fromJson(value);
        })
        .toList(growable: false);
  }

  @override
  Future<void> add(String trackId, {CancelToken? cancelToken}) async {
    final data = await _api.put(
      '/api/v1/favorites/${Uri.encodeComponent(trackId)}',
      body: const {},
      cancelToken: cancelToken,
    );
    if (data['isFavorite'] != true) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
  }

  @override
  Future<void> remove(String trackId, {CancelToken? cancelToken}) async {
    final data = await _api.delete(
      '/api/v1/favorites/${Uri.encodeComponent(trackId)}',
      cancelToken: cancelToken,
    );
    if (data['isFavorite'] != false) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
  }
}
