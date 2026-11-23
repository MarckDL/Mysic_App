import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/playback/presentation/artwork_prefetch.dart';

void main() {
  List<String?> covers(int count) => [
    for (var i = 0; i < count; i++) 'https://img/$i',
  ];

  test(
    'precarga la portada que suena y cinco a cada lado, de cerca a lejos',
    () {
      final urls = ArtworkPrefetch.urlsAround(covers(20), 10);
      expect(urls, [
        'https://img/10',
        'https://img/11',
        'https://img/9',
        'https://img/12',
        'https://img/8',
        'https://img/13',
        'https://img/7',
        'https://img/14',
        'https://img/6',
        'https://img/15',
        'https://img/5',
      ]);
      // Ni la sexta de cada lado.
      expect(urls, isNot(contains('https://img/16')));
      expect(urls, isNot(contains('https://img/4')));
    },
  );

  test('en los bordes de la cola solo toma lo que hay', () {
    expect(ArtworkPrefetch.urlsAround(covers(3), 0), [
      'https://img/0',
      'https://img/1',
      'https://img/2',
    ]);
    expect(ArtworkPrefetch.urlsAround(covers(3), -1), isEmpty);
    expect(ArtworkPrefetch.urlsAround(const [], 0), isEmpty);
  });

  test(
    'salta las canciones sin portada y no repite una portada compartida',
    () {
      expect(
        ArtworkPrefetch.urlsAround([
          'https://img/a',
          null,
          'https://img/a',
          '',
          'https://img/b',
        ], 2),
        ['https://img/a', 'https://img/b'],
      );
    },
  );
}
