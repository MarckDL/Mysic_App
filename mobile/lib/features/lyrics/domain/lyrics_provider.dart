/// Una palabra (o sílaba) con su instante de inicio, para resaltar la letra
/// palabra a palabra. El texto conserva el espacio final si lo tenía.
class LyricWord {
  const LyricWord(this.start, this.text);

  final Duration start;
  final String text;
}

class LyricLine {
  const LyricLine(this.start, this.text, {this.words = const []});

  final Duration start;
  final String text;

  /// Vacío si la fuente solo sincroniza por línea.
  final List<LyricWord> words;

  bool get hasWords => words.length > 1;

  /// Avance de 0 a 1 de la línea en [position]: palabras ya cantadas más la
  /// fracción de la actual. Sin palabras, 0 antes y 1 después de [start].
  double progressAt(Duration position, Duration end) {
    if (position < start) return 0;
    if (!hasWords) return position >= end ? 1 : 0;
    var sung = 0;
    var total = 0;
    for (var i = 0; i < words.length; i++) {
      final length = words[i].text.length;
      total += length;
      final wordEnd = i + 1 < words.length ? words[i + 1].start : end;
      if (position >= wordEnd) {
        sung += length;
      } else if (position >= words[i].start) {
        final span = (wordEnd - words[i].start).inMilliseconds;
        final into = (position - words[i].start).inMilliseconds;
        sung += (length * (span <= 0 ? 1 : into / span)).round();
      }
    }
    return total == 0 ? 0 : (sung / total).clamp(0.0, 1.0).toDouble();
  }
}

class SongLyrics {
  const SongLyrics({this.plain, this.lines = const [], this.source});

  final String? plain;
  final List<LyricLine> lines;

  /// Nombre de la fuente que la entregó (para la atribución).
  final String? source;

  SongLyrics withSource(String name) =>
      SongLyrics(plain: plain, lines: lines, source: name);

  bool get isSynced => lines.isNotEmpty;
  bool get hasWordSync => lines.any((line) => line.hasWords);

  static final _timestamp = RegExp(
    r'\[(\d{1,4}):([0-5]\d)(?:[.:](\d{1,3}))?\]',
  );
  static final _offset = RegExp(
    r'^\[offset:\s*([+-]?\d{1,7})\s*\]$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _inlineTime = RegExp(r'<(\d{1,4}):([0-5]\d)(?:[.:](\d{1,3}))?>');

  /// Palabras de una línea con etiquetas "<mm:ss.xx>" (LRC ampliado).
  static List<LyricWord> _words(String rest, int offset) {
    final tags = _inlineTime.allMatches(rest).toList();
    if (tags.length < 2) return const [];
    final words = <LyricWord>[];
    for (var i = 0; i < tags.length; i++) {
      final tag = tags[i];
      final end = i + 1 < tags.length ? tags[i + 1].start : rest.length;
      final text = rest.substring(tag.end, end);
      if (text.trim().isEmpty) {
        // Un espacio suelto pertenece a la palabra anterior.
        if (words.isNotEmpty && text.isNotEmpty) {
          final last = words.removeLast();
          words.add(LyricWord(last.start, last.text + text));
        }
        continue;
      }
      final milliseconds =
          (int.parse(tag[1]!) * 60 + int.parse(tag[2]!)) * 1000 +
          int.parse((tag[3] ?? '').padRight(3, '0')) -
          offset;
      words.add(
        LyricWord(
          Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds),
          text,
        ),
      );
    }
    return words;
  }

  static SongLyrics? fromLrc({String? plain, String? synced}) {
    final text = plain?.trim();
    final source = synced?.replaceAll('\r', '').trim() ?? '';
    final offset =
        int.tryParse(_offset.firstMatch(source)?.group(1) ?? '') ?? 0;
    final times = <int, List<String>>{};
    final wordsAt = <int, List<LyricWord>>{};
    for (final raw in source.split('\n')) {
      final line = raw.trimLeft();
      var cursor = 0;
      final stamps = <int>[];
      while (true) {
        final match = _timestamp.matchAsPrefix(line, cursor);
        if (match == null) break;
        cursor = match.end;
        final minutes = int.parse(match[1]!);
        final seconds = int.parse(match[2]!);
        final fraction = int.parse((match[3] ?? '').padRight(3, '0'));
        final milliseconds =
            (minutes * 60 + seconds) * 1000 + fraction - offset;
        stamps.add(milliseconds < 0 ? 0 : milliseconds);
      }
      if (stamps.isEmpty) continue;
      final rest = line.substring(cursor);
      final verse = rest.replaceAll(_inlineTime, '').trim();
      final words = stamps.length == 1
          ? _words(rest, offset)
          : const <LyricWord>[];
      for (final stamp in stamps) {
        final group = times.putIfAbsent(stamp, () => []);
        if (!group.contains(verse)) group.add(verse);
        if (words.isNotEmpty) wordsAt.putIfAbsent(stamp, () => words);
      }
    }
    final sorted = times.keys.toList()..sort();
    final lines = [
      for (final stamp in sorted)
        LyricLine(
          Duration(milliseconds: stamp),
          times[stamp]!.where((verse) => verse.isNotEmpty).join('\n'),
          // Solo si la línea es una sola voz: con varias, las palabras no
          // corresponderían al texto unido.
          words: times[stamp]!.length == 1
              ? (wordsAt[stamp] ?? const [])
              : const [],
        ),
    ];
    final hasTimedText = lines.any((line) => line.text.isNotEmpty);
    if (!hasTimedText && (text == null || text.isEmpty)) return null;
    return SongLyrics(
      plain: text?.isNotEmpty == true ? text : null,
      lines: hasTimedText ? List.unmodifiable(lines) : const [],
    );
  }

  int lineAt(Duration position) {
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].start <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }
}
