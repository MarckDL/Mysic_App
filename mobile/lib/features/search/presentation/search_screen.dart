import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../playback/presentation/open_player.dart';
import '../application/catalog_providers.dart';
import '../domain/catalog_track.dart';
import 'catalog_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.accountAction});

  final Widget? accountAction;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late TrackPlaybackController _playback;
  final _input = TextEditingController();
  Timer? _debounce;
  Timer? _prefetchDebounce;
  String? _query;
  String? _prefetchedId;
  void _changed(String value) {
    _debounce?.cancel();
    _cancelPrefetch();
    setState(() => _query = null);
    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = query);
    });
  }

  void _schedulePrefetch(List<CatalogTrack> tracks) {
    if (tracks.isEmpty) return;
    final track = tracks.first;
    if (_prefetchedId == track.id) return;
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _query == null) return;
      _prefetchedId = track.id;
      unawaited(_playback.prefetchTrack(track).catchError((Object _) {}));
    });
  }

  void _cancelPrefetch() {
    _prefetchDebounce?.cancel();
    _prefetchedId = null;
    if (mounted) {
      _playback.cancelPrefetch();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _debounce?.cancel();
    _prefetchDebounce?.cancel();
    _playback.cancelPrefetch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _playback = ref.watch(trackPlaybackControllerProvider);
    final query = _query;
    final result = query == null
        ? null
        : ref.watch(searchResultsProvider(query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar'),
        actions: [?widget.accountAction],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _input,
                maxLength: 120,
                onChanged: _changed,
                decoration: const InputDecoration(
                  labelText: 'Canción o artista',
                  counterText: '',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: query == null
                  ? _ExploreCategories(
                      onSelected: (category) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        _input.text = category;
                        _changed(category);
                      },
                    )
                  : result!.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => CatalogError(
                        error: error,
                        retry: () =>
                            ref.invalidate(searchResultsProvider(query)),
                      ),
                      data: (tracks) {
                        _schedulePrefetch(tracks);
                        return tracks.isEmpty
                            ? const Center(
                                child: Text(
                                  'No encontramos canciones. Prueba otra búsqueda.',
                                ),
                              )
                            : ListView.separated(
                                key: PageStorageKey(query),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: tracks.length + 1,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return TextButton.icon(
                                      onPressed: () => playTracksAndOpenPlayer(
                                        context,
                                        ref,
                                        tracks,
                                      ),
                                      icon: const Icon(Icons.playlist_play),
                                      label: const Text(
                                        'Reproducir resultados',
                                      ),
                                    );
                                  }
                                  final track = tracks[index - 1];
                                  return ListTile(
                                    leading: TrackArtwork(
                                      url: track.thumbnailUrl,
                                    ),
                                    title: Text(
                                      track.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      track.artistName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Reproducir canción',
                                          icon: const Icon(Icons.play_arrow),
                                          onPressed: () => playAndOpenPlayer(
                                            context,
                                            ref,
                                            track,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Añadir a la cola',
                                          icon: const Icon(Icons.queue_music),
                                          onPressed: () {
                                            ref
                                                .read(
                                                  trackPlaybackControllerProvider,
                                                )
                                                .enqueue(track);
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Cola actualizada',
                                                ),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    onTap: () =>
                                        playAndOpenPlayer(context, ref, track),
                                  );
                                },
                              );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreCategories extends StatelessWidget {
  const _ExploreCategories({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _categories = [
    ('Pop', Icons.auto_awesome_rounded, Color(0xFF554687)),
    ('Rock', Icons.electric_bolt_rounded, Color(0xFF793E40)),
    ('Lo-fi', Icons.headphones_rounded, Color(0xFF494965)),
    ('Urbano', Icons.location_city_rounded, Color(0xFF37516E)),
    ('Anime', Icons.animation_rounded, Color(0xFF854865)),
    ('Cumbias', Icons.music_note_rounded, Color(0xFF376258)),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      Text('Categorías', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150 * MediaQuery.textScalerOf(context).scale(1),
          mainAxisExtent: 90 + MediaQuery.textScalerOf(context).scale(28),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final (name, icon, color) = _categories[index];
          return Material(
            color: color,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(name),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Icon(
                        icon,
                        size: 26,
                        color: const Color(0xCCFFFFFF),
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
