import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/catalog_providers.dart';
import 'catalog_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  String? _query;
  void _changed(String value) {
    _debounce?.cancel();
    setState(() => _query = null);
    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      data: (tracks) => tracks.isEmpty
                          ? const Center(
                              child: Text(
                                'No encontramos canciones. Prueba otra búsqueda.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: tracks.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final track = tracks[index];
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
                                  trailing: Text(track.durationLabel ?? '—'),
                                  onTap: () => context.push(
                                    '/tracks/${Uri.encodeComponent(track.id)}',
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
