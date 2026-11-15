import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../search/domain/catalog_track.dart';
import '../application/playback_providers.dart';
import '../domain/track_audio_engine.dart';

void playAndOpenPlayer(
  BuildContext context,
  WidgetRef ref,
  CatalogTrack track,
) {
  final controller = ref.read(trackPlaybackControllerProvider);
  final queue = controller.queue;
  if (queue.length >= 100 && !queue.any((item) => item.id == track.id)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('La cola está llena. Quita una canción para continuar.'),
      ),
    );
    return;
  }

  FocusManager.instance.primaryFocus?.unfocus();
  if (controller.current?.id != track.id) {
    unawaited(controller.playTrack(track));
  } else if (controller.phase != TrackAudioPhase.playing &&
      controller.phase != TrackAudioPhase.loading) {
    unawaited(controller.resume());
  }
  context.push('/player');
}

void playTracksAndOpenPlayer(
  BuildContext context,
  WidgetRef ref,
  List<CatalogTrack> tracks,
) {
  if (tracks.isEmpty) return;
  FocusManager.instance.primaryFocus?.unfocus();
  unawaited(
    ref
        .read(trackPlaybackControllerProvider)
        .playQueue(tracks.take(100).toList(growable: false)),
  );
  context.push('/player');
}
