import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/imports/data/takeout_parser.dart';
import 'package:mysic/features/imports/domain/takeout_playlist.dart';

Uint8List encoded(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final parser = TakeoutParser();
  test('lee metadatos antiguos, BOM, comillas, CRLF, orden y repetidos', () {
    final input =
        '\uFEFFPlaylist Id,Title,Description\r\nPL123,"Rock, música","Dos\r\nlíneas"\r\n\r\nVideo Id,Time Added\r\nabcdefghijk,2026-01-01\r\nbcdefghijkl,2026-01-02\r\nabcdefghijk,2026-01-03\r\nbad,2026-01-04\r\n';
    final result = parser.parse('lista.csv', encoded(input));
    expect(result.single.name, 'Rock, música');
    expect(result.single.sourceIds, [
      'abcdefghijk',
      'bcdefghijkl',
      'abcdefghijk',
    ]);
    expect(result.single.invalidRows, 1);
  });

  test('copia biblioteca como una playlist y admite URLs conocidas', () {
    final result = parser.parse(
      'music-library-songs.csv',
      encoded(
        'Song URL,Song Title,Album Title,Artist Names\n'
        'https://music.youtube.com/watch?v=abcdefghijk,Song,Album,Artist\n'
        'https://youtu.be/bcdefghijkl,Other,Album,Artist\n'
        'https://example.com/watch?v=cdefghijklm,Invalid,Album,Artist\n',
      ),
    );
    expect(result.single.name, 'Guardadas de YouTube Music');
    expect(result.single.sourceIds, ['abcdefghijk', 'bcdefghijkl']);
    expect(result.single.invalidRows, 1);
  });

  test('lee ZIP de Takeout y excluye historial, audios y otros archivos', () {
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'Takeout/YouTube and YouTube Music/playlists/Mi lista.csv',
          'Video ID,Playlist Video Creation Timestamp\nabcdefghijk,2026-01-01\n',
        ),
      )
      ..add(
        ArchiveFile.string(
          'Takeout/YouTube and YouTube Music/music (library and uploads)/music-library-songs.csv',
          'Video ID,Song Title,Album Title,Artist Name\nbcdefghijkl,Song,Album,Artist\n',
        ),
      )
      ..add(
        ArchiveFile.string(
          'Takeout/YouTube/history/watch-history.csv',
          'Video ID\ncdefghijklm\n',
        ),
      )
      ..add(ArchiveFile.bytes('audio.mp3', [1, 2, 3]));
    final result = parser.parse(
      'takeout.zip',
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(result.map((list) => list.name), [
      'Mi lista',
      'Guardadas de YouTube Music',
    ]);
    expect(result.expand((list) => list.sourceIds), [
      'abcdefghijk',
      'bcdefghijkl',
    ]);
  });

  test(
    'divide 501 pistas en partes privadas de hasta 500 y limita nombres',
    () {
      final text = csv.encode([
        ['Video ID'],
        for (var index = 0; index < 501; index++) ['abcdefghijk'],
      ]);
      final result = parser.parse('${'Á' * 170}.csv', encoded(text));
      expect(result.map((list) => list.sourceIds.length), [500, 1]);
      expect(result.first.name.endsWith('(parte 1 de 2)'), isTrue);
      expect(result.every((list) => list.name.runes.length <= 150), isTrue);
    },
  );

  test(
    'rechaza ZIP dañado, CSV incompatible, tamaños y enlaces simbólicos',
    () {
      for (final name in ['bad.zip', 'audio.mp3', 'empty.csv']) {
        expect(
          () => parser.parse(name, encoded('bad data')),
          throwsA(isA<TakeoutFailure>()),
        );
      }
      expect(
        () => parser.parse(
          'big.csv',
          Uint8List(TakeoutParser.maximumFileBytes + 1),
        ),
        throwsA(isA<TakeoutFailure>()),
      );
      final archive = Archive()
        ..add(ArchiveFile.symlink('link', '/etc/passwd'));
      expect(
        () => parser.parse(
          'link.zip',
          Uint8List.fromList(ZipEncoder().encode(archive)),
        ),
        throwsA(isA<TakeoutFailure>()),
      );
    },
  );
}
