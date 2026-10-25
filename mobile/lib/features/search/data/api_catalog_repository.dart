import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/catalog_repository.dart';
import '../domain/catalog_track.dart';

class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(this._api);
  final AuthenticatedApiClient _api;
  @override
  Future<List<CatalogTrack>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.get(
      '/api/v1/search',
      query: {'q': query},
      cancelToken: cancelToken,
    );
    final items = response['items'];
    if (items is! List || items.length > 20) {
      throw const ApiFailure('Respuesta de catálogo inválida.');
    }
    return items
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const ApiFailure('Respuesta de catálogo inválida.');
          }
          return CatalogTrack.fromJson(item);
        })
        .toList(growable: false);
  }

  @override
  Future<CatalogTrack> detail(String id, {CancelToken? cancelToken}) async {
    if (!RegExp(r'^youtube:[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      throw const ApiFailure('Identificador de pista inválido.');
    }
    final track = CatalogTrack.fromJson(
      await _api.get(
        '/api/v1/tracks/${Uri.encodeComponent(id)}',
        cancelToken: cancelToken,
      ),
    );
    if (track.id != id) {
      throw const ApiFailure('Respuesta de catálogo inválida.');
    }
    return track;
  }
}
