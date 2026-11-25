import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/offline_mode.dart';
import '../../core/settings/app_settings.dart';
import '../../features/downloads/data/download_store.dart';
import '../../features/downloads/presentation/downloaded_collection_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';
import '../../features/playback/application/track_playback_controller.dart';
import '../../features/authentication/domain/mysic_profile.dart';
import '../../features/authentication/presentation/account_screen.dart';
import '../../features/connected_library/application/music_mode_controller.dart';
import '../../features/connected_library/domain/music_mode.dart';
import '../../features/connected_library/presentation/catalog_pages.dart';
import '../../features/connected_library/presentation/library_screen.dart'
    show LibraryTab, libraryTabRequests;
import '../../features/connected_library/presentation/music_mode_host.dart';
import '../../features/connected_library/presentation/mood_screen.dart';
import '../../features/connected_library/presentation/music_mode_screen.dart';
import '../../features/connected_library/presentation/search_screen.dart';
import '../../features/playback/application/playback_providers.dart';
import '../../features/playback/presentation/player_screen.dart';
import '../../features/playback/presentation/player_widgets.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/ytm/data/liked_tracks.dart';
import '../adaptive_theme.dart';

// AuthGate elimina el navegador y su estado al cerrar sesión o cambiar de cuenta.
class CatalogNavigator extends ConsumerStatefulWidget {
  const CatalogNavigator({super.key, required this.profile});

  final MysicProfile profile;

  @override
  ConsumerState<CatalogNavigator> createState() => _CatalogNavigatorState();
}

class _CatalogNavigatorState extends ConsumerState<CatalogNavigator> {
  final _rootKey = GlobalKey<NavigatorState>();

  // La app puede abrir con el perfil guardado. Las páginas del router no se
  // reconstruyen al cambiar este widget, así que las que muestran el perfil
  // lo escuchan aquí y se actualizan cuando llega el verificado.
  late final _profile = ValueNotifier(widget.profile);

  @override
  void didUpdateWidget(CatalogNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _profile.value = widget.profile;
  }

