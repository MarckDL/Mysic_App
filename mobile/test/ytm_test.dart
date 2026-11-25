import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/api_failure.dart';
import 'package:mysic/core/network/offline_mode.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/ytm/data/ytm_auth_repository.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_parser.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';

const _cookie = 'VISITOR=1; SAPISID=abc123/xyz; __Secure-3PAPISID=other; X=y';

Map<String, dynamic> _song(String id, String title) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://i.ytimg.com/small.jpg'},
            {'url': 'https://i.ytimg.com/big.jpg'},
          ],
        },
      },
    },
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {
                'text': title,
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
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {
                'text': 'Artista Uno',
                'navigationEndpoint': {
                  'browseEndpoint': {
                    'browseId': 'UC${'a' * 22}',
                    'browseEndpointContextSupportedConfigs': {
                      'browseEndpointContextMusicConfig': {
                        'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
                      },
                    },
                  },
                },
              },
              {
                'text': 'Disco Uno',
                'navigationEndpoint': {
                  'browseEndpoint': {
                    'browseId': 'MPREb_abcdefgh',
                    'browseEndpointContextSupportedConfigs': {
                      'browseEndpointContextMusicConfig': {
                        'pageType': 'MUSIC_PAGE_TYPE_ALBUM',
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
    'fixedColumns': [
      {
        'musicResponsiveListItemFixedColumnRenderer': {
          'text': {'simpleText': '3:25'},
        },
      },
    ],
  },
};

Map<String, dynamic> _home(List<Map<String, dynamic>> shelfItems) => {
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
                    'musicCarouselShelfRenderer': {
                      'header': {
                        'musicCarouselShelfBasicHeaderRenderer': {
                          'title': {
                            'runs': [
                              {'text': 'Vuelve a escucharlo'},
                            ],
                          },
                        },
                      },
                      'contents': shelfItems,
                    },
                  },
                ],
                'continuations': [
                  {
                    'nextContinuationData': {'continuation': 'TOKEN-2'},
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

void main() {
  test('el analizador lee canciones de un estante del Inicio', () {
    final page = parseYtmPage(
      _home([_song('aaaaaaaaaaa', 'Tema A'), _song('bbbbbbbbbbb', 'Tema B')]),
      'home',
    );
    expect(page.items, hasLength(2));
    final first = page.items.first;
    expect(first['kind'], 'track');
    expect(first['id'], 'aaaaaaaaaaa');
    expect(first['title'], 'Tema A');
    expect(first['artist'], 'Artista Uno');
    expect(first['artistId'], 'UC${'a' * 22}');
    expect(first['albumId'], 'MPREb_abcdefgh');
    expect(first['albumName'], 'Disco Uno');
    expect(first['durationSeconds'], 205);
    expect(first['thumbnailUrl'], 'https://i.ytimg.com/big.jpg');
    expect(first['shelfTitle'], 'Vuelve a escucharlo');
    expect(page.next, 'TOKEN-2');
    // El mismo JSON que entiende la app.
    final parsed = MusicPage.fromJson(page.toJson());
    expect(parsed.items.whereType<MusicTrack>().first.nativePlayback, isTrue);
    expect(parsed.nextCursor, 'TOKEN-2');
  });

  test('una respuesta sin sesión se rechaza como acceso denegado', () {
    final loggedOut = {
      'responseContext': {
        'serviceTrackingParams': [
          {
            'params': [
              {'key': 'logged_in', 'value': '0'},
            ],
          },
        ],
      },
    };
    expect(
      () => parseYtmPage(loggedOut, 'home'),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'MUSIC_ACCESS_DENIED'),
      ),
    );
  });

  test('un formato desconocido no se confunde con una lista vacía', () {
    expect(
      () => parseYtmPage({
        'responseContext': {
          'serviceTrackingParams': [
            {
              'params': [
                {'key': 'logged_in', 'value': '1'},
              ],
            },
          ],
        },
        'otraCosa': 1,
      }, 'home'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.code,
          'code',
          'MUSIC_CATALOG_RESPONSE',
        ),
      ),
    );
  });

  test('una continuación vacía es el final de la lista, no un error', () {
    final empty = {
      'responseContext': {
        'serviceTrackingParams': [
          {
            'params': [
              {'key': 'logged_in', 'value': '1'},
            ],
          },
        ],
      },
      'trackingParams': 'x',
    };
    final page = parseYtmPage(empty, 'playlist', continuation: true);
    expect(page.items, isEmpty);
    expect(page.next, isNull);
    // Sin ser continuación, la misma respuesta sí se rechaza.
    expect(() => parseYtmPage(empty, 'playlist'), throwsA(isA<ApiFailure>()));
  });

  test('la firma SAPISIDHASH es el SHA-1 de "tiempo SAPISID origen"', () {
    const session = YtmSession(_cookie);
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    final expected = sha1
        .convert(utf8.encode('1700000000 abc123/xyz https://music.youtube.com'))
        .toString();
    expect(
      session.authorization('https://music.youtube.com', now: now),
      'SAPISIDHASH 1700000000_$expected',
    );
  });

  test(
    'sin SAPISID la cookie no vale como sesión y el uid no es la cookie',
    () {
      expect(const YtmSession(_cookie).uid, hasLength(24));
      expect(const YtmSession(_cookie).uid, isNot(contains('abc123')));
      expect(const YtmSession('X=y').sapisid, isNull);
    },
  );

  group('repositorio de sesión', () {
    YtmAuthRepository repo({
      YtmSession? saved,
      YtmSession? loginResult,
      Future<YtmAccount> Function()? account,
      List<String>? log,
    }) => YtmAuthRepository(
      load: () async => saved,
      login: () async => loginResult,
      clear: () async => log?.add('clear'),
      cache: YtmAccountCache(
        path:
            '${Uri.file('${Object.hash(saved, loginResult)}').path}.none/ytm_account.json',
      ),
    );

    test('sin sesión guardada no hay usuario', () async {
      final r = repo();
      expect(await r.authStateChanges().first, isNull);
      r.dispose();
    });

    test('con sesión guardada hay usuario sin ir a la red', () async {
      final r = repo(saved: const YtmSession(_cookie));
      final user = await r.authStateChanges().first;
      expect(user, isNotNull);
      expect(user!.uid, const YtmSession(_cookie).uid);
      r.dispose();
    });

    test('con «solo canciones descargadas» activo no se verifica ni se cierra '
        'la sesión', () async {
      // Es lo que dejaba la app atascada: una sesión guardada, el modo sin
      // conexión encendido en el teléfono, y la comprobación fallando al
      // instante porque la petición ni sale.
      var requests = 0;
      final r = YtmAuthRepository(
        load: () async => const YtmSession(_cookie),
        login: () async => null,
        clear: () async {},
        clientFor: (session) {
          requests++;
          return YtmClient(session);
        },
        cache: YtmAccountCache(
          path: '${Uri.file('offline').path}.none/ytm_account.json',
        ),
      );
      OfflineMode.instance.manual = true;
      addTearDown(OfflineMode.instance.reset);

      await expectLater(
        r.verify(),
        throwsA(
          isA<AuthFailure>().having((e) => e.unreachable, 'unreachable', true),
        ),
      );
      expect(requests, 0, reason: 'no se intenta la red');
      expect(r.session, isNotNull, reason: 'la sesión sigue guardada');
      r.dispose();
    });

    test('cancelar el inicio de sesión se informa como cancelado', () async {
      final r = repo();
      await expectLater(
        r.signIn(),
        throwsA(
          isA<AuthFailure>().having((e) => e.cancelled, 'cancelled', true),
        ),
      );
      r.dispose();
    });

    test('cerrar sesión borra lo guardado y avisa', () async {
      final log = <String>[];
      final r = repo(saved: const YtmSession(_cookie), log: log);
      final states = <AuthUser?>[];
      final sub = r.authStateChanges().listen(states.add);
      await Future<void>.delayed(Duration.zero);
      await r.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(log, ['clear']);
      expect(states.last, isNull);
      expect(r.session, isNull);
      await sub.cancel();
      r.dispose();
    });
  });
}
