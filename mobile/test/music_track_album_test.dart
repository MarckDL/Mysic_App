import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

Map<String, dynamic> track([Map<String, dynamic> extra = const {}]) => {
  'id': 'abcdefghijk',
  'title': 'Tema',
  'artist': 'Artista',
  'durationSeconds': 200,
  'playback': 'native',
  ...extra,
};

void main() {
  test('una canción con álbum lo lleva hasta el reproductor', () {
    final item = MusicTrack.fromJson(
      track({'albumId': 'MPREb_4U7yfKKFZLv', 'albumName': ' After Hours '}),
    );
    expect(item.albumId, 'MPREb_4U7yfKKFZLv');
    expect(item.albumName, 'After Hours');
    final playback = item.toPlaybackTrack();
    expect(playback.albumId, 'MPREb_4U7yfKKFZLv');
    expect(playback.albumName, 'After Hours');
  });

  test('sin álbum (servidor antiguo) la canción se lee igual', () {
    final item = MusicTrack.fromJson(track());
    expect(item.albumId, isNull);
    expect(item.albumName, isNull);
  });

  test(
    'un id de álbum que no es de YouTube Music se descarta con su nombre',
    () {
      final item = MusicTrack.fromJson(
        track({'albumId': '../otra-cosa', 'albumName': 'Nombre'}),
      );
      expect(item.albumId, isNull);
      // Un nombre sin álbum que abrir no se muestra como enlace.
      expect(item.albumName, isNull);
    },
  );

  test('un nombre vacío no cuenta como nombre', () {
    final item = MusicTrack.fromJson(
      track({'albumId': 'MPREb_4U7yfKKFZLv', 'albumName': '   '}),
    );
    expect(item.albumId, 'MPREb_4U7yfKKFZLv');
    expect(item.albumName, isNull);
  });
}
