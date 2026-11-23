import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/downloads/data/download_store.dart';
import 'package:mysic/features/downloads/domain/download_sort.dart';

DownloadedTrack _track(
  String id,
  int savedAt, {
  String title = 't',
  String artist = 'a',
  String? album,
}) => DownloadedTrack(
  id: id.padRight(11, 'x'),
  title: title,
  artist: artist,
  bytes: 1,
  savedAt: savedAt,
  albumName: album,
);

List<String> _ids(List<DownloadedTrack> list) => [
  for (final track in list) track.id.replaceAll('x', ''),
];

void main() {
  final tracks = [
    _track('a', 1, title: 'Track 10', artist: 'Zoe', album: 'Beta'),
    _track('b', 2, title: 'track 2', artist: 'Ánima', album: 'alfa'),
    _track('c', 3, title: 'Éxtasis', artist: 'Bruno'),
    _track('d', 4, title: 'Bonus', artist: 'Ánima', album: 'Beta'),
    _track('e', 5, title: 'Aire', artist: 'Carla', album: 'Alfa'),
  ];

  test('el predeterminado va de la más reciente a la más antigua', () {
    expect(_ids(DownloadSort.initial.apply(tracks)), ['e', 'd', 'c', 'b', 'a']);
    expect(
      _ids(
        const DownloadSort(DownloadSortKey.recent, desc: true).apply(tracks),
      ),
      ['a', 'b', 'c', 'd', 'e'],
    );
  });

  test('por álbum agrupa, sin tildes ni mayúsculas, y sin álbum al final', () {
    const sort = DownloadSort(DownloadSortKey.album);
    // Dentro de cada álbum se conserva el orden de descarga.
    expect(_ids(sort.apply(tracks)), ['e', 'b', 'd', 'a', 'c']);
    expect(_ids(sort.copyWith(desc: true).apply(tracks)), [
      'd',
      'a',
      'e',
      'b',
      'c',
    ]);
  });

  test('por título compara los números por su valor', () {
    const sort = DownloadSort(DownloadSortKey.title);
    expect(_ids(sort.apply(tracks)), ['e', 'd', 'c', 'b', 'a']);
  });

  test('por artista ignora las tildes', () {
    const sort = DownloadSort(DownloadSortKey.artist);
    expect(_ids(sort.apply(tracks)), ['d', 'b', 'c', 'e', 'a']);
  });

  test('se guarda y se lee como en Limusic', () {
    const sort = DownloadSort(DownloadSortKey.album, desc: true);
    expect(sort.encode(), 'album:desc');
    expect(DownloadSort.decode('album:desc'), sort);
    expect(
      DownloadSort.decode('title'),
      const DownloadSort(DownloadSortKey.title),
    );
    expect(DownloadSort.decode('nada'), DownloadSort.initial);
    expect(DownloadSort.decode(null), DownloadSort.initial);
  });
}
