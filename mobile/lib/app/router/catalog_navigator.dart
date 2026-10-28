import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/playback/presentation/demo_audio_screen.dart';
import '../../features/authentication/domain/mysic_profile.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/search/presentation/track_detail_screen.dart';

// Solo se monta dentro de AuthGate tras verificar y sincronizar el perfil.
// Al cerrar/cambiar cuenta se elimina el navegador y todo su estado.
class CatalogNavigator extends StatefulWidget {
  const CatalogNavigator({super.key, required this.profile});
  final MysicProfile profile;
  @override
  State<CatalogNavigator> createState() => _CatalogNavigatorState();
}

class _CatalogNavigatorState extends State<CatalogNavigator> {
  late final GoRouter _router = GoRouter(
    routes: [
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
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}
