import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/hls_track_info.dart';
import '../domain/live_now_playing.dart';
import '../domain/radio_mood.dart';

/// Lee la lista de moods de una emisora. Solo `https`, con tiempo límite; ante
/// cualquier fallo, vacío (las pastillas simplemente no salen).
Future<List<RadioMood>> fetchRadioMoods(Uri url) async {
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    return const [];
  }
  try {
    final response = await Dio().getUri<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final body = response.data;
    if (body == null || body.length > 250000) return const [];
    return RadioMood.parseList(jsonDecode(body));
  } on Object {
    return const [];
  }
}

/// Los datos de la canción que suena en un stream HLS ([master] es su
/// `.m3u8`), leídos de la etiqueta ID3 del último segmento. Se usa la variante
/// de menos calidad (segmentos de ~40 KB, con los mismos metadatos) y se
/// recuerda su lista para no pedir el maestro cada vez. La carátula solo se
/// devuelve si existe (se comprueba una vez por pista). Cualquier fallo: null.
Future<HlsTrackInfo?> fetchHlsTrackInfo(Uri master) async {
  if (master.scheme != 'https' ||
      master.host.isEmpty ||
      master.userInfo.isNotEmpty ||
      !master.path.endsWith('.m3u8')) {
    return null;
  }
  try {
    final dio = _hlsDio;
    Future<String> text(Uri url) async {
      final r = await dio.getUri<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final body = r.data ?? '';
      if (body.length > 200000) throw const FormatException('grande');
      return body;
    }

    var chunklist = _chunklists[master];
    if (chunklist == null) {
      // El maestro: la última variante listada es la de menos ancho de banda.
      final lines = (await text(master)).split('\n').map((l) => l.trim());
      final entries = lines.where((l) => l.isNotEmpty && !l.startsWith('#'));
      if (entries.isEmpty) return null;
      chunklist = master.resolve(entries.last);
      if (chunklist.scheme != 'https' || chunklist.host != master.host) {
        return null;
      }
      _chunklists[master] = chunklist;
    }
    final segments = (await text(chunklist))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    if (segments.length < 2) return null;
    // El reproductor va ~30 s por detrás del borde del directo (la señal lo
    // declara: PART-HOLD-BACK=30). Leer el último segmento enseñaría la
    // canción siguiente antes de que se oiga; se lee uno de hace
    // [_hlsLagSegments] (~5 s cada uno). Si ya no existe, se prueba con el
    // siguiente más nuevo. El último puede estar a medias (baja latencia).
    final lastFull = segments.length - 2;
    final first = (segments.length - 1 - _hlsLagSegments).clamp(0, lastFull);
    for (var i = first; i <= lastFull; i++) {
      final segment = chunklist.resolve(segments[i]);
      if (segment.scheme != 'https' || segment.host != master.host) return null;
      List<int>? data;
      try {
        final r = await dio.getUri<List<int>>(
          segment,
          options: Options(responseType: ResponseType.bytes),
        );
        data = r.data;
      } on DioException {
        continue; // ya se retiró de la lista: el siguiente
      }
      if (data == null || data.length > 2000000) return null;
      final info = HlsTrackInfo.fromSegment(Uint8List.fromList(data));
      return info == null ? null : await _withCover(dio, info);
    }
    return null;
  } on Object {
    return null;
  }
}

/// Cuántos segmentos (~5 s) por detrás del último se lee la etiqueta: ~25 s, lo
/// que el reproductor se retrasa respecto al borde del directo.
const _hlsLagSegments = 5;

final _hlsDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
    headers: const {'Cache-Control': 'no-cache'},
  ),
);
final _chunklists = <Uri, Uri>{};
final _coverChecks = <String, bool>{};

/// Quita el id de la pista si su carátula no existe (así no se pide una
/// imagen que dará error); lo recuerda para no repetir la comprobación.
Future<HlsTrackInfo> _withCover(Dio dio, HlsTrackInfo info) async {
  final cover = info.coverUri;
  if (cover == null) return info;
  final key = cover.toString();
  var exists = _coverChecks[key];
  if (exists == null) {
    try {
      final r = await dio.headUri<void>(
        cover,
        options: Options(validateStatus: (_) => true),
      );
      exists = r.statusCode == 200;
    } on Object {
      exists = false;
    }
    if (_coverChecks.length > 200) _coverChecks.clear();
    _coverChecks[key] = exists;
  }
  return exists
      ? info
      : HlsTrackInfo(
          title: info.title,
          artist: info.artist,
          album: info.album,
          label: info.label,
          year: info.year,
        );
}

/// Pide la hora de la emisora como la usa su web (`date=now`): la hora de la
/// pared del teléfono, no UTC.
String _wallStamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Lee el JSON de «lo que suena ahora» de una emisora. Solo `https`, con
/// tiempo límite y sin respuestas enormes; cualquier fallo es null (la
/// reproducción no depende de esto).
Future<LiveNowPlaying?> fetchLiveNowPlaying(Uri url) async {
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    return null;
  }
  try {
    // `date=now` pide la programación a la hora de ahora en la pared del
    // teléfono (la web de ROVR hace igual: cada huso horario tiene su
    // programación).
    final target = url.queryParameters['date'] == 'now'
        ? url.replace(
            queryParameters: {
              ...url.queryParameters,
              'date': _wallStamp(DateTime.now()),
            },
          )
        : url;
    final response = await Dio().getUri<String>(
      target,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: const {'Cache-Control': 'no-cache'},
      ),
    );
    final body = response.data;
    // La programación de ROVR pesa ~35 KB (todo el programa y sus pistas).
    if (body == null || body.length > 250000) return null;
    return LiveNowPlaying.parse(jsonDecode(body));
  } on Object {
    return null;
  }
}
