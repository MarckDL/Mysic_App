import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/ytm/data/ytm_parser.dart';

Map<String, dynamic> _runs(List<Map<String, dynamic>> runs) => {'runs': runs};

Map<String, dynamic> _text(String text) => _runs([
  {'text': text},
]);

Map<String, dynamic> _browse(String id, String type) => {
  'browseEndpoint': {
    'browseId': id,
    'browseEndpointContextSupportedConfigs': {
      'browseEndpointContextMusicConfig': {'pageType': type},
    },
  },
};

Map<String, dynamic> _watch(String id, String type) => {
  'watchEndpoint': {
    'videoId': id,
    'watchEndpointMusicSupportedConfigs': {
      'watchEndpointMusicConfig': {'musicVideoType': type},
    },
  },
};

Map<String, dynamic> _column(List<Map<String, dynamic>> runs) => {
  'musicResponsiveListItemFlexColumnRenderer': {'text': _runs(runs)},
};

const _artist = 'UCaaaaaaaaaaaaaaaaaaaaaa';

/// Una fila de canción o de vídeo, como las de `search`.
Map<String, dynamic> _trackRow(String id, String title, String type) => {
  'musicResponsiveListItemRenderer': {
    'flexColumns': [
      _column([
        {'text': title, 'navigationEndpoint': _watch(id, type)},
      ]),
      _column([
        {'text': type.endsWith('ATV') ? 'Canción' : 'Vídeo'},
        {'text': ' • '},
        {
          'text': 'Daft Punk',
          'navigationEndpoint': _browse(_artist, 'MUSIC_PAGE_TYPE_ARTIST'),
        },
        {'text': ' • '},
        {'text': '3:45'},
      ]),
    ],
  },
};

Map<String, dynamic> _linkRow(
  String id,
  String type,
  String title,
  String line,
) => {
  'musicResponsiveListItemRenderer': {
    'navigationEndpoint': _browse(id, type),
    'flexColumns': [
      _column([
        {'text': title},
      ]),
      _column([
        {'text': line},
      ]),
    ],
  },
};

Map<String, dynamic> _page(List<Map<String, dynamic>> sections) => {
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {'contents': sections},
            },
          },
        },
      ],
    },
  },
};

