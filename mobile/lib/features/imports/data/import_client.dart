import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../domain/music_import.dart';
import '../domain/takeout_playlist.dart';

String newImportId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

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
