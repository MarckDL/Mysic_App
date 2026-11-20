import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/connected_library/data/music_discovery.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/presentation/community_playlist_rail.dart';
import 'package:mysic/features/playback/application/playback_providers.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_track_audio_engine.dart';

void main() {
  testWidgets(
    'la tarjeta comunitaria abre la lista y reproduce la pista elegida',
    (tester) async {
      const playlist = MusicPlaylist('PL123', 'De la comunidad', false);
      final songs = [
        for (int i = 1; i <= 4; i++)
          MusicTrack(
            i.toString().padLeft(11, '0'),
            'Pista $i',
            'Artista',
            120,
            false,
            null,
            nativePlayback: true,
          ),
      ];
      MusicItem? opened;
      final engine = FakeTrackAudioEngine();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: CommunityPlaylistRail(
                playlists: const [playlist],
                open: (item) => opened = item,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) => const Scaffold(body: Text('Reproductor')),
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
              expect(request.path, 'playlist/PL123');
              return MusicPage(songs, null, null, 0);
            }),
          ],
          child: Consumer(
            builder: (_, ref, child) {
              ref.watch(trackPlaybackControllerProvider);
              return child!;
            },
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pista 3'), findsOneWidget);
      expect(find.text('Pista 4'), findsNothing);
      await tester.tap(find.text('De la comunidad'));
      expect(opened, same(playlist));
      await tester.tap(find.text('Pista 2'));
      await tester.pumpAndSettle();
      expect(engine.sourceId, songs[1].id);
      expect(find.text('Reproductor'), findsOneWidget);
    },
  );
}
