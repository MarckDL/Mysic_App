import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/api_failure.dart';
import 'package:mysic/features/connected_library/data/public_catalog_client.dart';

const _song = {
  'id': 'krJBZm2OMYE',
  'title': 'Again',
  'artist': 'Yui',
  'artistId': 'UCQusk8SoK8918LF19XBrlUQ',
  'durationSeconds': 200,
};

PublicCatalogClient client(
  void Function(RequestOptions) onRequest, {
  Map<String, dynamic>? data,
  int status = 200,
  bool Function()? owns,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (req, handler) {
        onRequest(req);
        handler.resolve(
          Response(
            requestOptions: req,
            statusCode: status,
            data:
                data ??
                {
                  'type': 'song',
                  'items': [_song],
                },
          ),
        );
      },
    ),
  );
  final value = PublicCatalogClient(owns ?? () => true, dio: dio);
  addTearDown(value.close);
  return value;
}

void main() {
  test('la búsqueda pública no envía ninguna credencial', () async {
    final seen = <RequestOptions>[];
    final catalog = client(seen.add);
    final page = await catalog.publicSongs('again', null);
    expect(page.items.single.title, 'Again');
    final request = seen.single;
    expect(request.uri.origin, 'https://myslc.duckdns.org');
    expect(request.queryParameters, {'q': 'again', 'type': 'song'});
    final headers = request.headers.keys.map((key) => key.toLowerCase());
    expect(headers, isNot(contains('cookie')));
    expect(headers, isNot(contains('authorization')));
  });

  test('un tipo que no corresponde se rechaza como catálogo no disponible', () {
    final catalog = client((_) {}, data: {'type': 'album', 'items': []});
    expect(
      catalog.publicSongs('x', null),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.code,
          'code',
          'MUSIC_SEARCH_UNAVAILABLE',
        ),
      ),
    );
  });

  test('los errores del servidor salen con su código', () {
    expect(
      client((_) {}, status: 429, data: {}).publicSongs('x', null),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'TOO_MANY_REQUESTS'),
      ),
    );
    expect(
      client((_) {}, status: 404, data: {}).publicSongs('x', null),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'CATALOG_ROUTE')),
    );
  });

  test('sin dueño vigente no hace ninguna petición', () {
    var requests = 0;
    final catalog = client((_) => requests++, owns: () => false);
    expect(catalog.publicSongs('x', null), throwsA(isA<ApiFailure>()));
    expect(requests, 0);
  });

  test('rechaza identificadores de artista y álbum que no son de YouTube', () {
    final catalog = client((_) {});
    expect(catalog.artistPage('../x'), throwsA(isA<ApiFailure>()));
    expect(catalog.albumPage('../x'), throwsA(isA<ApiFailure>()));
    expect(catalog.artistSongs('../x'), throwsA(isA<ApiFailure>()));
    expect(catalog.artistReleases('../x'), throwsA(isA<ApiFailure>()));
  });

  test('el «Ver todo» pide las rutas completas, sin credenciales', () async {
    final seen = <RequestOptions>[];
    const id = 'UCqHFrpXP6pnjnElQpHKyO_Q';
    final songs = await client(
      seen.add,
      data: {
        'songs': [_song],
      },
    ).artistSongs(id);
    expect(songs.single.title, 'Again');
    expect(seen.last.uri.path, '/api/youtube/artist/$id/songs');

    final releases = await client(
      seen.add,
      data: {
        'shelves': [
          {
            'title': 'Albums',
            'items': [
              {'id': 'MPREb_d1UkStdzUrN', 'title': 'Disco'},
            ],
          },
        ],
      },
    ).artistReleases(id);
    expect(releases.single.title, 'Álbumes');
    expect(seen.last.uri.path, '/api/youtube/artist/$id/releases');
    for (final request in seen) {
      expect(request.uri.origin, 'https://myslc.duckdns.org');
      final headers = request.headers.keys.map((k) => k.toLowerCase());
      expect(headers, isNot(contains('cookie')));
      expect(headers, isNot(contains('authorization')));
    }
  });
}
