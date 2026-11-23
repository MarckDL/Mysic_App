import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/playback/data/widget_bridge.dart';
import 'package:mysic/features/ytm/data/liked_tracks.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';

Map<String, dynamic> _song(String id) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {
                'text': 'Tema $id',
                'navigationEndpoint': {
                  'watchEndpoint': {
                    'videoId': id,
                    'watchEndpointMusicSupportedConfigs': {
                      'watchEndpointMusicConfig': {
                        'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
                      },
                    },
                  },
                },
              },
            ],
          },
        },
      },
    ],
  },
};

Map<String, dynamic> _liked(List<String> ids) => {
  'responseContext': {
    'serviceTrackingParams': [
      {
        'params': [
          {'key': 'logged_in', 'value': '1'},
        ],
      },
    ],
  },
  'contents': {
    'singleColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'selected': true,
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicShelfRenderer': {'contents': ids.map(_song).toList()},
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

(YtmClient, List<String>) _client({int status = 200, List<String>? liked}) {
  final paths = <String>[];
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        paths.add(options.path);
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: status,
            data: options.path.contains('browse')
                ? _liked(liked ?? [])
                : <String, dynamic>{},
          ),
        );
      },
    ),
  );
  return (YtmClient(const YtmSession('SAPISID=t'), dio: dio), paths);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mysic_likes'));
  tearDown(() async {
    // Deja terminar el guardado en segundo plano antes de borrar la carpeta.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows puede retener el archivo un instante: es una carpeta temporal.
    }
  });

  test(
    'carga las canciones con Me gusta y las guarda en el teléfono',
    () async {
      final (client, _) = _client(liked: ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
      final likes = LikedTracks(client, path: '${dir.path}/liked.json');
      await likes.load();
      expect(likes.isLiked('aaaaaaaaaaa'), isTrue);
      expect(likes.isLiked('ccccccccccc'), isFalse);
      // Un arranque sin red abre con lo guardado.
      final offline = LikedTracks(
        _client(status: 500).$1,
        path: '${dir.path}/liked.json',
      );
      await offline.load();
      expect(offline.isLiked('bbbbbbbbbbb'), isTrue);
    },
  );

  test('marcar cambia al instante y se confirma en YouTube Music', () async {
    final (client, paths) = _client();
    final likes = LikedTracks(client, path: '${dir.path}/liked.json');
    var changes = 0;
    likes.addListener(() => changes++);
    final pending = likes.toggle('aaaaaaaaaaa');
    expect(likes.isLiked('aaaaaaaaaaa'), isTrue); // antes de la respuesta
    expect(await pending, isTrue);
    expect(paths.single, contains('like/like'));
    expect(changes, greaterThanOrEqualTo(1));
    expect(await likes.toggle('aaaaaaaaaaa'), isFalse);
    expect(paths.last, contains('like/removelike'));
  });

  test('si YouTube Music falla, el corazón se deshace', () async {
    final (client, _) = _client(status: 500);
    final likes = LikedTracks(client, path: '${dir.path}/liked.json');
    expect(await likes.toggle('aaaaaaaaaaa'), isFalse);
    expect(likes.isLiked('aaaaaaaaaaa'), isFalse);
  });

  test('el estado del widget se compara por valor', () {
    const a = WidgetState(has: true, title: 'x', liked: true);
    const b = WidgetState(has: true, title: 'x', liked: true);
    expect(a, b);
    expect(a == const WidgetState(has: true, title: 'x'), isFalse);
    expect(a.toMap()['liked'], isTrue);
  });
}
