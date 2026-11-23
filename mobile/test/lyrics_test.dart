import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/lyrics/domain/lyrics_provider.dart';

void main() {
  group('LRC por línea', () {
    test('ordena las líneas por tiempo y respeta el desfase', () {
      final lyrics = SongLyrics.fromLrc(
        synced:
            '[offset: 500]\n[00:10.00]segunda\n[00:05.00]primera\n[00:00.20]corta',
      )!;
      expect(lyrics.lines.map((line) => line.text), [
        'corta',
        'primera',
        'segunda',
      ]);
      // El desfase de 500 ms adelanta cada línea; nunca queda por debajo de 0.
      expect(lyrics.lines.first.start, Duration.zero);
      expect(lyrics.lines[1].start, const Duration(milliseconds: 4500));
    });

    test('lineAt devuelve la línea activa y -1 antes de la primera', () {
      final lyrics = SongLyrics.fromLrc(
        synced: '[00:05.00]a\n[00:10.00]b\n[00:15.00]c',
      )!;
      expect(lyrics.lineAt(const Duration(seconds: 2)), -1);
      expect(lyrics.lineAt(const Duration(seconds: 5)), 0);
      expect(lyrics.lineAt(const Duration(seconds: 12)), 1);
      expect(lyrics.lineAt(const Duration(minutes: 3)), 2);
    });

    test('una letra sin tiempos ni texto es nula', () {
      expect(SongLyrics.fromLrc(synced: '[00:01.00]\n[00:02.00]  '), isNull);
      expect(SongLyrics.fromLrc(plain: '   '), isNull);
    });
  });

  group('LRC ampliado (palabra a palabra)', () {
    const source =
        '[00:10.00]<00:10.00>Hola <00:10.50>mundo <00:11.00>cruel\n'
        '[00:13.00]línea sin palabras';

    test('extrae las palabras con su inicio y conserva el texto limpio', () {
      final lyrics = SongLyrics.fromLrc(synced: source)!;
      final first = lyrics.lines.first;
      expect(first.text, 'Hola mundo cruel');
      expect(first.hasWords, isTrue);
      expect(first.words.map((word) => word.text), [
        'Hola ',
        'mundo ',
        'cruel',
      ]);
      expect(first.words.map((word) => word.start.inMilliseconds), [
        10000,
        10500,
        11000,
      ]);
      expect(lyrics.lines[1].hasWords, isFalse);
    });

    test('el avance de la línea sube con las palabras cantadas', () {
      final line = SongLyrics.fromLrc(synced: source)!.lines.first;
      const end = Duration(seconds: 12);
      expect(line.progressAt(const Duration(seconds: 9), end), 0);
      expect(
        line.progressAt(const Duration(milliseconds: 10500), end),
        closeTo(5 / 16, .001), // "Hola " ya cantada
      );
      final middle = line.progressAt(const Duration(milliseconds: 10750), end);
      expect(middle, greaterThan(5 / 16));
      expect(middle, lessThan(11 / 16));
      expect(line.progressAt(end, end), 1);
    });

    test('una línea sin palabras salta de 0 a 1 en su final', () {
      final line = SongLyrics.fromLrc(synced: source)!.lines[1];
      const end = Duration(seconds: 15);
      expect(line.progressAt(const Duration(seconds: 13), end), 0);
      expect(line.progressAt(const Duration(seconds: 14), end), 0);
      expect(line.progressAt(end, end), 1);
    });

    test('las etiquetas de varias voces no se asignan a un texto distinto', () {
      final lyrics = SongLyrics.fromLrc(
        synced: '[00:10.00]<00:10.00>uno <00:10.50>dos\n[00:10.00]segunda voz',
      )!;
      final line = lyrics.lines.single;
      expect(line.text, 'uno dos\nsegunda voz');
      expect(line.hasWords, isFalse);
    });
  });
}
