import 'package:dio/dio.dart';
import 'favorite.dart';

abstract interface class FavoriteRepository {
  Future<List<FavoriteItem>> list({CancelToken? cancelToken});
  Future<bool> status(String trackId, {CancelToken? cancelToken});
  Future<FavoriteItem> add(String trackId);
  Future<bool> remove(String trackId);
}
