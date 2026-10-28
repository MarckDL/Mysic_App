import 'package:dio/dio.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/playback_resolution.dart';

abstract interface class PlaybackRepository {
  Future<PlaybackResolution> resolve(
    String source,
    String sourceId, {
    CancelToken? cancelToken,
  });
}

class ApiPlaybackRepository implements PlaybackRepository {
  ApiPlaybackRepository(this._api);
  final AuthenticatedApiClient _api;
  @override
  Future<PlaybackResolution> resolve(
    String source,
    String sourceId, {
    CancelToken? cancelToken,
  }) async {
    final result = PlaybackResolution.fromJson(
      await _api.post(
        '/api/v1/playback/resolve',
        body: {'source': source, 'sourceId': sourceId},
        cancelToken: cancelToken,
      ),
    );
    if (source != 'demo' && result.available) {
      throw const PlaybackFailure('Esta fuente no está habilitada.');
    }
    return result;
  }
}
