import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/lyrics/data/lyrics_repository.dart';
import 'package:mysic/features/lyrics/data/lyrics_sources.dart';
import 'package:mysic/features/lyrics/domain/lyrics_provider.dart';
import 'package:mysic/features/lyrics/domain/ttml.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';

/// TTML recortado de una respuesta real de Better Lyrics: palabras con espacio
/// entre `<span>`, sílabas pegadas y una voz de fondo que no debe contarse.
const _ttml =
    '<tt xmlns="http://www.w3.org/ns/ttml"><body dur="3:20.046"><div>'
    '<p begin="27.395" end="28.960" ttm:agent="v1">'
    '<span begin="27.395" end="27.549">I</span> '
    '<span begin="27.549" end="27.740">been</span> '
    '<span begin="27.740" end="28.077">tryna</span> '
    '<span begin="28.077" end="28.960">call</span></p>'
    '<p begin="30.189" end="32.529">'
    '<span begin="30.189" end="30.396">I&apos;ve</span> '
    '<span begin="31.839" end="31.996">e</span>'
    '<span begin="31.996" end="32.529">nough</span>'
    '<span ttm:role="x-bg"><span begin="32.000" end="32.400">(oh)</span></span>'
    '</p>'
    '<p begin="1:02.500" end="1:05.000">Sin palabras</p>'
    '</div></body></tt>';

CatalogTrack track({int? seconds = 200}) => CatalogTrack(
  id: 'youtube:AbC01234567',
  title: 'Blinding Lights (Official Video) | Visualizer',
  artistName: 'The Weeknd',
  durationSeconds: seconds,
);

class _Fake implements LyricsSource {
  _Fake(this.label, this.run, {this.delay = Duration.zero});

  @override
  final String label;
  final Future<SongLyrics?> Function() run;
  final Duration delay;
  int calls = 0;

  @override
  Future<SongLyrics?> fetch(
    LyricsQuery query, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    await Future<void>.delayed(delay);
    return run();
  }
}

SongLyrics lineSynced() => SongLyrics.fromLrc(synced: '[00:01.00]hola')!;
SongLyrics wordSynced() =>
    SongLyrics.fromLrc(synced: '[00:01.00]<00:01.00>hola <00:01.50>mundo')!;
SongLyrics plain() => SongLyrics.fromLrc(plain: 'solo texto')!;

