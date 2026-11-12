import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/rating.dart';
import '../domain/rating_repository.dart';

class ApiRatingRepository implements RatingRepository {
  ApiRatingRepository(this._api);
  final AuthenticatedApiClient _api;

  String _path(String trackId) {
    final match = RegExp(r'^youtube:([A-Za-z0-9_-]{11})$').firstMatch(trackId);
    if (match == null) throw const ApiFailure('Pista inválida.');
    return '/api/v1/ratings/youtube/${match.group(1)}';
  }

  @override
  Future<RatingSummary> get(String trackId, {CancelToken? cancelToken}) async =>
      RatingSummary.fromJson(
        await _api.get(_path(trackId), cancelToken: cancelToken),
      );

  @override
  Future<RatingSummary> set(String trackId, int score) async =>
      RatingSummary.fromJson(
        await _api.put(_path(trackId), body: {'score': score}),
      );

  @override
  Future<RatingSummary> remove(String trackId) async =>
      RatingSummary.fromJson(await _api.delete(_path(trackId)));
}
