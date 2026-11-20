import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../playback/application/playback_providers.dart';
import '../domain/music_mode.dart';
import 'music_mode_host.dart';

void playDiscoveryQueue(
  BuildContext context,
  WidgetRef ref,
  List<MusicTrack> playable,
  MusicTrack selected,
  String? generation, {
  bool shuffle = false,
}) {
  final index = playable.indexOf(selected);
  final music = MusicModeScope.of(context);
  if (index < 0 ||
      (generation != null && (music == null || !music.isCurrent(generation)))) {
    return;
  }
  final start = index ~/ 100 * 100;
  final tracks = playable
      .skip(start)
      .take(100)
      .map(
        (track) => generation != null
            ? music!.playbackTrack(generation, track)
            : track.toPlaybackTrack(),
      )
      .toList();
  unawaited(
    ref
        .read(trackPlaybackControllerProvider)
        .playQueue(
          tracks,
          initialIndex: index - start,
          shuffled: shuffle,
          listenForTrack: generation == null
              ? null
              : () => music!.listenForTrack(generation),
        ),
  );
  context.push('/player');
}
