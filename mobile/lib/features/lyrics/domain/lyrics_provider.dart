import '../../search/domain/catalog_track.dart';

abstract interface class LyricsProvider {
  Future<SongLyrics?> getLyrics(CatalogTrack track);
}

class LyricLine {
  const LyricLine(this.start, this.text);

  final Duration start;
  final String text;
}

class SongLyrics {
  const SongLyrics({this.plain, this.lines = const []});

  final String? plain;
  final List<LyricLine> lines;

  static final _timestamp = RegExp(
    r'\[(\d{1,4}):([0-5]\d)(?:[.:](\d{1,3}))?\]',
  );
  static final _offset = RegExp(
    r'^\[offset:\s*([+-]?\d{1,7})\s*\]$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _inlineTime = RegExp(r'<\d{1,4}:[0-5]\d(?:[.:]\d{1,3})?>');

  static SongLyrics? fromLrc({String? plain, String? synced}) {
    final text = plain?.trim();
    final source = synced?.replaceAll('\r', '').trim() ?? '';
    final offset =
        int.tryParse(_offset.firstMatch(source)?.group(1) ?? '') ?? 0;
    final times = <int, List<String>>{};
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
      final verse = line.substring(cursor).replaceAll(_inlineTime, '').trim();
      for (final stamp in stamps) {
        final group = times.putIfAbsent(stamp, () => []);
        if (!group.contains(verse)) group.add(verse);
      }
    }
    final sorted = times.keys.toList()..sort();
    final lines = [
      for (final stamp in sorted)
        LyricLine(
          Duration(milliseconds: stamp),
          times[stamp]!.where((verse) => verse.isNotEmpty).join('\n'),
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