Dio fakeDio(Map<String, Object? Function(RequestOptions)> routes) {
  final dio = Dio(
    BaseOptions(validateStatus: (status) => status != null && status < 500),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        final reply = routes[request.path];
        if (reply == null) {
          handler.reject(DioException(requestOptions: request));
          return;
        }
        final body = reply(request);
        handler.resolve(
          Response(
            requestOptions: request,
            statusCode: body == null ? 404 : 200,
            data: body,
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  group('título de búsqueda', () {
    test('quita sufijos entre paréntesis y lo que va tras la barra', () {
      expect(
        LyricsQuery.searchTitle(
          'Blinding Lights (Official Video) | Visualizer',
        ),
        'Blinding Lights',
      );
      expect(
        LyricsQuery.searchTitle('Canción [Remaster 2011] （live）'),
        'Canción',
      );
      // Si no queda nada, se conserva el título original.
      expect(LyricsQuery.searchTitle('(Intro)'), '(Intro)');
    });
  });

  group('TTML', () {
    test(
      'lee palabras, une sílabas, ignora la voz de fondo y entiende m:ss',
      () {
        final lyrics = TtmlLyrics.parse(_ttml)!;
        expect(lyrics.lines, hasLength(3));
        final first = lyrics.lines[0];
        expect(first.text, 'I been tryna call');
        expect(first.words.map((word) => word.text), [
          'I ',
          'been ',
          'tryna ',
          'call',
        ]);
        expect(first.start, const Duration(milliseconds: 27395));
        final second = lyrics.lines[1];
        // "e" + "nough" son una palabra; el "(oh)" de fondo no aparece.
        expect(second.text, "I've enough");
        expect(second.words.map((word) => word.text), ["I've ", 'e', 'nough']);
        expect(lyrics.lines[2].start, const Duration(milliseconds: 62500));
        expect(lyrics.lines[2].hasWords, isFalse);
        expect(lyrics.hasWordSync, isTrue);
      },
    );

    test('un texto que no es TTML no produce letra', () {
      expect(TtmlLyrics.parse('<html>nada</html>'), isNull);
      expect(TtmlLyrics.parse(''), isNull);
    });
  });

  group('LRCLIB', () {
    test('usa la coincidencia exacta si existe', () async {
      final source = LrclibSource(
        dio: fakeDio({
          '/api/get': (_) => {'syncedLyrics': '[00:01.00]exacta'},
        }),
      );
      final lyrics = await source.fetch(LyricsQuery.of(track()));
      expect(lyrics!.lines.single.text, 'exacta');
    });

    test(
      'sin exacta, elige la sincronizada de duración más cercana y ≤ 5 s',
      () async {
        final source = LrclibSource(
          dio: fakeDio({
            '/api/get': (_) => null,
            '/api/search': (_) => [
              {'duration': 263.0, 'syncedLyrics': '[00:01.00]lejana'},
              {'duration': 203.0, 'syncedLyrics': '[00:01.00]cercana'},
              {'duration': 201.0, 'plainLyrics': 'solo texto'},
              {'duration': 400.0, 'instrumental': true},
            ],
          }),
        );
        final lyrics = await source.fetch(LyricsQuery.of(track()));
        expect(lyrics!.lines.single.text, 'cercana');
      },
    );

    test('si ninguna cabe en la tolerancia, no hay letra', () async {
      final source = LrclibSource(
        dio: fakeDio({
          '/api/get': (_) => null,
          '/api/search': (_) => [
            {'duration': 263.0, 'syncedLyrics': '[00:01.00]lejana'},
          ],
        }),
      );
      expect(await source.fetch(LyricsQuery.of(track())), isNull);
    });
  });

  group('Boidu', () {
    test('lee el TTML con palabras', () async {
      final source = BoiduSource(
        dio: fakeDio({
          '/getLyrics': (request) {
            // Pide la duración y el título ya limpio.
            expect(request.queryParameters['d'], 200);
            expect(request.queryParameters['s'], 'Blinding Lights');
            return {'ttml': _ttml};
          },
        }),
      );
      final lyrics = await source.fetch(LyricsQuery.of(track()));
      expect(lyrics!.hasWordSync, isTrue);
    });

    test('sin duración conocida no consulta', () async {
      final source = BoiduSource(dio: fakeDio({}));
      expect(await source.fetch(LyricsQuery.of(track(seconds: null))), isNull);
    });
  });

  group('repositorio', () {
    test('gana la letra palabra a palabra aunque otra llegue antes', () async {
      final line = _Fake('línea', () async => lineSynced());
      final words = _Fake(
        'palabras',
        () async => wordSynced(),
        delay: const Duration(milliseconds: 40),
      );
      final repo = LyricsRepository([line, words]);
      final lyrics = await repo.fetch(track());
      expect(lyrics!.source, 'palabras');
      expect(lyrics.hasWordSync, isTrue);
    });

    test('entre sincronizadas, manda el orden de preferencia', () async {
      final first = _Fake('primera', () async => lineSynced());
      final second = _Fake('segunda', () async => lineSynced());
      final lyrics = await LyricsRepository([first, second]).fetch(track());
      expect(lyrics!.source, 'primera');
    });

    test('prefiere la sincronizada al texto plano', () async {
      final repo = LyricsRepository([
        _Fake('plana', () async => plain()),
        _Fake('sincronizada', () async => lineSynced()),
      ]);
      expect((await repo.fetch(track()))!.source, 'sincronizada');
    });

    test('si solo hay texto plano, lo entrega', () async {
      final repo = LyricsRepository([
        _Fake('nada', () async => null),
        _Fake('plana', () async => plain()),
      ]);
      expect((await repo.fetch(track()))!.plain, 'solo texto');
    });

    test('una fuente que falla no impide usar las demás', () async {
      final repo = LyricsRepository([
        _Fake('rota', () async => throw StateError('caída')),
        _Fake('buena', () async => lineSynced()),
      ]);
      expect((await repo.fetch(track()))!.source, 'buena');
    });

    test('si todas fallan es un error, no "no hay letra"', () async {
      final repo = LyricsRepository([
        _Fake('a', () async => throw StateError('x')),
        _Fake('b', () async => throw StateError('y')),
      ]);
      await expectLater(repo.fetch(track()), throwsA(isA<Object>()));
    });

    test('si ninguna la tiene, devuelve null y no es un error', () async {
      final repo = LyricsRepository([
        _Fake('a', () async => null),
        _Fake('b', () async => null),
      ]);
      expect(await repo.fetch(track()), isNull);
    });

    test('la misma canción se pide una sola vez', () async {
      final source = _Fake('única', () async => lineSynced());
      final repo = LyricsRepository([source]);
      await repo.fetch(track());
      await repo.fetch(track());
      expect(source.calls, 1);
    });
  });
}
