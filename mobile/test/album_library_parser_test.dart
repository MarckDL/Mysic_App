import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/ytm/data/ytm_parser.dart';

Map<String, dynamic> _album({required bool saved, bool button = true}) => {
  'contents': {
    'twoColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicResponsiveHeaderRenderer': {
                      'buttons': [
                        if (button)
                          {
                            'toggleButtonRenderer': {
                              'isToggled': saved,
                              'defaultServiceEndpoint': {
                                'likeEndpoint': {
                                  'status': 'LIKE',
                                  'target': {'playlistId': 'OLAK5uy_aaaaaa'},
                                },
                              },
                              'toggledServiceEndpoint': {
                                'likeEndpoint': {
                                  'status': 'INDIFFERENT',
                                  'target': {'playlistId': 'OLAK5uy_aaaaaa'},
                                },
                              },
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
  'microformat': {
    'microformatDataRenderer': {
      'urlCanonical': 'https://music.youtube.com/playlist?list=OLAK5uy_bbbbbb',
    },
  },
};

void main() {
  test('lee la playlist de audio y si el álbum está guardado', () {
    final off = parseYtmAlbumLibrary(_album(saved: false));
    expect(off.playlistId, 'OLAK5uy_aaaaaa');
    expect(off.saved, isFalse);
    expect(parseYtmAlbumLibrary(_album(saved: true)).saved, isTrue);
  });

  test('sin botón, la playlist sale del enlace canónico', () {
    final found = parseYtmAlbumLibrary(_album(saved: false, button: false));
    expect(found.playlistId, 'OLAK5uy_bbbbbb');
    expect(found.saved, isFalse);
  });
}
