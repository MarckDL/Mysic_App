import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../search/presentation/catalog_widgets.dart';
import '../domain/music_mode.dart';
import 'music_shelf_heading.dart';
import 'community_playlist_rail.dart';

String catalogKind(MusicItem item) => switch (item) {
  MusicTrack() => item.isVideo ? 'video' : 'song',
  MusicArtist() => 'artist',
  MusicAlbum() => 'album',
  MusicPlaylist() => 'playlist',
};

String itemDescription(MusicItem item) =>
    item.subtitle ??
    switch (item) {
      MusicTrack() => item.artist,
      MusicAlbum() => 'Álbum',
      MusicPlaylist() => 'Playlist',
      MusicArtist() => 'Artista',
    };

Widget itemArtwork(MusicItem item, double size) => TrackArtwork(
  url: switch (item) {
    MusicTrack() => item.thumbnailUrl,
    MusicAlbum() => item.thumbnailUrl,
    MusicArtist() => item.thumbnailUrl,
    MusicPlaylist() => item.thumbnailUrl,
  },
  size: size,
  borderRadius: item is MusicArtist ? size / 2 : 10,
  fallbackIcon: switch (item) {
    MusicTrack() => item.isVideo ? Icons.music_video : Icons.music_note,
    MusicAlbum() => Icons.album_outlined,
    MusicPlaylist() => Icons.queue_music_rounded,
    MusicArtist() => Icons.person_outline_rounded,
  },
);

/// Renders consecutive shelves as returned by Music, including repeated items across shelves.
class MusicShelves extends StatelessWidget {
  const MusicShelves({
    super.key,
    required this.items,
    required this.open,
    this.actions,
    this.defaultTitle,
    this.listResults = false,
  });
  final List<MusicItem> items;
  final ValueChanged<MusicItem> open;
  final Widget? Function(MusicItem)? actions;
  final String? defaultTitle;
  final bool listResults;

  @override
  Widget build(BuildContext context) {
    final sections = <({String? title, List<MusicItem> items})>[];
    for (final item in items) {
      final title = musicShelfHeading(item.shelfTitle) ?? defaultTitle;
      if (sections.isEmpty || sections.last.title != title) {
        sections.add((title: title, items: <MusicItem>[]));
      }
      sections.last.items.add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          if (section.title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 17, 0, 9),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  if (!listResults && section.items.length > 3)
                    TextButton(
                      onPressed: () => _seeAll(context, title, section.items),
                      child: const Text('Ver todo'),
                    ),
                ],
              ),
            ),
          if (section.items.length == 1 &&
              section.title == 'Mejor coincidencia')
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                leading: itemArtwork(section.items.first, 60),
                title: Text(
                  section.items.first.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(itemDescription(section.items.first)),
                trailing: Icon(
                  section.items.first is MusicTrack
                      ? Icons.play_arrow
                      : Icons.chevron_right,
                ),
                onTap: () => open(section.items.first),
              ),
            )
          else if (!listResults &&
              section.title == 'De la comunidad' &&
              section.items.every((item) => item is MusicPlaylist))
            CommunityPlaylistRail(
              playlists: section.items.cast<MusicPlaylist>(),
              open: open,
            )
          else if (listResults ||
              (section.items.length == 1 && section.items.first is MusicTrack))
            for (final item in section.items) _row(item)
          else if (section.items.every(
            (item) => item is MusicTrack && !item.isVideo,
          ))
            _trackRail(context, section.items)
          else
            _coverRail(context, section.items),
        ],
      ],
    );
  }

  void _seeAll(BuildContext context, String title, List<MusicItem> entries) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _row(
                    entries[i],
                    onOpen: (item) {
                      Navigator.of(sheet).pop();
                      open(item);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(MusicItem item, {ValueChanged<MusicItem>? onOpen}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: itemArtwork(item, 46),
    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      itemDescription(item),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: actions?.call(item),
    onTap: () => (onOpen ?? open)(item),
  );

  Widget _trackRail(BuildContext context, List<MusicItem> entries) {
    const rows = 3;
    final rowHeight = math.max(
      76.0,
      MediaQuery.textScalerOf(context).scale(18) * 3 + 20,
    );
    final count = (entries.length + rows - 1) ~/ rows;
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = math.min(
          count == 1 ? bounds.maxWidth : bounds.maxWidth * .88,
          420.0,
        );
        return SizedBox(
          height: math.min(rows, entries.length) * rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (_, column) => SizedBox(
              width: width,
              child: Column(
                children: [
                  for (final item in entries.skip(column * rows).take(rows))
                    SizedBox(height: rowHeight, child: _row(item)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _coverRail(BuildContext context, List<MusicItem> entries) {
    final cardWidth = (MediaQuery.sizeOf(context).width * .35)
        .clamp(120.0, 162.0)
        .toDouble();
    final labelHeight = MediaQuery.textScalerOf(context).scale(16) * 4.6;
    return SizedBox(
      height: cardWidth + labelHeight + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final item = entries[i];
          return SizedBox(
            width: cardWidth,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => open(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        itemArtwork(item, cardWidth),
                        if (item is MusicTrack && item.isVideo)
                          const Positioned(
                            bottom: 6,
                            right: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xB3141110),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(5),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      itemDescription(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
