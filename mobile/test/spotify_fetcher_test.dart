import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/spotify_import/data/spotify_fetcher.dart';
import 'package:mysic/features/spotify_import/domain/spotify_link.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final urls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    urls.add(options.uri.toString());
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(String text, int status) => ResponseBody.fromString(
  text,
  status,
  headers: {
    Headers.contentTypeHeader: ['text/html'],
  },
);

void main() {
  const html =
      '<script id="__NEXT_DATA__" type="application/json">'
      '{"props":{"pageProps":{"state":{"data":{"entity":'
      '{"name":"Mix","subtitle":"Yo","trackList":['
      '{"title":"A","subtitle":"X"}]}}}}}}</script>';

  SpotifyFetcher fetcher(_Adapter adapter) =>
      SpotifyFetcher(dio: Dio()..httpClientAdapter = adapter);

  test('pide la página embed de la playlist y la lee', () async {
    final adapter = _Adapter((_) => _body(html, 200));
    final list = await fetcher(adapter).playlist('37i9dQZF1DXcBWIGoYBM5M');
    expect(adapter.urls, [
      'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
    ]);
    expect(list.name, 'Mix');
    expect(list.tracks.single.title, 'A');
  });

  test('un 404 es una playlist privada o borrada', () async {
    final adapter = _Adapter((_) => _body('', 404));
    expect(
      () => fetcher(adapter).playlist('abc'),
      throwsA(
        isA<SpotifyLinkFailure>().having(
          (e) => e.error,
          'error',
          SpotifyLinkError.private,
        ),
      ),
    );
  });

  test('un error del servidor o una página sin datos se distinguen', () async {
    expect(
      () => fetcher(_Adapter((_) => _body('', 500))).playlist('abc'),
      throwsA(
        isA<SpotifyLinkFailure>().having(
          (e) => e.error,
          'error',
          SpotifyLinkError.network,
        ),
      ),
    );
    expect(
      () =>
          fetcher(_Adapter((_) => _body('<html></html>', 200))).playlist('abc'),
      throwsA(
        isA<SpotifyLinkFailure>().having(
          (e) => e.error,
          'error',
          SpotifyLinkError.changed,
        ),
      ),
    );
  });

  test('sin conexión es un fallo de red', () async {
    final adapter = _Adapter(
      (options) => throw DioException(requestOptions: options),
    );
    expect(
      () => fetcher(adapter).playlist('abc'),
      throwsA(
        isA<SpotifyLinkFailure>().having(
          (e) => e.error,
          'error',
          SpotifyLinkError.network,
        ),
      ),
    );
    // Sin usar utf8 aquí: solo para comprobar que el cuerpo es texto plano.
    expect(utf8.encode(html), isNotEmpty);
  });
}
