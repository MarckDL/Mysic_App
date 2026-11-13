import '../../../core/network/authenticated_api_client.dart';
import '../domain/youtube_library.dart';

class YoutubeLibraryRepository {
  YoutubeLibraryRepository(this._api);
  final AuthenticatedApiClient _api;

  Future<YoutubeConnectionStatus> status() async =>
      YoutubeConnectionStatus.fromJson(
        await _api.get('/api/v1/integrations/youtube/status'),
      );

  Future<YoutubeLibrary> library() async => YoutubeLibrary.fromJson(
    await _api.get('/api/v1/integrations/youtube/library'),
  );

  Future<YoutubeConnectionStatus> sync(String temporaryAccessToken) async =>
      YoutubeConnectionStatus.fromJson(
        await _api.post(
          '/api/v1/integrations/youtube/sync',
          body: const {},
          headers: {'X-YouTube-OAuth-Token': temporaryAccessToken},
          preserveSessionOnUnauthorized: true,
        ),
      );

  Future<void> disconnect() async {
    await _api.delete('/api/v1/integrations/youtube');
  }

  Future<void> duplicate(String remotePlaylistId) async {
    await _api.post(
      '/api/v1/integrations/youtube/playlists/$remotePlaylistId/duplicate',
      body: const {},
    );
  }
}
