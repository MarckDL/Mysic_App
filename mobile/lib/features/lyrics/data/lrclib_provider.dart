import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../search/domain/catalog_track.dart';
import '../domain/lyrics_provider.dart';

final lyricsProvider = Provider.autoDispose<LrclibProvider>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://lrclib.net',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: false,
      headers: {
        'User-Agent': 'Mysic/0.11.0 (https://github.com/MarckDL/Mysic_App)',
      },
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return LrclibProvider(dio);
});

class LrclibProvider implements LyricsProvider {
  const LrclibProvider(this.dio);
  final Dio dio;

  @override
  Future<SongLyrics?> getLyrics(
    CatalogTrack track, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/get',
        cancelToken: cancelToken,
        queryParameters: {
          'track_name': track.title,
          'artist_name': track.artistName,
          if (track.durationSeconds != null && track.durationSeconds! <= 3600)
            'duration': track.durationSeconds,
        },
      );
      final data = response.data;
      if (data == null || data['instrumental'] == true) return null;
      final plain = data['plainLyrics'];
      final synced = data['syncedLyrics'];
      return SongLyrics.fromLrc(
        plain: plain is String ? plain : null,
        synced: synced is String ? synced : null,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}

final trackLyricsProvider = FutureProvider.autoDispose
    .family<SongLyrics?, CatalogTrack>((ref, track) {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return ref.watch(lyricsProvider).getLyrics(track, cancelToken: cancel);
    }, retry: (count, error) => null);
