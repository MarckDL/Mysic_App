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
    return Column(
      children: [
        Expanded(child: Router.withConfig(config: _router)),
        MiniPlayer(
          controller: controller,
          open: () {
            if (_router.routeInformationProvider.value.uri.path != '/player') {
              _router.push('/player');
            }
          },
        ),
      ],
    );
  }
}
