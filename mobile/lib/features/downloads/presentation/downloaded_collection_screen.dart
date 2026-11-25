import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/offline_mode.dart';
import '../../connected_library/presentation/catalog_pages.dart'
    show FloatingBack, PageSeed, StatusScrim, openAlbum;
import '../../playback/application/playback_providers.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../../search/presentation/music_tiles.dart' show AlbumDiscArt;
import '../data/download_store.dart';

/// La página de un álbum o una playlist descargados. Se ve igual que la página
/// normal del álbum (la portada con su medio disco, el título, el artista y las
/// pistas numeradas) pero con lo que hay en el teléfono, así que se abre con
/// internet o sin él, sin pedir nada a ningún servidor. Desde los tres puntos,
/// con internet, se puede abrir la página normal.
class DownloadedCollectionScreen extends ConsumerStatefulWidget {
  const DownloadedCollectionScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<DownloadedCollectionScreen> createState() =>
      _DownloadedCollectionScreenState();
}

class _DownloadedCollectionScreenState
    extends ConsumerState<DownloadedCollectionScreen> {
  final _store = DownloadStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  Future<void> _play(
    List<DownloadedTrack> tracks,
    int index, {
    bool shuffled = false,
  }) async {
    final dir = await _store.directory();
    if (dir == null || !mounted) return;
    final controller = ref.read(trackPlaybackControllerProvider);
    unawaited(
      controller.playQueue(
        [for (final track in tracks) _store.playable(track, dir)],
        initialIndex: index,
        shuffled: shuffled,
      ),
    );
    if (mounted) unawaited(context.push('/player'));
  }

  Future<void> _remove(DownloadedCollection collection) async {
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
    if (confirmed != true) return;
    await _store.releaseCollection(collection.id);
    if (mounted && context.canPop()) context.pop();
  }

  void _openOnline(DownloadedCollection collection) {
    final seed = PageSeed(
      title: collection.title,
      imageUrl: collection.thumbnailUrl,
    );
    if (collection.album) {
      openAlbum(context, collection.id, seed: seed);
    } else {
      unawaited(
        context.push(
          '/music/playlist/${Uri.encodeComponent(collection.id)}',
          extra: seed,
        ),
      );
    }
  }

  /// Los tres puntos: lo que se puede hacer sin internet con lo descargado.
  void _options(
    DownloadedCollection collection,
    List<DownloadedTrack> tracks,
  ) => unawaited(
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Reproducir'),
              enabled: tracks.isNotEmpty,
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_play(tracks, 0));
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle_rounded),
              title: const Text('Reproducir en aleatorio'),
              enabled: tracks.isNotEmpty,
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_play(tracks, 0, shuffled: true));
              },
            ),
            // La página normal, con todo lo que pide internet (el corazón, el
            // artista, más del artista…). Solo con internet.
            if (!OfflineMode.instance.active)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(
                  collection.album
                      ? 'Abrir la página del álbum'
                      : 'Abrir la página de la playlist',
                ),
                subtitle: const Text('Necesita internet'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (mounted) _openOnline(collection);
                },
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheet).colorScheme.error,
              ),
              title: const Text('Quitar descarga'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_remove(collection));
              },
            ),
          ],
        ),
      ),
    ),
  );

  static String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final theme = Theme.of(context), colors = theme.colorScheme;
      final collection = _store.collection(widget.id);
      if (collection == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Esta descarga ya no está.')),
        );
      }
      final tracks = _store.tracksOf(collection);
      final missing = collection.trackIds.length - tracks.length;
      final seconds = tracks.fold<int>(
        0,
        (sum, track) => sum + (track.durationSeconds ?? 0),
      );
      final width = MediaQuery.sizeOf(context).width;
      // La portada y su medio disco (45 % más de ancho) caben centrados.
      final cover = ((width - 64) / 1.45).clamp(120.0, 230.0).toDouble();
      final details = [
        '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}',
        if (seconds >= 60) '${seconds ~/ 60} minutos',
        if (missing > 0)
          missing == 1 ? 'falta 1 por bajar' : 'faltan $missing por bajar',
      ].join(' • ');
      return Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: tracks.length + 1,
              itemBuilder: (context, row) {
                if (row > 0) {
                  final index = row - 1, track = tracks[index];
                  return InkWell(
                    key: ValueKey('track:${track.id}'),
                    onTap: () => _play(tracks, index),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (track.durationSeconds != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                _time(track.durationSeconds!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        MediaQuery.paddingOf(context).top + 8,
                        12,
                        0,
                      ),
                      child: Row(
                        children: [
                          const FloatingBack(),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Opciones',
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(48),
                              backgroundColor: colors.surfaceContainerHighest
                                  .withValues(alpha: .82),
                              foregroundColor: colors.onSurface,
                            ),
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _options(collection, tracks),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: collection.album
                          ? AlbumDiscArt(
                              size: cover,
                              url: collection.thumbnailUrl,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: TrackArtwork(
                                url: collection.thumbnailUrl,
                                size: cover,
                                borderRadius: 0,
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 12, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  collection.album ? 'ÁLBUM' : 'PLAYLIST',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 1,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  collection.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontSize: 28,
                                        height: 1.14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          // El botón de descarga de la página normal: ya está
                          // descargada, así que se ve marcado; tocarlo ofrece
                          // quitarla.
                          IconButton(
                            tooltip: 'Descargado',
                            iconSize: 28,
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(52),
                            ),
                            color: colors.primary,
                            icon: const Icon(
                              Icons.download_for_offline_rounded,
                            ),
                            onPressed: () => unawaited(_remove(collection)),
                          ),
                        ],
                      ),
                    ),
                    if (collection.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: TextButton.icon(
                          onPressed: null,
                          style: TextButton.styleFrom(
                            disabledForegroundColor: colors.onSurface,
                          ),
                          icon: const Icon(Icons.person_rounded, size: 20),
                          label: Flexible(
                            child: Text(
                              collection.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Text(
                        details,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const StatusScrim(),
          ],
        ),
      );
    },
  );
}
