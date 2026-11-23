import 'lyrics_provider.dart';

/// Lector mínimo de TTML (el formato de letras de Apple Music) para las letras
/// palabra a palabra: `<p begin end>` por línea y `<span begin end>` por
/// palabra o sílaba. No es un lector XML completo; lee solo lo que hace falta y
/// rechaza lo que no entiende devolviendo `null`.
///
/// Se ignoran las voces de fondo (`ttm:role="x-bg"`), que las apps como
/// Limusic muestran aparte.
abstract final class TtmlLyrics {
  static final _paragraph = RegExp(
    r'<p\b([^>]*)>(.*?)</p>',
    dotAll: true,
    caseSensitive: false,
  );
  static final _background = RegExp(
    r'<span\b[^>]*ttm:role="x-bg"[^>]*>.*?</span></span>',
    dotAll: true,
    caseSensitive: false,
  );
  static final _span = RegExp(
    r'<span\b([^>]*)>(.*?)</span>',
    dotAll: true,
    caseSensitive: false,
  );
  static final _tag = RegExp(r'<[^>]+>');

  static SongLyrics? parse(String xml) {
    if (!xml.contains('<p')) return null;
    final lines = <LyricLine>[];
    for (final paragraph in _paragraph.allMatches(xml)) {
      final begin = _clock(_attribute(paragraph[1]!, 'begin'));
      if (begin == null) continue;
      final body = paragraph[2]!.replaceAll(_background, '');
      final words = <LyricWord>[];
      var cursor = 0;
      for (final span in _span.allMatches(body)) {
        final start = _clock(_attribute(span[1]!, 'begin'));
        final text = _text(span[2]!);
        // Un espacio entre dos `<span>` separa palabras; sin él son sílabas.
        final gap = body.substring(cursor, span.start);
        if (words.isNotEmpty && gap.contains(RegExp(r'\s'))) {
          final last = words.removeLast();
          if (!last.text.endsWith(' ')) {
            words.add(LyricWord(last.start, '${last.text} '));
          } else {
            words.add(last);
          }
        }
        cursor = span.end;
        if (start == null || text.isEmpty) continue;
        words.add(LyricWord(start, text));
      }
      final text = words.isEmpty
          ? _text(body)
          : words.map((word) => word.text).join().trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine(begin, text, words: words.length > 1 ? words : []));
    }
    if (lines.isEmpty) return null;
    lines.sort((a, b) => a.start.compareTo(b.start));
    return SongLyrics(lines: List.unmodifiable(lines));
  }

  static String? _attribute(String attributes, String name) =>
      RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(attributes)?[1];

  /// "27.395", "1:02.345", "0:01:02.345" o "12.5s" → duración.
  static Duration? _clock(String? value) {
    if (value == null) return null;
    var text = value.trim();
    if (text.endsWith('s')) text = text.substring(0, text.length - 1);
    var seconds = 0.0;
    for (final part in text.split(':')) {
      final number = double.tryParse(part);
      if (number == null) return null;
      seconds = seconds * 60 + number;
    }
    return Duration(microseconds: (seconds * 1e6).round());
  }

  static String _text(String html) => html
      .replaceAll(_tag, '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll(RegExp(r'\s+'), ' ');
}
