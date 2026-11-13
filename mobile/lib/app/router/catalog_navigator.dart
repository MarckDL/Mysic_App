import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/playback/application/playback_providers.dart';
import '../../features/playback/presentation/player_screen.dart';
import '../../features/playback/presentation/player_widgets.dart';
import '../../features/playback/presentation/youtube_audio_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/playback/presentation/demo_audio_screen.dart';
import '../../features/authentication/domain/mysic_profile.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/search/presentation/track_detail_screen.dart';
import '../../features/playlists/presentation/playlists_screen.dart';
import '../../features/playlists/presentation/playlist_detail_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/youtube_library/presentation/youtube_library_screen.dart';

// Solo se monta dentro de AuthGate tras verificar y sincronizar el perfil.
// Al cerrar/cambiar cuenta se elimina el navegador y todo su estado.
class CatalogNavigator extends ConsumerStatefulWidget {
  const CatalogNavigator({super.key, required this.profile});
  final MysicProfile profile;
  @override
  ConsumerState<CatalogNavigator> createState() => _CatalogNavigatorState();
}

class _CatalogNavigatorState extends ConsumerState<CatalogNavigator> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/player',
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/youtube-audio-test',
        builder: (context, state) => const YoutubeAudioTestScreen(),
      ),
      GoRoute(
        path: '/audio-test',
        builder: (context, state) => const DemoAudioScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => HomeScreen(profile: widget.profile),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
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
        path: '/library',
        builder: (context, state) => const LibraryScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => ProfileScreen(profile: widget.profile),
      ),
      GoRoute(
        path: '/youtube-library',
        builder: (context, state) => const YoutubeLibraryScreen(),
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
    // Este listener mantiene una única instancia mientras la sesión está montada.
    final controller = ref.watch(trackPlaybackControllerProvider);
    return ListenableBuilder(
      listenable: _router.routeInformationProvider,
      builder: (context, _) {
        final path = _router.routeInformationProvider.value.uri.path;
        final destination = switch (path) {
          '/search' => 1,
          '/library' || '/playlists' || '/favorites' => 2,
          '/profile' => 3,
          _ => 0,
        };
        final primary = !const {
          '/player',
          '/audio-test',
          '/youtube-audio-test',
        }.contains(path);
        return Column(
          children: [
            Expanded(child: Router.withConfig(config: _router)),
            if (primary)
              MiniPlayer(
                controller: controller,
                open: () => _router.push('/player'),
              ),
            if (primary)
              NavigationBar(
                selectedIndex: destination,
                onDestinationSelected: (index) => _router.go(
                  const ['/', '/search', '/library', '/profile'][index],
                ),
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
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Perfil',
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
