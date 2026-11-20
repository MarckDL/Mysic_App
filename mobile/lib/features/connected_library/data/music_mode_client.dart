import 'package:dio/dio.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../domain/music_mode.dart';
import 'desktop_music_client.dart';

class MusicModeClient {
  MusicModeClient(this._api, {this.desktop});
  final DesktopMusicClient? desktop;

  static const _root = '/api/v2/integrations/youtube-music';
  final AuthenticatedApiClient _api;

  Future<MusicConnection> connection() async {
    final restored = await desktop?.connection();
    if (restored != null) return restored;
    try {
      return MusicConnection.fromJson(await _api.get('$_root/connection'));
    } on ApiFailure catch (error) {
      // The Android update can arrive before the backend exposes this route.
      if (error.statusCode != 404 || error.code != 'NOT_FOUND') rethrow;
      return const MusicConnection(
        status: MusicLinkStatus.unavailable,
        provider: 'serverPending',
      );
    }
  }

  Future<MusicConnection> link(String id, String? generation) async =>
      MusicConnection.fromJson(
        await _api.post(
          '$_root/connection',
          body: {'accountId': id, 'generation': generation},
        ),
      );

  Future<void> unlink(String generation) async {
    if (generation.startsWith('desktop-') && desktop != null) {
      return desktop!.disconnect();
    }
    await _api.delete('$_root/connections/$generation');
  }

  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (generation.startsWith('desktop-') && desktop != null) {
      return desktop!.page(
        generation,
        surface,
        playlistId: playlistId,
        query: query,
        cursor: cursor,
        cancelToken: cancelToken,
      );
    }
    final path = '$_root/connections/$generation/pages/${surface.name}';
    return MusicPage.fromJson(
      await _api.get(
        playlistId == null ? path : '$path/${Uri.encodeComponent(playlistId)}',
        query: {
          if (query != null) 'q': query,
          if (cursor != null) 'cursor': cursor,
        },
        cancelToken: cancelToken,
      ),
    );
  }

  Future<void> activityPreference(String generation, {bool? paused}) async {
    final path = '$_root/connections/$generation/activity';
    if (paused == null) {
      await _api.delete(path);
    } else {
      await _api.put(path, body: {'paused': paused});
    }
  }

  Future<bool> hasListen(String generation, String id) async =>
      (await _api.get(
        '$_root/connections/$generation/listens/$id',
      ))['listen'] !=
      null;

  Future<void> record(
    String generation,
    String id,
    String trackId,
    int listenedMs, {
    int? activityEpoch,
  }) async {
    await _api.put(
      '$_root/connections/$generation/listens/$id',
      body: {
        'trackId': trackId,
        'listenedMs': listenedMs,
        if (activityEpoch != null) 'activityEpoch': activityEpoch,
      },
    );
  }
}
