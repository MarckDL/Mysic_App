import 'dart:convert';
import 'dart:typed_data';

/// Lee los metadatos de la canción de un stream HLS; null si no hay.
typedef HlsInfoFetcher = Future<HlsTrackInfo?> Function(Uri master);

/// Lo que dice una emisora sobre la canción que suena, escrito dentro del
/// propio audio HLS: cada segmento lleva una caja `emsg` con una etiqueta ID3
/// (título, artista, álbum, discográfica, año y el id de la pista). Es lo que
/// lee la web de ROVR, y vale para todas sus señales (radio y moods).
class HlsTrackInfo {
  const HlsTrackInfo({
    required this.title,
    this.artist,
    this.album,
    this.label,
    this.year,
    this.trackId,
  });

  final String title;
  final String? artist, album, label, year;

  /// El id de la pista en la emisora (`TXXX/TrackId`); de él sale la carátula.
  final String? trackId;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{6,64}$');

  /// La carátula de ROVR: `album_art/<TrackId>.jpg`. Solo si el id es de los
  /// que se pueden poner en una dirección sin riesgo. No todas las pistas la
  /// tienen: quien la use debe comprobar que existe.
  Uri? get coverUri => trackId != null && _safeId.hasMatch(trackId!)
      ? Uri.https(
          'rovr-prod.s3.eu-west-2.amazonaws.com',
          '/album_art/$trackId.jpg',
        )
      : null;

  /// La última etiqueta ID3 de un segmento fMP4 (la más reciente), o null si no
  /// hay o no trae título. Es tolerante: lo que no entiende lo salta.
  static HlsTrackInfo? fromSegment(Uint8List bytes) {
    HlsTrackInfo? last;
    var from = 0;
    while (true) {
      final at = _find(bytes, from);
      if (at < 0) break;
      from = at + 3;
      final info = _parseTag(bytes, at);
      if (info != null) last = info;
    }
    return last;
  }

  /// Busca «ID3» seguido de versión 3 o 4: así no confunde el texto
  /// `https://aomedia.org/emsg/ID3` ni `ID3.OvenMediaEngine.ID3` del `emsg`.
  static int _find(Uint8List b, int from) {
    for (var i = from; i + 10 <= b.length; i++) {
      if (b[i] == 0x49 &&
          b[i + 1] == 0x44 &&
          b[i + 2] == 0x33 &&
          (b[i + 3] == 3 || b[i + 3] == 4) &&
          b[i + 4] == 0) {
        return i;
      }
    }
    return -1;
  }

  static int _synchsafe(Uint8List b, int i) =>
      (b[i] & 0x7f) << 21 |
      (b[i + 1] & 0x7f) << 14 |
      (b[i + 2] & 0x7f) << 7 |
      (b[i + 3] & 0x7f);

  static HlsTrackInfo? _parseTag(Uint8List b, int start) {
    final version = b[start + 3];
    final size = _synchsafe(b, start + 6);
    final end = start + 10 + size;
    if (size <= 0 || end > b.length) return null;
    final text = <String, String>{};
    String? trackId;
    var i = start + 10;
    while (i + 10 <= end) {
      final id = String.fromCharCodes(b.sublist(i, i + 4));
      // v2.4 usa tamaños «synchsafe»; v2.3, enteros normales.
      final frameSize = version == 4
          ? _synchsafe(b, i + 4)
          : (b[i + 4] << 24) | (b[i + 5] << 16) | (b[i + 6] << 8) | b[i + 7];
      final body = i + 10;
      if (frameSize <= 0 || body + frameSize > end) break;
      if (id == 'TXXX') {
        final parts = _decodeFrame(b, body, frameSize, split: true);
        if (parts.length >= 2 && parts[0] == 'TrackId') trackId = parts[1];
      } else if (id.startsWith('T')) {
        final parts = _decodeFrame(b, body, frameSize);
        if (parts.isNotEmpty) text[id] = parts[0];
      }
      i = body + frameSize;
    }
    final title = text['TIT2']?.trim();
    if (title == null || title.isEmpty || title.length > 200) return null;
    String? clean(String? s) {
      final t = s?.trim();
      return t == null || t.isEmpty || t.length > 200 ? null : t;
    }

    return HlsTrackInfo(
      title: title,
      artist: clean(text['TPE1']),
      album: clean(text['TALB']),
      label: clean(text['TPUB']),
      year: clean(text['TYER'] ?? text['TDRC']),
      trackId: trackId,
    );
  }

  /// El texto de una trama: primer byte = codificación (0 latin1, 1 UTF-16 con
  /// BOM, 2 UTF-16 BE, 3 UTF-8). Con [split], separa por el terminador (TXXX:
  /// descripción y valor).
  static List<String> _decodeFrame(
    Uint8List b,
    int start,
    int length, {
    bool split = false,
  }) {
    if (length < 2) return const [];
    final encoding = b[start];
    final data = b.sublist(start + 1, start + length);
    String decode(List<int> raw) {
      switch (encoding) {
        case 1:
        case 2:
          return _utf16(raw, encoding == 2);
        case 3:
          return utf8.decode(raw, allowMalformed: true);
        default:
          return latin1.decode(raw);
      }
    }

    final wide = encoding == 1 || encoding == 2;
    final parts = <List<int>>[];
    var from = 0;
    for (var i = 0; i < data.length; i += wide ? 2 : 1) {
      final isZero = wide
          ? i + 1 < data.length && data[i] == 0 && data[i + 1] == 0
          : data[i] == 0;
      if (isZero) {
        parts.add(data.sublist(from, i));
        from = i + (wide ? 2 : 1);
        if (!split) break;
      }
    }
    if (from < data.length) parts.add(data.sublist(from));
    if (parts.isEmpty) parts.add(data);
    return [for (final p in parts) decode(p)];
  }

  static String _utf16(List<int> raw, bool bigEndian) {
    var data = raw;
    var be = bigEndian;
    if (data.length >= 2) {
      if (data[0] == 0xFF && data[1] == 0xFE) {
        be = false;
        data = data.sublist(2);
      } else if (data[0] == 0xFE && data[1] == 0xFF) {
        be = true;
        data = data.sublist(2);
      }
    }
    final units = <int>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      units.add(
        be ? (data[i] << 8) | data[i + 1] : (data[i + 1] << 8) | data[i],
      );
    }
    return String.fromCharCodes(units);
  }
}
