import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/spotify_import/application/spotify_import_controller.dart';
import 'package:mysic/features/spotify_import/domain/spotify_link.dart';
import 'package:mysic/features/spotify_import/domain/spotify_matching.dart';

MusicTrack _song(String id, String title, String artist) =>
    MusicTrack(id, title, artist, 200, false, null);

String _page(String entity) =>
    '<html><script id="__NEXT_DATA__" type="application/json">'
    '{"props":{"pageProps":{"state":{"data":{"entity":$entity}}}}}'
    '</script></html>';

void main() {
  group('enlaces de Spotify', () {
    test('se leen las formas que se pegan de verdad', () {
      for (final (input, kind, id) in [
        (
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc',
          'playlist',
          '37i9dQZF1DXcBWIGoYBM5M',
        ),
        (
          'open.spotify.com/intl-es/album/4aawyAB9vmqN3uQ7FjRGTy',
          'album',
          '4aawyAB9vmqN3uQ7FjRGTy',
        ),
        (
          'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
          'playlist',
          '37i9dQZF1DXcBWIGoYBM5M',
        ),
        (
          'https://open.spotify.com/user/someone/playlist/abc123',
          'playlist',
          'abc123',
        ),
        (
          'spotify:playlist:0TnOYISbd1XYRBk9myaseg',
          'playlist',
          '0TnOYISbd1XYRBk9myaseg',
        ),
        (
          '  https://open.spotify.com/track/05RgAMGypEvqhNs5hPCbMS  ',
          'track',
          '05RgAMGypEvqhNs5hPCbMS',
        ),
      ]) {
        final target = parseSpotifyLink(input);
        expect(target?.kind, kind, reason: input);
        expect(target?.id, id, reason: input);
      }
    });

    test('lo demás no es un enlace de Spotify', () {
      for (final input in [
        'https://music.youtube.com/playlist?list=PL123',
        'https://open.spotify.com/show/abc',
        'https://open.spotify.com/playlist/',
        'not a link',
        '',
      ]) {
        expect(parseSpotifyLink(input), isNull, reason: input);
      }
    });
  });

  group('página de la playlist', () {
    test('lee nombre, autor, portada y canciones, y salta los episodios', () {
      final list = parseSpotifyPlaylistEmbed(
        _page(
          '{"name":"Mix","subtitle":"Yo",'
          '"coverArt":{"sources":[{"url":"https://i.scdn.co/image/abc"}]},'
          '"trackList":['
          '{"title":"A","subtitle":"X, Y","entityType":"track"},'
          '{"title":"Ep","subtitle":"Pod","entityType":"episode"},'
          '{"title":"B","subtitle":"Z"}]}',
        ),
      );
      expect(list.name, 'Mix');
      expect(list.owner, 'Yo');
      expect(list.cover, 'https://i.scdn.co/image/abc');
      expect(list.tracks.map((t) => t.title), ['A', 'B']);
      expect(list.tracks.first.artists, ['X', 'Y']);
      expect(list.truncated, isFalse);
    });

    test('marca la lista cortada en 100 y descarta portadas no https', () {
      final rows = [
        for (var n = 0; n < 140; n++) '{"title":"T$n","subtitle":"A"}',
      ].join(',');
      final list = parseSpotifyPlaylistEmbed(
        _page(
          '{"name":"Larga","coverArt":{"sources":[{"url":"http://x/y"}]},'
          '"trackList":[$rows]}',
        ),
      );
      expect(list.tracks.length, 100);
      expect(list.truncated, isTrue);
      expect(list.cover, isNull);
    });

    test('sin entidad es privada y sin datos es que Spotify cambió', () {
      expect(
        () => parseSpotifyPlaylistEmbed(
          '<script id="__NEXT_DATA__" type="application/json">'
          '{"props":{"pageProps":{"status":404}}}</script>',
        ),
        throwsA(
          isA<SpotifyLinkFailure>().having(
            (e) => e.error,
            'error',
            SpotifyLinkError.private,
          ),
        ),
      );
      expect(
        () => parseSpotifyPlaylistEmbed('<html></html>'),
        throwsA(
          isA<SpotifyLinkFailure>().having(
            (e) => e.error,
            'error',
            SpotifyLinkError.changed,
          ),
        ),
      );
    });
  });

  group('emparejar canciones', () {
    test('quita sufijos de edición pero no un feat.', () {
      expect(cleanTitle('Song - 2015 Remaster'), 'Song');
      expect(cleanTitle('Song (Remastered 2011)'), 'Song');
      expect(cleanTitle('Song - Radio Edit'), 'Song');
      expect(cleanTitle('Song (feat. Otro)'), 'Song (feat. Otro)');
      expect(cleanTitle('Coldplay - Yellow'), 'Coldplay - Yellow');
    });

    test('la consulta es título y artista principal', () {
      expect(
        trackQuery(
          const SpotifyTrack('Tomorrow - 2011 Remaster', ['Kali Uchis', 'X']),
        ),
        'Tomorrow Kali Uchis',
      );
    });

    test('parecido de títulos', () {
      expect(titleSimilarity('Canción', 'cancion'), 1);
      expect(titleSimilarity('Song (feat. X)', 'Song'), 1);
      expect(titleSimilarity('Hello World', 'Hello'), .9);
      expect(titleSimilarity('Alfa', 'Beta'), 0);
    });

    test('coincide, dudoso o sin resultado', () {
      const track = SpotifyTrack('Tomorrow', ['Kali Uchis']);
      expect(
        pickMatch(track, [_song('aaaaaaaaaaa', 'Tomorrow', 'Kali Uchis')]).tier,
        MatchTier.matched,
      );
      // Mismo título, otro artista: se incluye pero se avisa.
      expect(
        pickMatch(track, [
          _song('bbbbbbbbbbb', 'Tomorrow', 'Otra persona'),
        ]).tier,
        MatchTier.check,
      );
      expect(
        pickMatch(track, [_song('ccccccccccc', 'Nada que ver', 'Nadie')]).tier,
        MatchTier.missing,
      );
      expect(pickMatch(track, const []).tier, MatchTier.missing);
      // Entre varios, gana el que tiene título y artista.
      final best = pickMatch(track, [
        _song('bbbbbbbbbbb', 'Tomorrow', 'Otra persona'),
        _song('aaaaaaaaaaa', 'Tomorrow (Remastered)', 'Kali Uchis'),
      ]);
      expect(best.tier, MatchTier.matched);
      expect(best.song?.id, 'aaaaaaaaaaa');
    });

    test(
      'una búsqueda que falla se reintenta y luego cuenta como fallo',
      () async {
        var calls = 0;
        final results = await runMatching(
          tracks: const [
            SpotifyTrack('Uno', ['Banda Uno']),
            SpotifyTrack('Dos', ['Banda Dos']),
          ],
          cancelled: () => false,
          retryDelay: Duration.zero,
          search: (query) async {
            if (query.startsWith('Dos')) {
              calls++;
              throw StateError('sin red');
            }
            return [_song('aaaaaaaaaaa', 'Uno', 'Banda Uno')];
          },
        );
        expect(results[0]?.tier, MatchTier.matched);
        expect(results[1]?.failed, isTrue);
        expect(calls, 2, reason: 'un reintento');
      },
    );

    test('al parar, las que no se miraron quedan sin resolver', () async {
      var stop = false;
      final results = await runMatching(
        tracks: [
          for (var i = 0; i < 20; i++) SpotifyTrack('T$i', ['Banda X']),
        ],
        concurrency: 1,
        cancelled: () => stop,
        search: (query) async {
          if (query.startsWith('T3 ')) stop = true;
          return [_song('aaaaaaaaaaa', query.split(' ').first, 'Banda X')];
        },
      );
      expect(results.where((e) => e != null).length, lessThan(20));
      expect(results.last, isNull);
    });
  });

  group('importar', () {
    SpotifyImportController controller({
      Future<SpotifyPlaylist> Function(String id)? fetch,
      List<List<String>>? created,
      Future<List<MusicTrack>> Function(String query)? search,
    }) => SpotifyImportController(
      retryDelay: Duration.zero,
      fetch:
          fetch ??
          (id) async => const SpotifyPlaylist(
            name: 'Mi lista',
            owner: 'Yo',
            tracks: [
              SpotifyTrack('Uno', ['Banda Uno']),
              SpotifyTrack('Dos', ['Banda Dos']),
              SpotifyTrack('Tres', ['Banda Tres']),
            ],
          ),
      search:
          search ??
          (query) async {
            final name = query.split(' ').first;
            if (name == 'Tres') return const [];
            return [
              _song(
                name == 'Uno' ? 'aaaaaaaaaaa' : 'bbbbbbbbbbb',
                name,
                'Banda $name',
              ),
            ];
          },
      create: (title, description, ids) async {
        created?.add([title, description, ...ids]);
        return 'PLabcdefgh12345';
      },
    );

    test(
      'flujo completo: lee, busca y crea la playlist con lo encontrado',
      () async {
        final created = <List<String>>[];
        final c = controller(created: created);
        await c.open(
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
        );
        expect(c.phase, SpotifyImportPhase.preview);
        expect(c.total, 3);

        await c.start();
        expect(c.phase, SpotifyImportPhase.done);
        expect(c.matched, 2);
        expect(c.missing, 1);
        expect(c.missingText, 'Tres - Banda Tres');
        expect(c.createdId, 'PLabcdefgh12345');
        expect(created, hasLength(1));
        expect(created.single, [
          'Mi lista',
          'Importada de Spotify · Yo',
          'aaaaaaaaaaa',
          'bbbbbbbbbbb',
        ]);
        expect(c.percent, 100);
      },
    );

    test('solo se importan playlists y los enlaces malos avisan', () async {
      final c = controller();
      await c.open('https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy');
      expect(c.phase, SpotifyImportPhase.failed);
      expect(c.message, contains('solo se pueden importar playlists'));

      await c.open('https://example.com/x');
      expect(c.message, 'Ese no es un enlace de Spotify.');
    });

    test(
      'una playlist privada o sin canciones no llega a la vista previa',
      () async {
        final c = controller(
          fetch: (id) async =>
              throw const SpotifyLinkFailure(SpotifyLinkError.private),
        );
        await c.open('spotify:playlist:0TnOYISbd1XYRBk9myaseg');
        expect(c.phase, SpotifyImportPhase.failed);
        expect(c.message, contains('privada'));

        final empty = controller(
          fetch: (id) async => const SpotifyPlaylist(name: 'Vacía', tracks: []),
        );
        await empty.open('spotify:playlist:0TnOYISbd1XYRBk9myaseg');
        expect(empty.phase, SpotifyImportPhase.failed);
      },
    );

    test('sin ninguna canción encontrada no se crea la playlist', () async {
      final created = <List<String>>[];
      final c = controller(created: created, search: (q) async => const []);
      await c.open('spotify:playlist:0TnOYISbd1XYRBk9myaseg');
      await c.start();
      expect(c.phase, SpotifyImportPhase.failed);
      expect(created, isEmpty);
    });

    test('si la búsqueda falla por la red lo dice y no crea nada', () async {
      final created = <List<String>>[];
      final c = controller(
        created: created,
        search: (q) async => throw StateError('sin red'),
      );
      await c.open('spotify:playlist:0TnOYISbd1XYRBk9myaseg');
      await c.start();
      expect(c.phase, SpotifyImportPhase.failed);
      expect(c.message, contains('conexión'));
      expect(created, isEmpty);
    });

    test('canciones repetidas en YouTube Music entran una sola vez', () async {
      final created = <List<String>>[];
      final c = controller(
        created: created,
        search: (query) async => [
          _song(
            'aaaaaaaaaaa',
            query.split(' ').first,
            'Banda ${query.split(' ').first}',
          ),
        ],
      );
      await c.open('spotify:playlist:0TnOYISbd1XYRBk9myaseg');
      await c.start();
      expect(created.single.skip(2), ['aaaaaaaaaaa']);
    });
  });
}
