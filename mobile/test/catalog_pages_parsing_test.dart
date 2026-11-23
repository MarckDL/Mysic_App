import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/data/public_catalog_client.dart';
import 'package:mysic/features/connected_library/data/original_music_catalog.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

void main() {
  const cover = 'https://yt3.googleusercontent.com/portada=w544-h544-l90-rj';

  test('la página de artista conserva destacadas, discografía y audiencia', () {
    final artist = OriginalMusicCatalog.artistProfile({
      'id': 'UCZU9T1ceaOgwfLRq7OKFU4Q',
      'name': 'Artista de prueba',
      'subtitle': '422 subscribers',
      'description': 'Biografía.',
      'thumbnail': cover,
      'topSongs': [
        {
          'id': 'BLZWkjBXfN8',
          'title': 'Canción',
          'artist': 'Artista de prueba',
          'artistId': 'UCxgN32UVVztKAQd2HkXzBtw',
          'albumId': 'MPREb_m10OjDmOhfv',
          'durationSeconds': 0,
          'thumbnail': cover,
        },
        // Sin id de vídeo válido: se descarta sin romper la página.
        {'id': 'corto', 'title': 'Rota'},
      ],
      'shelves': [
        {
          'title': 'Albums',
          'items': [
            {
              'id': 'MPREb_d1UkStdzUrN',
              'title': 'Disco',
              'year': '2024',
              'kind': 'Álbum',
              'thumbnail': cover,
            },
          ],
        },
        {'title': 'Vacío', 'items': []},
      ],
    });

    expect(artist.name, 'Artista de prueba');
    expect(artist.audience, '422 suscriptores');
    expect(artist.thumbnailUrl, cover);
    expect(artist.topSongs, hasLength(1));
    expect(artist.topSongs.single.albumId, 'MPREb_m10OjDmOhfv');
    expect(artist.topSongs.single.artistId, 'UCxgN32UVVztKAQd2HkXzBtw');
    // Los enlaces viajan hasta la pista que usa el reproductor.
    final playing = artist.topSongs.single.toPlaybackTrack();
    expect(playing.albumId, 'MPREb_m10OjDmOhfv');
    expect(playing.artistId, 'UCxgN32UVVztKAQd2HkXzBtw');
    expect(artist.shelves, hasLength(1));
    final album = artist.shelves.single.items.single as MusicAlbum;
    expect(album.title, 'Disco');
    expect(album.detail, 'Álbum · 2024');
  });

  test('los textos en inglés de YouTube se muestran en español', () {
    expect(OriginalMusicCatalog.shelfTitle('Albums'), 'Álbumes');
    expect(OriginalMusicCatalog.shelfTitle('Singles & EPs'), 'Sencillos y EP');
    // Un título desconocido se deja tal cual.
    expect(
      OriginalMusicCatalog.shelfTitle('Noches de verano'),
      'Noches de verano',
    );
    expect(OriginalMusicCatalog.releaseKind('Single'), 'Sencillo');
    expect(
      OriginalMusicCatalog.albumInfo('8 songs • 35 minutes'),
      '8 canciones • 35 minutos',
    );
    expect(
      OriginalMusicCatalog.albumInfo('1 song • 1 hour, 1 minute'),
      '1 canción • 1 hora, 1 minuto',
    );
  });

  test(
    'la página de álbum conserva el orden de pistas y enlaza al artista',
    () {
      final album = OriginalMusicCatalog.albumDetail({
        'id': 'MPREb_d1UkStdzUrN',
        'title': 'Disco',
        'artist': 'Artista de prueba',
        'artistId': 'UCxgN32UVVztKAQd2HkXzBtw',
        'year': '2024',
        'info': '2 songs • 5 minutes',
        'thumbnail': cover,
        'tracks': [
          {
            'id': 'ay32SqJPpB0',
            'title': 'Intro',
            'artist': 'Artista de prueba',
            'durationSeconds': 23,
            'index': 1,
          },
          {
            'id': 'BLZWkjBXfN8',
            'title': 'Segunda',
            'artist': 'Artista de prueba',
            'durationSeconds': 200,
            'index': 2,
          },
        ],
      });

      expect(album.title, 'Disco');
      expect(album.artistId, 'UCxgN32UVVztKAQd2HkXzBtw');
      expect(album.year, '2024');
      expect(album.tracks.map((track) => track.title), ['Intro', 'Segunda']);
      expect(album.tracks.first.durationSeconds, 23);
    },
  );

  test('un artista o álbum sin los campos mínimos se rechaza', () {
    expect(
      () => OriginalMusicCatalog.artistProfile({'id': 'UCx'}),
      throwsFormatException,
    );
    expect(
      () => OriginalMusicCatalog.albumDetail({'id': 'MPREb_x', 'title': 'D'}),
      throwsFormatException,
    );
    // Un id de artista que no es un canal no se usa como enlace.
    final album = OriginalMusicCatalog.albumDetail({
      'id': 'MPREb_d1UkStdzUrN',
      'title': 'Disco',
      'artistId': 'no-es-un-canal',
      'tracks': [],
    });
    expect(album.artistId, isNull);
    expect(OriginalMusicCatalog.isAlbumId('MPREb_d1UkStdzUrN'), isTrue);
    expect(OriginalMusicCatalog.isAlbumId('OLAK5uy_abc'), isFalse);
    expect(OriginalMusicCatalog.isArtistId('UCZU9T1ceaOgwfLRq7OKFU4Q'), isTrue);
  });

  Future<TrackLinks> resolve(
    List<Map<String, Object?>> rows, {
    String videoId = 'krJBZm2OMYE',
    String artist = 'Miho Nakayama',
  }) async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          // Búsqueda pública: nunca lleva credenciales.
          expect(request.uri.path, '/api/youtube/search');
          expect(request.queryParameters['type'], 'song');
          expect(request.queryParameters['q'], 'PRECIOUS LOVE $artist');
          expect(
            request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('cookie')),
          );
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {'type': 'song', 'items': rows},
            ),
          );
        },
      ),
    );
    final client = PublicCatalogClient(() => true, dio: dio);
    addTearDown(client.close);
    return client.resolveLinks(
      videoId: videoId,
      title: 'PRECIOUS LOVE',
      artist: artist,
    );
  }

  test('la canción exacta aporta artista y álbum', () async {
    final links = await resolve([
      {
        'id': 'otraCancion1',
        'artist': 'Keizo Nakanishi',
        'artistId': 'UCH3uTAEFOcPo4nIUKz454dg',
        'albumId': 'MPREb_GKwTKmGXPON',
      },
      {
        'id': 'krJBZm2OMYE',
        'artist': 'Miho Nakayama',
        'artistId': 'UCQusk8SoK8918LF19XBrlUQ',
        'album': ' Collection III ',
        'albumId': 'MPREb_6tRvUJBGmks',
      },
    ]);
    expect(links.artistId, 'UCQusk8SoK8918LF19XBrlUQ');
    expect(links.albumId, 'MPREb_6tRvUJBGmks');
    // El nombre del álbum acompaña al enlace, sin espacios sobrantes.
    expect(links.album, 'Collection III');
  });

  test(
    'sin la canción exacta solo se acepta el artista, nunca el álbum',
    () async {
      final links = await resolve([
        {
          'id': 'otraCancion1',
          'artist': 'Keizo Nakanishi',
          'artistId': 'UCH3uTAEFOcPo4nIUKz454dg',
          'albumId': 'MPREb_GKwTKmGXPON',
        },
        {
          'id': 'XkengMU9Eho',
          'artist': 'miho nakayama',
          'artistId': 'UCQusk8SoK8918LF19XBrlUQ',
          'albumId': 'MPREb_bsil1Ocrivu',
        },
      ]);
      // Un álbum de otra pista sería un enlace equivocado.
      expect(links.albumId, isNull);
      // El artista de otro intérprete tampoco se usa.
      expect(links.artistId, 'UCQusk8SoK8918LF19XBrlUQ');
    },
  );

  test(
    'ids con formato inválido o resultados vacíos no producen enlaces',
    () async {
      final bad = await resolve([
        {
          'id': 'krJBZm2OMYE',
          'artist': 'Miho Nakayama',
          'artistId': 'no-es-un-canal',
          'albumId': 'OLAK5uy_abc',
        },
      ]);
      expect(bad.artistId, isNull);
      expect(bad.albumId, isNull);
      final empty = await resolve(const []);
      expect(empty.artistId, isNull);
      expect(empty.albumId, isNull);
    },
  );
}
