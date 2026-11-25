import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/offline_mode.dart';
import '../../../core/settings/app_settings.dart';
import '../../playback/application/playback_providers.dart';
import '../../connected_library/domain/music_mode.dart'
    show MusicAlbum, MusicPlaylist;
import '../../connected_library/presentation/catalog_pages.dart'
    show PageSeed, openAlbum;
import '../../connected_library/presentation/track_sheet.dart'
    show showItemMenu;
import '../../connected_library/presentation/library_screen.dart'
    show LibraryCoverTile;
import '../../playback/presentation/player_widgets.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../application/download_sort_provider.dart';
import '../data/download_store.dart';
import '../domain/download_sort.dart';
import 'download_sort_sheet.dart';

/// Las canciones descargadas, en su propia pantalla (se abre desde Ajustes).
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Descargas')),
    body: const SafeArea(top: false, child: DownloadsList()),
  );
}

/// Pantalla de inicio con «solo canciones descargadas»: sustituye a las
/// pestañas, que necesitan internet, por la lista de descargas.
class OfflineHome extends ConsumerWidget {
  const OfflineHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(trackPlaybackControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Descargas'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: const Column(
        children: [
          _OfflineBanner(),
          Expanded(child: DownloadsList()),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(
            controller: controller,
            open: () => context.push('/player'),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Aviso de que no se está usando internet, con la salida correspondiente: si
/// el modo se activó solo por falta de conexión, reintentar; si lo eligió el
/// usuario, desactivarlo.
class _OfflineBanner extends ConsumerStatefulWidget {
  const _OfflineBanner();

  @override
  ConsumerState<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<_OfflineBanner> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    final online = await OfflineMode.instance.retry();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sigue sin haber internet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = OfflineMode.instance;
    final automatic = mode.automatic && !mode.manual;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              automatic ? Icons.wifi_off : Icons.download_done,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                automatic
                    ? 'Sin conexión: solo se reproducen las canciones '
                          'descargadas.'
                    : 'Modo «Solo canciones descargadas»: no se usa internet '
                          'ni datos.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: _checking
                  ? null
                  : automatic
                  ? _retry
                  : () => ref.read(offlineOnlyProvider.notifier).set(false),
              child: Text(automatic ? 'Reintentar' : 'Desactivar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abre la página de una colección descargada. Con internet, la página normal
/// del álbum o de la playlist (con todo lo demás); sin él, la propia de lo
/// descargado. Nunca hace sonar nada por sí sola.
void openDownloadedCollection(
  BuildContext context,
  DownloadedCollection collection,
) {
  if (OfflineMode.instance.active) {
    context.push('/downloads/collection/${Uri.encodeComponent(collection.id)}');
    return;
  }
  final seed = PageSeed(
    title: collection.title,
    imageUrl: collection.thumbnailUrl,
  );
  if (collection.album) {
    openAlbum(context, collection.id, seed: seed);
  } else {
    context.push(
      '/music/playlist/${Uri.encodeComponent(collection.id)}',
      extra: seed,
    );
  }
}

/// Lista de descargas: las que están bajando, los fallos, y las canciones.
class DownloadsList extends ConsumerStatefulWidget {
  const DownloadsList({super.key});

  @override
  ConsumerState<DownloadsList> createState() => _DownloadsListState();
}

class _DownloadsListState extends ConsumerState<DownloadsList> {
  final _store = DownloadStore.instance;
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _play(
    List<DownloadedTrack> list,
    int index, {
    bool shuffled = false,
  }) async {
    final dir = await _store.directory();
    if (dir == null || !mounted) return;
    final start = index ~/ 100 * 100;
    final queue = [
      for (final track in list.skip(start).take(100))
        _store.playable(track, dir),
    ];
    final controller = ref.read(trackPlaybackControllerProvider);
    unawaited(
      controller.playQueue(
        queue,
        initialIndex: index - start,
        shuffled: shuffled,
      ),
    );
    if (mounted) unawaited(context.push('/player'));
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).round()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(downloadSortProvider);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final all = sort.apply(_store.tracks);
        final text = _filter.text.trim().toLowerCase();
        final shown = text.isEmpty
            ? all
            : [
                for (final track in all)
                  if (track.title.toLowerCase().contains(text) ||
                      track.artist.toLowerCase().contains(text))
                    track,
              ];
        final pending = _store.pending;
        final failures = _store.failures;
        final total = all.fold<int>(0, (sum, track) => sum + track.bytes);
        if (all.isEmpty && pending.isEmpty && failures.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Aún no hay canciones descargadas.\nUsa «Descargar» en el menú '
                'de una canción para oírla sin internet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${all.length} '
                        '${all.length == 1 ? 'canción' : 'canciones'} · '
                        '${_size(total)}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Reproducir todo',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: shown.isEmpty ? null : () => _play(shown, 0),
                    ),
                    IconButton(
                      tooltip: 'Aleatorio',
                      icon: const Icon(Icons.shuffle),
                      onPressed: shown.isEmpty
                          ? null
                          : () => _play(shown, 0, shuffled: true),
                    ),
                    const DownloadSortButton(),
                  ],
                ),
              ),
            // Los álbumes y playlists descargados enteros, también sin
            // internet.
            if (_store.collections.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Álbumes y playlists',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _collections(_store.collections),
            ],
            if (all.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar en las descargas',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            for (final track in pending)
              ListTile(
                leading: TrackArtwork(url: track.thumbnailUrl, size: 48),
                title: Text(track.title, maxLines: 1),
                subtitle: _PendingProgress(
                  progress: _store.progressOf(track.id.substring(8)),
                ),
              ),
            for (final failure in failures)
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(failure.title, maxLines: 1),
                subtitle: Text(failure.reason),
                trailing: IconButton(
                  tooltip: 'Descartar',
                  icon: const Icon(Icons.close),
                  onPressed: () => _store.dismissFailure(failure.id),
                ),
              ),
            for (final (index, track) in shown.indexed)
              ListTile(
                key: ValueKey(track.id),
                leading: DownloadCover(track: track),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    track.artist,
                    // Ordenadas por álbum, se ve de cuál es cada una.
                    if (sort.key == DownloadSortKey.album &&
                        (track.albumName?.isNotEmpty ?? false))
                      track.albumName!,
                    if (track.durationSeconds != null)
                      _duration(track.durationSeconds!),
                    _size(track.bytes),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Quitar descarga',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(_remove(track)),
                ),
                onTap: () => _play(shown, index),
              ),
          ],
        );
      },
    );
  }

  /// La cuadrícula de colecciones: tocar una hace sonar sus canciones
  /// descargadas; mantener pulsada ofrece quitar su descarga.
  Widget _collections(List<DownloadedCollection> collections) => LayoutBuilder(
    builder: (context, box) {
      final columns = (box.maxWidth / 170).round().clamp(3, 12);
      final cell = (box.maxWidth - 12) / columns;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent:
              (cell - 20) + 16 + MediaQuery.textScalerOf(context).scale(58),
        ),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final collection = collections[index];
          final have = _store.tracksOf(collection).length;
          final total = collection.trackIds.length;
          final kind = collection.album ? 'Álbum' : 'Playlist';
          return LibraryCoverTile(
            key: ValueKey('downloaded:${collection.id}'),
            title: collection.title,
            subtitle: have < total
                ? '$kind · $have de $total'
                : collection.album && collection.subtitle != null
                ? '$kind · ${collection.subtitle}'
                : kind,
            url: collection.thumbnailUrl,
            icon: collection.album ? Icons.album : Icons.queue_music,
            onTap: () => openDownloadedCollection(context, collection),
            onLongPress: () => _holdCollection(collection),
          );
        },
      );
    },
  );

  /// Mantener pulsada una colección: con internet, el menú completo del
  /// álbum o la playlist (incluye quitar la descarga); sin él, quitarla.
  void _holdCollection(DownloadedCollection collection) {
    if (OfflineMode.instance.active) {
      unawaited(_removeCollection(collection));
      return;
    }
    unawaited(
      showItemMenu(
        context,
        ref,
        collection.album
            ? MusicAlbum(
                collection.id,
                collection.title,
                thumbnailUrl: collection.thumbnailUrl,
                artist: collection.subtitle,
              )
            : MusicPlaylist(
                collection.id,
                collection.title,
                false,
                thumbnailUrl: collection.thumbnailUrl,
              ),
      ),
    );
  }

  Future<void> _removeCollection(DownloadedCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(collection.title),
        content: const Text(
          '¿Quitar la descarga? Las canciones que no guarde otro álbum o '
          'playlist dejarán de estar en el teléfono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar descarga'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.releaseCollection(collection.id);
  }

  Future<void> _remove(DownloadedTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar la descarga?'),
        content: Text('«${track.title}» dejará de estar en el teléfono.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.remove(track.id);
  }

  static String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _PendingProgress extends StatelessWidget {
  const _PendingProgress({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: LinearProgressIndicator(
      // -1: aún no se conoce el tamaño.
      value: progress == null || progress! < 0 ? null : progress,
    ),
  );
}

/// La portada guardada con la canción; si falta, la de la red o su caché.
class DownloadCover extends StatelessWidget {
  const DownloadCover({super.key, required this.track});

  final DownloadedTrack track;

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: DownloadStore.instance.coverFile(track.id),
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null) return TrackArtwork(url: track.thumbnailUrl, size: 48);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 48,
          // Las miniaturas de vídeo llevan franjas negras: se amplían.
          child: Transform.scale(
            scale: TrackArtwork.zoomFor(track.thumbnailUrl),
            child: Image.file(
              file,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              cacheWidth: 144,
              errorBuilder: (context, error, stack) =>
                  TrackArtwork(url: track.thumbnailUrl, size: 48),
            ),
          ),
        ),
      );
    },
  );
}