  late final GoRouter _router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _CatalogShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const MusicModeSurface(surface: MusicSurface.home),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) =>
                    const MusicModeSurface(surface: MusicSurface.search),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) =>
                    const MusicModeSurface(surface: MusicSurface.songs),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) =>
            _mini(const MusicModeSurface(surface: MusicSurface.history)),
      ),
      GoRoute(
        path: '/music/playlist/:id',
        builder: (context, state) => _mini(
          MusicModeSurface(
            surface: MusicSurface.playlist,
            playlistId: state.pathParameters['id'],
            seed: state.extra is PageSeed ? state.extra as PageSeed : null,
          ),
        ),
      ),
      GoRoute(
        path: '/music/album/:id',
        builder: (context, state) => _mini(
          MusicModeSurface(
            surface: MusicSurface.album,
            playlistId: state.pathParameters['id'],
          ),
        ),
      ),
      GoRoute(
        path: '/music/liked',
        builder: (context, state) =>
            _mini(const MusicModeSurface(surface: MusicSurface.liked)),
      ),
      GoRoute(
        path: '/music/repeat',
        builder: (context, state) =>
            _mini(const MusicModeSurface(surface: MusicSurface.onRepeat)),
      ),
      GoRoute(
        path: '/music/mood',
        builder: (context, state) => _mini(
          state.extra is MoodSeed
              ? MoodScreen(seed: state.extra as MoodSeed)
              : const MusicModeSurface(surface: MusicSurface.search),
        ),
      ),
      GoRoute(
        path: '/music/artists',
        builder: (context, state) =>
            _mini(const MusicModeSurface(surface: MusicSurface.artists)),
      ),
      GoRoute(
        path: '/music/artist/:id',
        builder: (context, state) => _mini(
          MusicModeSurface(
            surface: MusicSurface.artist,
            playlistId: state.pathParameters['id'],
          ),
        ),
      ),
      GoRoute(
        path: '/artist/:id',
        builder: (context, state) => _mini(
          ArtistScreen(
            id: state.pathParameters['id']!,
            seed: state.extra is PageSeed ? state.extra as PageSeed : null,
          ),
        ),
      ),
      GoRoute(
        path: '/album/:id',
        builder: (context, state) => _mini(
          AlbumScreen(
            id: state.pathParameters['id']!,
            seed: state.extra is PageSeed ? state.extra as PageSeed : null,
          ),
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => _mini(const DownloadsScreen()),
      ),
      GoRoute(
        path: '/downloads/collection/:id',
        builder: (context, state) =>
            _mini(DownloadedCollectionScreen(id: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => ValueListenableBuilder(
          valueListenable: _profile,
          builder: (context, profile, _) => AccountScreen(profile: profile),
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
    _profile.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Crea ya el ajuste «solo descargadas» (main() ya restauró su valor).
    ref.read(offlineOnlyProvider);
    unawaited(_checkConnection());
  }

  /// Sin internet al arrancar y con canciones descargadas, la app deja al
  /// usuario en Biblioteca → Descargas, donde lo descargado se ve y suena sin
  /// internet ni datos. No cambia ningún ajuste ni bloquea la red: el usuario
  /// sigue libre de ir a cualquier otra parte, y el modo «Solo canciones
  /// descargadas» es solo suyo. No retrasa el primer fotograma, y solo mueve al
  /// usuario si sigue en Inicio.
  Future<void> _checkConnection() async {
    await DownloadStore.instance.load();
    if (!mounted ||
        OfflineMode.instance.manual ||
        !DownloadStore.instance.hasDownloads) {
      return;
    }
    if (await OfflineMode.hasInternet() || !mounted) return;
    final here = _router.routeInformationProvider.value.uri.path;
    if (here != '/') return;
    libraryTabRequests.value = LibraryTab.downloads;
    _router.go('/library');
  }

  @override
  Widget build(BuildContext context) => AdaptiveTheme(
    player: ref.watch(trackPlaybackControllerProvider),
    enabled: ref.watch(adaptCoverColorProvider),
    child: EffectsScope(
      reduced: ref.watch(reduceEffectsProvider),
      child: MusicModeHost(
        controller: ref.watch(musicModeControllerProvider(widget.profile.uid)),
        child: Router.withConfig(config: _router),
      ),
    ),
  );
}

/// El mini reproductor también en las páginas que se abren por encima de las
/// pestañas (álbum, playlist, artista, género, Recientes, Descargas…).
Widget _mini(Widget child) => WithMiniPlayer(child: child);

/// Una página con el mini reproductor debajo, como las pestañas: así la
/// canción que suena se sigue viendo y controlando al navegar.
class WithMiniPlayer extends ConsumerWidget {
  const WithMiniPlayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    LikedTracks? likes;
    try {
      likes = ref.watch(likedTracksProvider);
    } on Object {
      likes = null;
    }
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Sin nada en la cola la página va tal cual, sin hueco abajo.
        if (keyboardOpen ||
            (controller.current == null && controller.queue.isEmpty)) {
          return child;
        }
        return Scaffold(
          body: child,
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: MiniPlayer(
                controller: controller,
                likes: likes,
                open: () => context.push('/player'),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CatalogShell extends ConsumerWidget {
  const _CatalogShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    LikedTracks? likes;
    try {
      likes = ref.watch(likedTracksProvider);
    } on Object {
      likes = null;
    }
    // Con «solo descargadas» (o sin internet al arrancar) las pestañas, que
    // necesitan red, se sustituyen por la lista de descargas.
    return ListenableBuilder(
      listenable: OfflineMode.instance,
      builder: (context, _) => OfflineMode.instance.active
          ? const OfflineHome()
          : _tabs(context, controller, keyboardOpen, likes),
    );
  }

  Widget _tabs(
    BuildContext context,
    TrackPlaybackController controller,
    bool keyboardOpen,
    LikedTracks? likes,
  ) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: keyboardOpen
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniPlayer(
                  controller: controller,
                  likes: likes,
                  open: () => context.push('/player'),
                ),
                const Divider(height: 1),
                NavigationBar(
                  selectedIndex: shell.currentIndex,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) {
                    // Tocar Buscar estando en Buscar empieza una búsqueda
                    // nueva, como en Limusic.
                    if (index == 1 && shell.currentIndex == 1) {
                      searchTabReselected.value++;
                      return;
                    }
                    FocusManager.instance.primaryFocus?.unfocus();
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
                      label: 'Buscar',
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
