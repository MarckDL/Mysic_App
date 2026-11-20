import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/connected_library/data/music_discovery.dart';
import 'package:mysic/features/connected_library/data/original_music_catalog.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/music_discovery_screen.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';
import 'package:mysic/features/connected_library/presentation/music_shelves.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
  test('las portadas de ambas fuentes conservan su subtítulo musical', () {
    final disc = OriginalMusicCatalog.item({
      'id': 'MPRE123',
      'title': 'Disco',
      'artist': 'YUI',
      'year': '2009',
    }, 'album')!;
    final list = OriginalMusicCatalog.item({
      'id': 'VLPL321',
      'title': 'Mi lista',
      'subtitle': 'Playlist • María',
    }, 'playlist')!;
    final artist = MusicItem.fromJson({
      'kind': 'artist',
      'id': 'UCtest',
      'title': 'Artista de prueba',
      'subtitle': '32 mil oyentes',
    });
    expect([disc, list, artist].map(itemDescription), [
      'YUI · 2009',
      'María',
      '32 mil oyentes',
    ]);
    expect(
      itemDescription(const MusicPlaylist('PL', 'Mi lista', false)),
      'Playlist',
    );
  });

  testWidgets('Ver todo abre la sección completa y permite elegir una pista', (
    tester,
  ) async {
    MusicItem? chosen;
    final songs = [
      for (var i = 1; i <= 16; i++)
        MusicTrack(
          i.toString().padLeft(11, '0'),
          'Canción $i',
          'Artista',
          120,
          false,
          null,
          shelfTitle: 'Selección rápida',
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              MusicShelves(items: songs, open: (item) => chosen = item),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ver todo'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    final scroll = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    final last = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Canción 16'),
    );
    await tester.scrollUntilVisible(last, 220, scrollable: scroll);
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(chosen, same(songs.last));
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'Explorar abre un álbum público, conserva la navegación y reproduce dentro de Mysic',
    (tester) async {
      final calls = <DiscoveryRequest>[];
      final engine = FakeTrackAudioEngine();
      const track = MusicTrack(
        'aaaaaaaaaaa',
        'Prueba de audio',
        'Artista',
        166,
        false,
        null,
        nativePlayback: true,
      );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const MusicDiscoveryScreen()),
          GoRoute(
            path: '/music/catalog/:kind/:id',
            builder: (_, state) => PublicMusicDetail(
              kind: state.pathParameters['kind']!,
              id: state.pathParameters['id']!,
              title: state.extra as String?,
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('Reproductor de prueba')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(user: const AuthUser(uid: 'A')),
            ),
            trackAudioEngineFactoryProvider.overrideWithValue(() => engine),
            discoveryPageProvider.overrideWith((_, request) async {
              calls.add(request);
              if (request.path == 'explore') {
                return const MusicPage(
                  [
                    MusicAlbum(
                      'MPREb123',
                      'Álbum de prueba',
                      shelfTitle: 'Álbumes y sencillos nuevos',
                    ),
                  ],
                  null,
                  null,
                  0,
                );
              }
              expect(request.path, 'album/MPREb123');
              return const MusicPage([track], null, null, 0, 'Álbum de prueba');
            }),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              ref.watch(trackPlaybackControllerProvider);
              return child!;
            },
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Álbumes y sencillos nuevos'), findsOneWidget);
      await tester.tap(find.text('Álbum de prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Prueba de audio'), findsOneWidget);
      await tester.tap(find.text('Reproducir'));
      await tester.pumpAndSettle();
      expect(engine.sourceId, track.id);
      expect(find.text('Reproductor de prueba'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Explorar'), findsOneWidget);
      expect(
        calls.map((x) => x.path),
        containsAll(['explore', 'album/MPREb123']),
      );
    },
  );

  testWidgets(
    'los cinco filtros consultan por tipo y limpiar vuelve a Explorar',
    (tester) async {
      final calls = <DiscoveryRequest>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryPageProvider.overrideWith((_, request) async {
              calls.add(request);
              if (request.path == 'explore') {
                return const MusicPage(
                  [
                    MusicPlaylist(
                      'PL123',
                      'Tendencia de muestra',
                      false,
                      shelfTitle: 'Tendencias',
                    ),
                  ],
                  null,
                  null,
                  0,
                );
              }
              expect(request.query, 'again');
              final list = switch (request.filter!) {
                MusicSearchFilter.all => const <MusicItem>[
                  MusicTrack(
                    'aaaaaaaaaaa',
                    'Mejor tema',
                    'YUI',
                    180,
                    false,
                    null,
                    nativePlayback: true,
                    shelfTitle: 'Mejor coincidencia',
                  ),
                ],
                MusicSearchFilter.song => const <MusicItem>[
                  MusicTrack(
                    'aaaaaaaaaaa',
                    'Tema filtrado',
                    'YUI',
                    180,
                    false,
                    null,
                    nativePlayback: true,
                  ),
                ],
                MusicSearchFilter.video => const <MusicItem>[
                  MusicTrack(
                    'bbbbbbbbbbb',
                    'Videoclip',
                    'YUI',
                    180,
                    false,
                    null,
                    nativePlayback: true,
                    isVideo: true,
                  ),
                ],
                MusicSearchFilter.artist => const <MusicItem>[
                  MusicArtist('UCx', 'Grupo filtrado'),
                ],
                MusicSearchFilter.album => const <MusicItem>[
                  MusicAlbum('MPREb34', 'Álbum filtrado'),
                ],
              };
              return MusicPage(list, null, null, 0);
            }),
          ],
          child: const MaterialApp(home: MusicDiscoveryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tendencias'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'again');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Mejor coincidencia'), findsOneWidget);
      for (final filter in MusicSearchFilter.values.skip(1)) {
        final chip = find.widgetWithText(ChoiceChip, filter.label);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(calls.last.filter, filter);
      }
      expect(find.text('Álbum filtrado'), findsOneWidget);
      await tester.tap(find.byTooltip('Limpiar búsqueda'));
      await tester.pumpAndSettle();
      expect(find.text('Tendencias'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    },
  );
}
