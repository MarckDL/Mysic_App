import 'package:dio/dio.dart';
import 'playlist.dart';

abstract interface class PlaylistRepository {
  Future<List<PlaylistSummary>> list({CancelToken? cancelToken});
  Future<PlaylistDetail> detail(String id, {CancelToken? cancelToken});
  Future<PlaylistDetail> create({
    required String name,
    String? description,
    PlaylistVisibility visibility = PlaylistVisibility.private,
  });
  Future<PlaylistDetail> update(
    String id, {
    String? name,
    String? description,
    bool clearDescription = false,
    PlaylistVisibility? visibility,
  });
  Future<void> delete(String id);
  Future<PlaylistDetail> addTrack(String id, String catalogTrackId);
  Future<PlaylistDetail> removeTrack(String id, String itemId);
  Future<PlaylistDetail> reorder(String id, List<String> itemIds);
}
