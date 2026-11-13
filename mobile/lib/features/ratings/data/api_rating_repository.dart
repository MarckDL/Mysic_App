import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/rating_repository.dart';
import '../domain/track_interactions.dart';

class ApiRatingRepository implements RatingRepository {
  ApiRatingRepository(this._api);
  final AuthenticatedApiClient _api;

  @override
  Future<TrackInteractions> interactions(
    String trackId, {
    CancelToken? cancelToken,
  }) async => TrackInteractions.fromJson(
    await _api.get(
      '/api/v1/tracks/${Uri.encodeComponent(trackId)}/interactions',
      cancelToken: cancelToken,
    ),
  );

  @override
  Future<TrackInteractions> rate(
    String trackId,
    int score, {
    required bool isFavorite,
    CancelToken? cancelToken,
  }) async {
    final data = await _api.put(
      '/api/v1/ratings/${Uri.encodeComponent(trackId)}',
      body: {'score': score},
      cancelToken: cancelToken,
    );
    return TrackInteractions.fromJson({...data, 'isFavorite': isFavorite});
  }
}
