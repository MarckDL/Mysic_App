import 'package:dio/dio.dart';
import 'favorite.dart';

abstract interface class FavoriteRepository {
  Future<List<FavoriteItem>> list({CancelToken? cancelToken});
  Future<void> add(String trackId, {CancelToken? cancelToken});
  Future<void> remove(String trackId, {CancelToken? cancelToken});
}
