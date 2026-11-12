import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/favorite.dart';
import '../domain/favorite_repository.dart';

class ApiFavoriteRepository implements FavoriteRepository {
  ApiFavoriteRepository(this._api);
  final AuthenticatedApiClient _api;

  String _path(String trackId) {
    final match = RegExp(r'^youtube:([A-Za-z0-9_-]{11})$').firstMatch(trackId);
    if (match == null) throw const ApiFailure('Pista inválida.');
    return '/api/v1/favorites/youtube/${match.group(1)}';
  }

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
  Future<bool> status(String trackId, {CancelToken? cancelToken}) async {
    final data = await _api.get(_path(trackId), cancelToken: cancelToken);
    final favorite = data['favorite'];
    if (favorite is! bool) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
    return favorite;
  }

  @override
  Future<FavoriteItem> add(String trackId) async =>
      FavoriteItem.fromJson(await _api.put(_path(trackId)));

  @override
  Future<bool> remove(String trackId) async {
    final data = await _api.delete(_path(trackId));
    final deleted = data['deleted'];
    if (deleted is! bool) {
      throw const ApiFailure('Respuesta de favoritos inválida.');
    }
    return deleted;
  }
}
