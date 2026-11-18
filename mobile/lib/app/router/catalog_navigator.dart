import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/domain/mysic_profile.dart';
import '../../features/authentication/presentation/account_screen.dart';
import '../../features/comments/presentation/moderation_screen.dart';
import '../../features/connected_library/application/connected_host.dart';
import '../../features/connected_library/presentation/connected_screen.dart';
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
                builder: (context, state) => HomeScreen(
                  profile: widget.profile,
                  accountAction: const AccountAction(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) =>
                    const SearchScreen(accountAction: AccountAction()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) =>
                    const LibraryScreen(accountAction: AccountAction()),
                routes: [
                  GoRoute(
                    path: 'youtube',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => const ConnectedScreen(),
                    routes: [
                      GoRoute(
                        path: 'playlist/:id',
                        parentNavigatorKey: _rootKey,
                        builder: (context, state) => ConnectedScreen(
                          playlistId: state.pathParameters['id'],
                          title: state.extra as String?,
                        ),
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
        builder: (context, state) => const ImportScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
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
          builder: (context, state) => const YoutubeAudioTestScreen(),
        ),
        GoRoute(
          path: '/audio-test',
          builder: (context, state) => const DemoAudioScreen(),
        ),
      ],
      GoRoute(
        path: '/playlists',
        builder: (context, state) => const PlaylistsScreen(),
      ),
      GoRoute(
        path: '/playlists/:id',
        builder: (context, state) =>
            PlaylistDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/moderation/comments',
        redirect: (context, state) =>
            widget.profile.canModerateComments ? null : '/account',
        builder: (context, state) => const ModerationScreen(canModerate: true),
      ),
      GoRoute(
        path: '/tracks/:id',
        builder: (context, state) =>
            TrackDetailScreen(id: state.pathParameters['id']!),
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
    final router = Router.withConfig(config: _router);
    if (!ref.watch(youtubePilotProvider)) return router;
    return ConnectedHost(
      controller: ref.watch(
        connectedControllerProvider(widget.profile.firebaseUid),
      ),
      onReturn: () {
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
                    if (index == 0 && shell.currentIndex != 0) {
                      ref.invalidate(recentListeningProvider(firebaseUid));
                    }
                    shell.goBranch(index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Inicio',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search),
                      label: 'Explorar',
                    ),
                    NavigationDestination(
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
