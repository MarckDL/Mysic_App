import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/ytm/data/ytm_parser.dart';

Map<String, dynamic> _run(String text, {String? browseId, String? pageType}) =>
    {
      'text': text,
      if (browseId != null)
        'navigationEndpoint': {
          'browseEndpoint': {
            'browseId': browseId,
            if (pageType != null)
              'browseEndpointContextSupportedConfigs': {
                'browseEndpointContextMusicConfig': {'pageType': pageType},
              },
          },
        },
    };

Map<String, dynamic> _panel(
  String id,
  String title, {
  String length = '3:45',
  bool album = true,
}) => {
  'playlistPanelVideoRenderer': {
    'videoId': id,
    'title': {
      'runs': [
        {'text': title},
      ],
    },
    'longBylineText': {
      'runs': [
        _run(
          'Gustavo Cerati',
          browseId: 'UC${'a' * 22}',
          pageType: 'MUSIC_PAGE_TYPE_ARTIST',
        ),
        _run(' • '),
        if (album)
          _run(
            'Ahí vamos',
            browseId: 'MPREb_abcdefgh',
            pageType: 'MUSIC_PAGE_TYPE_ALBUM',
          ),
        if (album) _run(' • '),
        _run('2006'),
      ],
    },
    'lengthText': {
      'runs': [
        {'text': length},
      ],
    },
    'thumbnail': {
      'thumbnails': [
        {'url': 'https://lh3.googleusercontent.com/small'},
        {'url': 'https://lh3.googleusercontent.com/big'},
      ],
    },
  },
};

void main() {
  Map<String, dynamic> response(
    List<Map<String, dynamic>> items, {
    String? next,
  }) => {
    'contents': {
      'singleColumnMusicWatchNextResultsRenderer': {
        'tabbedRenderer': {
          'watchNextTabbedResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'musicQueueRenderer': {
                      'content': {
                        'playlistPanelRenderer': {
                          'contents': items,
                          if (next != null)
                            'continuations': [
                              {
                                'nextRadioContinuationData': {
                                  'continuation': next,
                                },
                              },
                            ],
                        },
                      },
                    },
                  },
                },
              },
            ],
          },
        },
      },
    },
  };

  test(
    'lee las canciones de la radio con artista, álbum, duración y portada',
    () {
      final page = parseYtmRadio(
        response([
          _panel('abcdefghijk', 'Crimen'),
          _panel('ABCDEFGHIJK', 'Sal', length: '1:02:03', album: false),
        ], next: 'cursor-1'),
      );
      expect(page.next, 'cursor-1');
      expect(page.tracks, hasLength(2));
      final first = MusicTrack.fromJson(page.tracks[0]);
      expect(first.id, 'abcdefghijk');
      expect(first.title, 'Crimen');
      expect(first.artist, 'Gustavo Cerati');
      expect(first.artistId, 'UC${'a' * 22}');
      expect(first.albumId, 'MPREb_abcdefgh');
      expect(first.albumName, 'Ahí vamos');
      expect(first.durationSeconds, 225);
      expect(first.thumbnailUrl, 'https://lh3.googleusercontent.com/big');
      expect(first.nativePlayback, isTrue);
      final second = MusicTrack.fromJson(page.tracks[1]);
      expect(second.durationSeconds, 3723);
      expect(second.albumId, isNull);
      // Se convierte en una pista reproducible de la cuenta.
      final playable = first.toPlaybackTrack();
      expect(playable.id, 'youtube:abcdefghijk');
      expect(playable.musicAccountTrack, isTrue);
    },
  );

  test('descarta ids inválidos, repetidos y filas sin título', () {
    final page = parseYtmRadio(
      response([
        _panel('abcdefghijk', 'Crimen'),
        _panel('abcdefghijk', 'Crimen otra vez'),
        _panel('corto', 'Id inválido'),
        _panel('12345678901', ''),
      ]),
    );
    expect(page.tracks.map((t) => t['id']), ['abcdefghijk']);
    expect(page.next, isNull);
  });

  test('encuentra las canciones aunque vengan dentro de un envoltorio', () {
    final wrapped = {
      'playlistPanelVideoWrapperRenderer': {
        'primaryRenderer': _panel('abcdefghijk', 'Crimen'),
      },
    };
    final page = parseYtmRadio(response([wrapped]));
    expect(page.tracks, hasLength(1));
  });

  test('una respuesta sin sesión pide iniciarla de nuevo', () {
    expect(
      () => parseYtmRadio({
        'responseContext': {
          'mainAppWebResponseContext': {'loggedOut': true},
        },
      }),
      throwsA(isA<Object>()),
    );
  });

  test('una respuesta vacía da una página vacía, no un error', () {
    final page = parseYtmRadio(<String, dynamic>{});
    expect(page.tracks, isEmpty);
    expect(page.next, isNull);
  });
}
