import 'package:dio/dio.dart';

import '../../../core/network/offline_mode.dart';
import '../../search/domain/catalog_track.dart';
import '../domain/lyrics_provider.dart';
import '../domain/ttml.dart';

/// Lo que se pregunta a una fuente de letras.
class LyricsQuery {
  const LyricsQuery({
    required this.title,
    required this.artist,
    this.durationSeconds,
  });

  factory LyricsQuery.of(CatalogTrack track) => LyricsQuery(
    title: searchTitle(track.title),
    artist: track.artistName,
    durationSeconds: track.durationSeconds,
  );

  final String title;
  final String artist;
  final int? durationSeconds;

  /// Clave de caché: la misma canción se pide una vez.
  String get key =>
      '${title.toLowerCase()}|${artist.toLowerCase()}|'
      '${durationSeconds ?? 0}';

  /// Corta en `|` y quita lo que va entre `()`, `[]`, `【】` y `（）`: los
  /// sufijos como "(Official Video)" impiden que las fuentes encuentren la
  /// canción.
  static String searchTitle(String title) {
    var text = title.split('|').first;
    for (final pair in const [
      r'\([^)]*\)',
      r'\[[^\]]*\]',
      r'【[^】]*】',
      r'（[^）]*）',
    ]) {
      text = text.replaceAll(RegExp(pair), '');
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? title.trim() : text;
  }
}

/// Una fuente de letras. Debe devolver `null` si no tiene la canción y puede
/// lanzar si falla: el repositorio decide qué hacer con cada caso.
abstract interface class LyricsSource {
  String get label;

  Future<SongLyrics?> fetch(LyricsQuery query, {CancelToken? cancelToken});
}

/// Tolerancia al comparar la duración de la canción con la de la letra.
const lyricsDurationTolerance = 5.0;

Dio _client(String baseUrl) =>
    Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          followRedirects: false,
          // Los servicios comunitarios piden identificarse.
          headers: {
            'User-Agent': 'Mysic/0.11.0 (https://github.com/MarckDL/Mysic_App)',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      )
      // Con «solo canciones descargadas» ninguna petición sale.
      ..interceptors.add(OfflineMode.dioGuard);

/// LRCLIB: API pública y documentada. Primero la coincidencia exacta y, si no
/// existe, una búsqueda de la que se elige la letra de duración más cercana.
class LrclibSource implements LyricsSource {
  LrclibSource({Dio? dio}) : _dio = dio ?? _client('https://lrclib.net');

  final Dio _dio;

  @override
  String get label => 'LRCLIB';

  @override
  Future<SongLyrics?> fetch(
    LyricsQuery query, {
    CancelToken? cancelToken,
  }) async {
    final exact = await _dio.get<dynamic>(
      '/api/get',
      cancelToken: cancelToken,
      queryParameters: {
        'track_name': query.title,
        'artist_name': query.artist,
        if (query.durationSeconds != null && query.durationSeconds! <= 3600)
          'duration': query.durationSeconds,
      },
    );
    if (exact.statusCode == 200 && exact.data is Map) {
      final found = _lyrics(exact.data as Map);
      if (found != null) return found;
    }
    final search = await _dio.get<dynamic>(
      '/api/search',
      cancelToken: cancelToken,
      queryParameters: {'track_name': query.title, 'artist_name': query.artist},
    );
    if (search.statusCode != 200 || search.data is! List) return null;
    final duration = query.durationSeconds;
    final candidates = [
      for (final item in search.data as List)
        if (item is Map && item['instrumental'] != true) item,
    ];
    // Mejor candidato: con letra sincronizada, y de duración más cercana.
    Map<dynamic, dynamic>? best;
    var bestGap = double.infinity;
    for (final item in candidates) {
      final synced = item['syncedLyrics'];
      final length = item['duration'];
      if (synced is! String || synced.isEmpty) continue;
      final gap = duration == null || length is! num
          ? 0.0
          : (length - duration).abs().toDouble();
      if (duration != null && gap > lyricsDurationTolerance) continue;
      if (gap < bestGap) {
        best = item;
        bestGap = gap;
      }
    }
    return best == null ? null : _lyrics(best);
  }

  static SongLyrics? _lyrics(Map<dynamic, dynamic> data) {
    if (data['instrumental'] == true) return null;
    final plain = data['plainLyrics'];
    final synced = data['syncedLyrics'];
    return SongLyrics.fromLrc(
      plain: plain is String ? plain : null,
      synced: synced is String ? synced : null,
    );
  }
}

/// Boidu (Better Lyrics): servicio comunitario que entrega TTML con tiempos
/// por palabra. Pide la duración, así que solo se consulta si se conoce.
class BoiduSource implements LyricsSource {
  BoiduSource({Dio? dio})
    : _dio = dio ?? _client('https://lyrics-api.boidu.dev');

  final Dio _dio;

  @override
  String get label => 'Better Lyrics';

  @override
  Future<SongLyrics?> fetch(
    LyricsQuery query, {
    CancelToken? cancelToken,
  }) async {
    final duration = query.durationSeconds;
    if (duration == null || duration <= 0 || duration > 3600) return null;
    final response = await _dio.get<dynamic>(
      '/getLyrics',
      cancelToken: cancelToken,
      queryParameters: {'s': query.title, 'a': query.artist, 'd': duration},
    );
    final data = response.data;
    if (response.statusCode != 200 || data is! Map) return null;
    // Entrega TTML (con palabras) o, en su defecto, LRC por línea.
    final ttml = data['ttml'];
    if (ttml is String && ttml.isNotEmpty) {
      final parsed = TtmlLyrics.parse(ttml);
      if (parsed != null) return parsed;
    }
    for (final key in const ['syncedLyrics', 'lrc']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) {
        final parsed = SongLyrics.fromLrc(synced: value);
        if (parsed != null) return parsed;
      }
    }
    final plain = data['lyrics'];
    return plain is String ? SongLyrics.fromLrc(plain: plain) : null;
  }
}
