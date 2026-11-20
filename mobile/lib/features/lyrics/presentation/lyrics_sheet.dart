import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/application/track_playback_controller.dart';
import '../../search/domain/catalog_track.dart';
import '../data/lrclib_provider.dart';
import '../domain/lyrics_provider.dart';

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.controller});

  final TrackPlaybackController controller;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  CatalogTrack? _track;

  @override
  void initState() {
    super.initState();
    _track = widget.controller.current;
    widget.controller.addListener(_updateTrack);
  }

  void _updateTrack() {
    final next = widget.controller.current;
    if (identical(next, _track)) return;
    setState(() => _track = next);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateTrack);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return SafeArea(
      top: false,
      child: track == null || widget.controller.isDemoTrack
          ? const Center(child: Text('No hay letra para este audio.'))
          : _LyricsForTrack(
              key: ValueKey(track.id),
              track: track,
              controller: widget.controller,
            ),
    );
  }
}

class _LyricsForTrack extends ConsumerWidget {
  const _LyricsForTrack({
    super.key,
    required this.track,
    required this.controller,
  });

  final CatalogTrack track;
  final TrackPlaybackController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = trackLyricsProvider(track);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: ref
              .watch(provider)
              .when(
                skipLoadingOnRefresh: false,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('No se pudo cargar la letra.'),
                        TextButton(
                          onPressed: () => ref.invalidate(provider),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (lyrics) {
                  if (lyrics != null && lyrics.lines.isNotEmpty) {
                    return _TimedLyrics(
                      key: ObjectKey(lyrics),
                      lyrics: lyrics,
                      controller: controller,
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                    children: [
                      SelectableText(
                        lyrics?.plain ??
                            'No encontramos letra para esta canción.',
                        style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.7,
                        ),
                      ),
                      if (lyrics?.plain != null) const _Attribution(),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }
}

class _TimedLyrics extends StatefulWidget {
  const _TimedLyrics({
    super.key,
    required this.lyrics,
    required this.controller,
  });

  final SongLyrics lyrics;
  final TrackPlaybackController controller;

  @override
  State<_TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends State<_TimedLyrics> {
  late final _lineKeys = List.generate(
    widget.lyrics.lines.length,
    (_) => GlobalKey(),
  );
  var _active = -1;

  @override
  void initState() {
    super.initState();
    _active = widget.lyrics.lineAt(widget.controller.position);
    widget.controller.addListener(_positionChanged);
    _followLine();
  }

  void _positionChanged() {
    final next = widget.lyrics.lineAt(widget.controller.position);
    if (next == _active) return;
    setState(() => _active = next);
    _followLine();
  }

  void _followLine() {
    final index = _active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _active) return;
      final context = _lineKeys[index < 0 ? 0 : index].currentContext;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(
            context,
            alignment: index < 0 ? 0 : 0.30,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_positionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, line) in widget.lyrics.lines.indexed)
            Padding(
              key: _lineKeys[index],
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: line.text.isEmpty
                  ? const SizedBox(height: 4)
                  : Semantics(
                      selected: index == _active,
                      child: Text(
                        line.text,
                        style: theme.textTheme.titleLarge?.copyWith(
                          height: 1.25,
                          color: index == _active
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: index == _active
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
            ),
          const _Attribution(),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 18),
    child: Text('Letras de LRCLIB'),
  );
}
