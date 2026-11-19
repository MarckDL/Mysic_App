import 'package:dio/dio.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../domain/music_import.dart';
import '../domain/takeout_playlist.dart';

class ImportClient {
  ImportClient(this._api);
  final AuthenticatedApiClient _api;
  static const _path = '/api/v1/imports/youtube-music';

  Future<List<MusicImport>> list(CancelToken cancel) async {
    final data = await _api.get(_path, cancelToken: cancel);
    return (data['items'] as List)
        .map((item) => MusicImport.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MusicImport> prepare(
    String id,
    TakeoutPlaylist list,
    CancelToken cancel,
  ) async => MusicImport.fromJson(
    await _api.post(
      _path,
      body: {'id': id, 'name': list.name, 'sourceIds': list.sourceIds},
      cancelToken: cancel,
    ),
  );

  Future<MusicImport> resolve(
    String id,
    List<int> indices,
    CancelToken cancel,
  ) async => MusicImport.fromJson(
    await _api.post(
      '$_path/$id/resolve',
      body: {'indices': indices},
      cancelToken: cancel,
    ),
  );

  Future<MusicImport> confirm(String id, CancelToken cancel) async =>
      MusicImport.fromJson(
        await _api.post('$_path/$id/confirm', body: {}, cancelToken: cancel),
      );

  Future<void> discard(String id, CancelToken cancel) async {
    await _api.delete('$_path/$id', cancelToken: cancel);
  }

  void close() => _api.close();
}
