import 'package:dio/dio.dart';

import '../../../core/network/offline_mode.dart';
import '../domain/spotify_link.dart';

/// Lee una playlist pública de Spotify desde el teléfono, sin cuenta ni API de
/// Spotify: la página «embed» (`open.spotify.com/embed/playlist/<id>`) lleva
/// sus datos en un JSON. Es la misma lectura que hace Mysic de escritorio.
class SpotifyFetcher {
  SpotifyFetcher({Dio? dio}) : _dio = dio ?? Dio(), _ownsGuard = dio == null {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => status != null,
      responseType: ResponseType.plain,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
      },
    );
    // Con «solo canciones descargadas» ninguna petición sale.
    if (_ownsGuard) _dio.interceptors.add(OfflineMode.dioGuard);
  }

  final Dio _dio;
  final bool _ownsGuard;

  /// La playlist del enlace [target]. Lanza [SpotifyLinkFailure].
  Future<SpotifyPlaylist> playlist(String id) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        'https://open.spotify.com/embed/playlist/$id',
      );
    } on DioException {
      throw const SpotifyLinkFailure(SpotifyLinkError.network);
    }
    final status = response.statusCode ?? 0;
    // Una playlist privada o borrada es un 404, igual que un id mal escrito.
    if (status == 404) {
      throw const SpotifyLinkFailure(SpotifyLinkError.private);
    }
    if (status < 200 || status >= 300 || response.data is! String) {
      throw const SpotifyLinkFailure(SpotifyLinkError.network);
    }
    return parseSpotifyPlaylistEmbed(response.data as String);
  }
}
