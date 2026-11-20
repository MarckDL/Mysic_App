import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/domain/mysic_profile.dart';
import '../../features/authentication/presentation/account_screen.dart';
import '../../features/comments/presentation/moderation_screen.dart';
import '../../features/connected_library/application/connected_host.dart';
import '../../features/connected_library/presentation/connected_screen.dart';
import '../../features/connected_library/application/music_mode_controller.dart';
import '../../features/connected_library/domain/music_mode.dart';
import '../../features/connected_library/presentation/music_mode_host.dart';
import '../../features/connected_library/presentation/music_mode_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/history/data/history_client.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/imports/presentation/import_screen.dart';
import '../../features/playback/application/playback_providers.dart';
import '../../features/playback/presentation/demo_audio_screen.dart';
import '../../features/playback/presentation/player_screen.dart';
import '../../features/playback/presentation/player_widgets.dart';
import '../../features/playback/presentation/youtube_audio_test_screen.dart';
import '../../features/playlists/presentation/playlist_detail_screen.dart';
import '../../features/playlists/presentation/playlists_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/search/presentation/track_detail_screen.dart';

// AuthGate elimina el navegador y su estado al cerrar sesión o cambiar de UID.
class CatalogNavigator extends ConsumerStatefulWidget {
  const CatalogNavigator({super.key, required this.profile});

  final MysicProfile profile;

  @override
  ConsumerState<CatalogNavigator> createState() => _CatalogNavigatorState();
}

class _CatalogNavigatorState extends ConsumerState<CatalogNavigator> {
  final _rootKey = GlobalKey<NavigatorState>();
  late final GoRouter _router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _CatalogShell(
          shell: shell,
          firebaseUid: widget.profile.firebaseUid,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => MusicModeSurface(
                  surface: MusicSurface.home,
                  local: HomeScreen(
                    profile: widget.profile,
                    accountAction: const AccountAction(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const MusicModeSurface(
                  surface: MusicSurface.search,
                  local: SearchScreen(accountAction: AccountAction()),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const MusicModeSurface(
                  surface: MusicSurface.songs,
                  local: LibraryScreen(accountAction: AccountAction()),
                ),
                routes: [
                  GoRoute(
                    path: 'youtube',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => const ConnectedScreen(),
                    routes: [
                      GoRoute(
                        path: 'playlist/:id',
                        parentNavigatorKey: _rootKey,
                        redirect: (context, state) =>
                            '/music/playlist/${Uri.encodeComponent(state.pathParameters['id']!)}',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/imports/youtube-music',
        builder: (context, state) => const _MysicOnly(child: ImportScreen()),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const MusicModeSurface(
          surface: MusicSurface.history,
          local: HistoryScreen(),
        ),
      ),
      GoRoute(
        path: '/music/playlist/:id',
        builder: (context, state) => MusicModeSurface(
          surface: MusicSurface.playlist,
          playlistId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/music/album/:id',
        builder: (context, state) => MusicModeSurface(
          surface: MusicSurface.album,
          playlistId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/music/liked',
        builder: (context, state) =>
            const MusicModeSurface(surface: MusicSurface.liked),
      ),
      GoRoute(
        path: '/music/repeat',
        builder: (context, state) =>
            const MusicModeSurface(surface: MusicSurface.onRepeat),
      ),
      GoRoute(
        path: '/music/artists',
        builder: (context, state) =>
            const MusicModeSurface(surface: MusicSurface.artists),
      ),
      GoRoute(
        path: '/music/artist/:id',
        builder: (context, state) => MusicModeSurface(
          surface: MusicSurface.artist,
          playlistId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => AccountScreen(profile: widget.profile),
      ),
      if (kDebugMode) ...[
        GoRoute(
          path: '/youtube-audio-test',
          builder: (context, state) =>
              const _MysicOnly(child: YoutubeAudioTestScreen()),
        ),
        GoRoute(
          path: '/audio-test',
          builder: (context, state) =>
              const _MysicOnly(child: DemoAudioScreen()),
        ),
      ],
      GoRoute(
        path: '/playlists',
        builder: (context, state) => const _MysicOnly(child: PlaylistsScreen()),
      ),
      GoRoute(
        path: '/playlists/:id',
        builder: (context, state) => _MysicOnly(
          child: PlaylistDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const MusicModeSurface(
          surface: MusicSurface.liked,
          local: FavoritesScreen(),
        ),
      ),
      GoRoute(
        path: '/moderation/comments',
        redirect: (context, state) =>
            widget.profile.canModerateComments ? null : '/account',
        builder: (context, state) => const ModerationScreen(canModerate: true),
      ),
      GoRoute(
        path: '/tracks/:id',
        builder: (context, state) => _MysicOnly(
          child: TrackDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Mysic')),
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Volver al inicio'),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget router = Router.withConfig(config: _router);
    if (ref.watch(youtubeMusicModeEnabledProvider)) {
      router = MusicModeHost(
        controller: ref.watch(
          musicModeControllerProvider(widget.profile.firebaseUid),
        ),
        child: router,
      );
    }
    if (!ref.watch(youtubePilotProvider)) return router;
    return ConnectedHost(
      controller: ref.watch(
        connectedControllerProvider(widget.profile.firebaseUid),
      ),
      onBindingChanged: (confirmed) {
        if (!ref.read(youtubeMusicModeEnabledProvider)) return;
        final music = ref.read(
          musicModeControllerProvider(widget.profile.firebaseUid),
        );
        if (music.connection?.isPreview == true ||
            music.connection?.isDesktop == true) {
          return;
        }
        if (confirmed) {
          unawaited(music.useLinkedAccount());
          _router.go('/library');
        } else {
          unawaited(music.refresh(invalidate: true));
        }
      },
      onReturn: () {
        if (ref.read(youtubeMusicModeEnabledProvider) &&
            ref
                    .read(
                      musicModeControllerProvider(widget.profile.firebaseUid),
                    )
                    .connection
                    ?.isPreview ==
                true) {
          return;
        }
        const path = '/library/youtube';
        if (_router.routerDelegate.currentConfiguration.isEmpty ||
            _router.state.matchedLocation != path) {
          _router.go(path);
        }
      },
      child: router,
    );
  }
}

class _CatalogShell extends ConsumerWidget {
  const _CatalogShell({required this.shell, required this.firebaseUid});

  final StatefulNavigationShell shell;
  final String firebaseUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    final music = MusicModeScope.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: keyboardOpen
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniPlayer(
                  controller: controller,
                  open: () => context.push('/player'),
                ),
                NavigationBar(
                  selectedIndex: shell.currentIndex,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (music?.showMusic != true &&
                        index == 0 &&
                        shell.currentIndex != 0) {
                      ref.invalidate(recentListeningProvider(firebaseUid));
                    }
                    shell.goBranch(index);
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Inicio',
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.search),
                      label: music?.wantsMusic == true ? 'Buscar' : 'Explorar',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: 'Biblioteca',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _MysicOnly extends StatelessWidget {
  const _MysicOnly({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MusicModeScope.of(context)?.showMusic != true) return child;
    return Scaffold(
      appBar: AppBar(title: const Text('Mysic')),
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Volver a Inicio'),
        ),
      ),
    );
  }
}
