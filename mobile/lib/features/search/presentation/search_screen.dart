import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  String _filter = 'Todo';
  String? _prefetchedId;
  void _changed(String value) {
    _debounce?.cancel();
    _cancelPrefetch();
    setState(() {
      _query = null;
      _filter = 'Todo';
    });
    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = query);
    });
  }

  void _clear() {
    FocusManager.instance.primaryFocus?.unfocus();
    _input.clear();
    _changed('');
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
        leading: _input.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Volver a explorar',
                onPressed: _clear,
                icon: const Icon(Icons.arrow_back),
              ),
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
                decoration: InputDecoration(
                  labelText: 'Canción o artista',
                  counterText: '',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _input.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar búsqueda',
                          onPressed: _clear,
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (query != null)
              SizedBox(
                height: 52,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final filter in ['Todo', 'Canciones', 'Artistas'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: _filter == filter,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                  ],
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
                            : _SearchResults(
                                key: ValueKey((query, _filter)),
                                query: query,
                                filter: _filter,
                                tracks: tracks,
                                selectFilter: (value) =>
                                    setState(() => _filter = value),
                                searchArtist: (artist) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  _input.text = artist;
                                  _changed(artist);
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

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    super.key,
    required this.query,
    required this.filter,
    required this.tracks,
    required this.selectFilter,
    required this.searchArtist,
  });
  final String query;
  final String filter;
  final List<CatalogTrack> tracks;
  final ValueChanged<String> selectFilter;
  final ValueChanged<String> searchArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final artists = tracks.map((track) => track.artistName).toSet().toList();
    final shown = filter == 'Todo' ? tracks.skip(1).take(3).toList() : tracks;
    return ListView(
      key: PageStorageKey((query, filter)),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (filter == 'Todo') ...[
          Text(
            'Mejor coincidencia',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(18),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: TrackArtwork(
                url: tracks.first.thumbnailUrl,
                size: 72,
                borderRadius: 12,
              ),
              title: Text(
                tracks.first.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Canción · ${tracks.first.artistName}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton.filled(
                tooltip: 'Reproducir mejor coincidencia',
                onPressed: () => playAndOpenPlayer(context, ref, tracks.first),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              onTap: () => playAndOpenPlayer(context, ref, tracks.first),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (filter != 'Artistas') ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Canciones',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (filter == 'Todo')
                TextButton(
                  onPressed: () => selectFilter('Canciones'),
                  child: const Text('Ver todo'),
                ),
            ],
          ),
          for (final track in shown) ...[
            _ResultRow(track: track),
            const Divider(height: 1),
          ],
        ],
        if (filter != 'Canciones') ...[
          const SizedBox(height: 20),
          Text(
            'Artistas en estos resultados',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final artist in artists)
                SizedBox(
                  width: 92,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => searchArtist(artist),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          child: Text(
                            artist.isEmpty
                                ? '?'
                                : String.fromCharCode(
                                    artist.runes.first,
                                  ).toUpperCase(),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          artist,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.track});
  final CatalogTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: TrackArtwork(url: track.thumbnailUrl, size: 48),
    title: Text(
      track.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      track.artistName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => playAndOpenPlayer(context, ref, track),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.durationLabel != null)
          Text(
            track.durationLabel!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        PopupMenuButton<String>(
          tooltip: 'Opciones de la canción',
          icon: const Icon(Icons.more_horiz),
          onSelected: (action) {
            if (action == 'details') {
              context.push('/tracks/${Uri.encodeComponent(track.id)}');
            } else {
              final controller = ref.read(trackPlaybackControllerProvider);
              final canAdd =
                  controller.queue.length < 100 &&
                  !controller.queue.any((item) => item.id == track.id);
              if (canAdd) controller.enqueue(track);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    canAdd
                        ? 'Cola actualizada'
                        : 'La canción ya está en la cola o la cola está llena.',
                  ),
                ),
              );
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'queue', child: Text('Añadir a la cola')),
            PopupMenuItem(
              value: 'details',
              child: Text('Detalles de la canción'),
            ),
          ],
        ),
      ],
    ),
  );
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
            color: Color.lerp(Colors.white, color, .14),
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
                      child: Icon(icon, size: 26, color: color),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        color: color,
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
