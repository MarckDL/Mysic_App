import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/catalog_providers.dart';
import '../domain/catalog_track.dart';
import 'catalog_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late TrackPlaybackController _playback;
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
      appBar: AppBar(title: const Text('Buscar música')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                maxLength: 120,
                onChanged: _changed,
                decoration: const InputDecoration(
                  labelText: 'Canción o artista',
                  hintText: 'Escribe al menos 2 caracteres',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: query == null
                  ? const Center(
                      child: Text('Busca canciones por título o artista.'),
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
                                itemCount: tracks.length + 1,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return TextButton.icon(
                                      onPressed: () => unawaited(
                                        ref
                                            .read(
                                              trackPlaybackControllerProvider,
                                            )
                                            .playQueue(tracks),
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
                                          onPressed: () => unawaited(
                                            ref
                                                .read(
                                                  trackPlaybackControllerProvider,
                                                )
                                                .playTrack(track),
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
                                    onTap: () => context.push(
                                      '/tracks/${Uri.encodeComponent(track.id)}',
                                    ),
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
