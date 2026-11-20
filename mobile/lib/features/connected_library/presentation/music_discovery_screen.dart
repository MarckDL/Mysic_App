import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/account_screen.dart'
    show AccountAction;
import '../../playback/application/playback_providers.dart';
import '../../search/presentation/catalog_widgets.dart' show CatalogError;
import '../data/music_discovery.dart';
import '../domain/music_mode.dart';
import 'music_mode_host.dart';
import 'music_shelves.dart';
import 'play_discovery_queue.dart';

void openCatalogDetail(BuildContext context, MusicItem item) {
  final kind = catalogKind(item);
  if (item is MusicTrack) return;
  context.push(
    '/music/catalog/$kind/${Uri.encodeComponent(item.id)}',
    extra: item.title,
  );
}

class MusicDiscoveryScreen extends ConsumerStatefulWidget {
  const MusicDiscoveryScreen({super.key});
  @override
  ConsumerState<MusicDiscoveryScreen> createState() =>
      _MusicDiscoveryScreenState();
}

class _MusicDiscoveryScreenState extends ConsumerState<MusicDiscoveryScreen> {
  final _input = TextEditingController();
  Timer? _timer;
  var _query = '';
  var _filter = MusicSearchFilter.all;

  void _search(String raw) {
    _timer?.cancel();
    final value = raw.trim();
    if (value == _query) return;
    setState(() {
      _query = value;
    });
  }

  void _changed(String value) {
    _timer?.cancel();
    if (value.trim().isEmpty) {
      _search('');
    } else {
      _timer = Timer(const Duration(milliseconds: 350), () => _search(value));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explore = _query.isEmpty;
    final DiscoveryRequest request = explore
        ? exploreRequest
        : (path: 'search', query: _query, filter: _filter);
    return Scaffold(
      appBar: AppBar(
        title: Text(explore ? 'Explorar' : 'Buscar'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(discoveryPageProvider(request)),
          ),
          const AccountAction(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            TextField(
              controller: _input,
              maxLength: 120,
              textInputAction: TextInputAction.search,
              onChanged: _changed,
              onSubmitted: _search,
              decoration: InputDecoration(
                labelText: 'Canción, artista o álbum',
                counterText: '',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (_, value, __) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _input.clear();
                            _search('');
                          },
                        ),
                ),
              ),
            ),
            if (!explore)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in MusicSearchFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(filter.label),
                            labelStyle: Theme.of(context).textTheme.labelMedium,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            selected: filter == _filter,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            PublicMusicResults(request: request),
          ],
        ),
      ),
    );
  }
}

class PublicMusicDetail extends StatelessWidget {
  const PublicMusicDetail({
    super.key,
    required this.kind,
    required this.id,
    this.title,
  });
  final String kind, id;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      'album' => 'Álbum',
      'artist' => 'Artista',
      'playlist' => 'Playlist',
      _ => 'Catálogo',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title ?? label)),
      body: SafeArea(
        child:
            !{'album', 'artist', 'playlist'}.contains(kind) ||
                !RegExp(r'^[A-Za-z0-9_-]{1,150}$').hasMatch(id)
            ? const Center(child: Text('Este elemento no está disponible.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  PublicMusicResults(
                    request: (path: '$kind/$id', query: null, filter: null),
                    detail: true,
                  ),
                ],
              ),
      ),
    );
  }
}

class PublicMusicResults extends ConsumerWidget {
  const PublicMusicResults({
    super.key,
    required this.request,
    this.detail = false,
  });
  final DiscoveryRequest request;
  final bool detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = discoveryPageProvider(request);
    final music = MusicModeScope.of(context);
    final generation = music?.connection?.generation;
    final linked = generation != null && music!.isCurrent(generation);
    return ref
        .watch(provider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              CatalogError(error: error, retry: () => ref.invalidate(provider)),
          data: (page) {
            if (page.items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  request.path == 'search'
                      ? 'Sin resultados para «${request.query}».'
                      : 'No hay música disponible en esta sección.',
                ),
              );
            }
            final playable = page.items
                .whereType<MusicTrack>()
                .where((item) => item.canPlayInMysic)
                .toList();
            void play(MusicTrack selected, {bool shuffle = false}) =>
                playDiscoveryQueue(
                  context,
                  ref,
                  playable,
                  selected,
                  generation,
                  shuffle: shuffle,
                );

            Widget? actionsFor(MusicItem item) {
              if (item is! MusicTrack || !item.canPlayInMysic) return null;
              return PopupMenuButton<bool>(
                tooltip: 'Opciones de ${item.title}',
                onSelected: (next) {
                  if (linked && !music.isCurrent(generation)) return;
                  final added = ref
                      .read(trackPlaybackControllerProvider)
                      .queueConnected(
                        [
                          linked
                              ? music.playbackTrack(generation, item)
                              : item.toPlaybackTrack(),
                        ],
                        next: next,
                        listenForTrack: linked
                            ? () => music.listenForTrack(generation)
                            : null,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        added ? 'Añadido a la cola' : 'La cola no cambió',
                      ),
                    ),
                  );
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: true,
                    child: Text('Reproducir a continuación'),
                  ),
                  PopupMenuItem(
                    value: false,
                    child: Text('Añadir al final de la cola'),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (detail && playable.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => play(playable.first),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Reproducir'),
                      ),
                      TextButton.icon(
                        onPressed: () => play(playable.first, shuffle: true),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Aleatorio'),
                      ),
                    ],
                  ),
                MusicShelves(
                  items: page.items,
                  listResults:
                      detail ||
                      (request.path == 'search' &&
                          request.filter != MusicSearchFilter.all),
                  actions: actionsFor,
                  open: (item) {
                    if (item is MusicTrack) {
                      play(item);
                    } else {
                      openCatalogDetail(context, item);
                    }
                  },
                ),
              ],
            );
          },
        );
  }
}
