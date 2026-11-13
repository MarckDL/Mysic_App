import 'package:dio/dio.dart';
import 'track_interactions.dart';

abstract interface class RatingRepository {
  Future<TrackInteractions> interactions(
    String trackId, {
    CancelToken? cancelToken,
  });
  Future<TrackInteractions> rate(
    String trackId,
    int score, {
    required bool isFavorite,
    CancelToken? cancelToken,
  });
}