void main() {
  test('la búsqueda general separa el resultado principal y cada tipo', () {
    final page = parseYtmSearch(
      _page([
        {
          'musicCardShelfRenderer': {
            'title': _runs([
              {
                'text': 'Daft Punk',
                'navigationEndpoint': _browse(
                  _artist,
                  'MUSIC_PAGE_TYPE_ARTIST',
                ),
              },
            ]),
            'subtitle': _text('Artista • 20 M de oyentes mensuales'),
            'contents': [
              _trackRow(
                'aaaaaaaaaaa',
                'Around the World',
                'MUSIC_VIDEO_TYPE_ATV',
              ),
            ],
          },
        },
        {
          'musicShelfRenderer': {
            'title': _text('Canciones'),
            'contents': [
              _trackRow('bbbbbbbbbbb', 'One More Time', 'MUSIC_VIDEO_TYPE_ATV'),
              _trackRow(
                'ccccccccccc',
                'Da Funk (Vídeo)',
                'MUSIC_VIDEO_TYPE_OMV',
              ),
            ],
          },
        },
        {
          'musicShelfRenderer': {
            'title': _text('Álbumes'),
            'contents': [
              _linkRow(
                'MPREb_aaaaaaaa',
                'MUSIC_PAGE_TYPE_ALBUM',
                'Discovery',
                'Álbum • Daft Punk • 2001',
              ),
              _linkRow(
                _artist,
                'MUSIC_PAGE_TYPE_ARTIST',
                'Daft Punk',
                'Artista • 20 M de oyentes',
              ),
              _linkRow(
                'VLPLaaaaaaaaaa',
                'MUSIC_PAGE_TYPE_PLAYLIST',
                'Lo mejor de Daft Punk',
                'Playlist • YouTube Music',
              ),
            ],
          },
        },
      ]),
    );
    expect(page.top, containsPair('kind', 'artist'));
    expect(page.top, containsPair('id', _artist));
    // La línea del principal se enseña entera; la de las filas, sin el tipo.
    expect(page.topSubtitle, 'Artista • 20 M de oyentes mensuales');
    expect(page.topSongs.map((s) => s['id']), ['aaaaaaaaaaa']);
    // Una canción emparejada que solo trae tipo y duración toma el artista
    // del resultado principal, no la duración.
    final bare = parseYtmSearch(
      _page([
        {
          'musicCardShelfRenderer': {
            'title': _runs([
              {
                'text': 'Daft Punk',
                'navigationEndpoint': _browse(
                  _artist,
                  'MUSIC_PAGE_TYPE_ARTIST',
                ),
              },
            ]),
            'contents': [
              {
                'musicResponsiveListItemRenderer': {
                  'flexColumns': [
                    _column([
                      {
                        'text': 'Aerodynamic',
                        'navigationEndpoint': _watch(
                          'ddddddddddd',
                          'MUSIC_VIDEO_TYPE_ATV',
                        ),
                      },
                    ]),
                    _column([
                      {'text': 'Canción • 3:27'},
                    ]),
                  ],
                },
              },
            ],
          },
        },
      ]),
    );
    expect(bare.topSongs.single, containsPair('artist', 'Daft Punk'));
    expect(page.items.map((i) => i['kind']), [
      'track',
      'track',
      'album',
      'artist',
      'playlist',
    ]);
    expect(page.items[0], containsPair('artist', 'Daft Punk'));
    expect(page.items[0].containsKey('video'), isFalse);
    expect(page.items[1], containsPair('video', true));
    expect(page.items[2], containsPair('subtitle', 'Daft Punk • 2001'));
    expect(page.items[3], containsPair('subtitle', '20 M de oyentes'));
    expect(page.items[4], containsPair('id', 'PLaaaaaaaaaa'));
  });

  test('las sugerencias traen consultas y elementos directos', () {
    final page = parseYtmSuggestions({
      'contents': [
        {
          'searchSuggestionsSectionRenderer': {
            'contents': [
              {
                'searchSuggestionRenderer': {
                  'suggestion': _runs([
                    {'text': 'daft', 'bold': true},
                    {'text': ' punk'},
                  ]),
                },
              },
              {
                'searchSuggestionRenderer': {
                  'suggestion': _text('daft punk discovery'),
                },
              },
            ],
          },
        },
        {
          'searchSuggestionsSectionRenderer': {
            'contents': [
              _linkRow(
                _artist,
                'MUSIC_PAGE_TYPE_ARTIST',
                'Daft Punk',
                'Artista',
              ),
            ],
          },
        },
      ],
    });
    expect(page.queries, ['daft punk', 'daft punk discovery']);
    expect(page.items.single, containsPair('kind', 'artist'));
  });

  test('ambientes y géneros conservan sección, clave y color', () {
    Map<String, dynamic> button(String title, String params, int color) => {
      'musicNavigationButtonRenderer': {
        'buttonText': _text(title),
        'solid': {'leftStripeColor': color},
        'clickCommand': {
          'browseEndpoint': {
            'browseId': 'FEmusic_moods_and_genres_category',
            'params': params,
          },
        },
      },
    };

    final sections = parseYtmMoods({
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'gridRenderer': {
                          'header': {
                            'gridHeaderRenderer': {
                              'title': _text('Ambientes y momentos'),
                            },
                          },
                          'items': [
                            button('Relax', 'ggMPOg1uX1', 4281545523),
                            // Sin clave no se puede abrir: se descarta.
                            button('Roto', '', 0),
                          ],
                        },
                      },
                      {
                        'gridRenderer': {
                          'header': {
                            'gridHeaderRenderer': {'title': _text('Géneros')},
                          },
                          'items': [button('Rock', 'ggMPOg1uX2', 4291559424)],
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    });
    expect(sections.map((s) => s['title']), [
      'Ambientes y momentos',
      'Géneros',
    ]);
    expect(sections.first['items'], [
      {'title': 'Relax', 'params': 'ggMPOg1uX1', 'color': 4281545523},
    ]);
  });

  test('la página de un género agrupa sus playlists por sección', () {
    final page = parseYtmPage({
      'header': {
        'musicHeaderRenderer': {'title': _text('Rock')},
      },
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'gridRenderer': {
                          'header': {
                            'gridHeaderRenderer': {
                              'title': _text('Playlists destacadas'),
                            },
                          },
                          'items': [
                            {
                              'musicTwoRowItemRenderer': {
                                'title': _text('Rock clásico'),
                                'navigationEndpoint': _browse(
                                  'VLPLbbbbbbbbbb',
                                  'MUSIC_PAGE_TYPE_PLAYLIST',
                                ),
                              },
                            },
                          ],
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    }, 'mood');
    expect(page.title, 'Rock');
    expect(page.items.single, containsPair('kind', 'playlist'));
    expect(page.items.single, containsPair('id', 'PLbbbbbbbbbb'));
    expect(
      page.items.single,
      containsPair('shelfTitle', 'Playlists destacadas'),
    );
  });
}
