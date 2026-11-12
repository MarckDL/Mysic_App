import 'package:dio/dio.dart';
import 'rating.dart';

abstract interface class RatingRepository {
  Future<RatingSummary> get(String trackId, {CancelToken? cancelToken});
  Future<RatingSummary> set(String trackId, int score);
  Future<RatingSummary> remove(String trackId);
}
