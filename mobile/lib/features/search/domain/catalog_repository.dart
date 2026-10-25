import 'package:dio/dio.dart';
import 'catalog_track.dart';

abstract interface class CatalogRepository {
  Future<List<CatalogTrack>> search(String query, {CancelToken? cancelToken});
  Future<CatalogTrack> detail(String id, {CancelToken? cancelToken});
}
