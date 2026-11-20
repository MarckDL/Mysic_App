import 'dart:async';

import 'package:flutter/material.dart';

import '../application/track_playback_controller.dart';
import 'player_widgets.dart';

class PlaybackProgress extends StatefulWidget {
  const PlaybackProgress({super.key, required this.controller});

  final TrackPlaybackController controller;

  @override
  State<PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<PlaybackProgress> {
  double? _preview;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final length = controller.duration?.inMilliseconds ?? 0;
    final current = (_preview ?? controller.position.inMilliseconds.toDouble())
        .clamp(0, length)
        .toDouble();
    final slider = Semantics(
      label: 'Posición de reproducción',
      child: Slider(
        value: current,
        max: length > 0 ? length.toDouble() : 1,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onChanged: controller.canSeek
            ? (value) => setState(() => _preview = value)
            : null,
        onChangeEnd: controller.canSeek
            ? (value) {
                setState(() => _preview = null);
                unawaited(
                  controller.seek(Duration(milliseconds: value.round())),
                );
              }
            : null,
        semanticFormatterCallback: (value) =>
            audioTime(Duration(milliseconds: value.round())),
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: theme.colorScheme.outlineVariant,
              disabledInactiveTrackColor:
                  theme.colorScheme.surfaceContainerHighest,
              trackHeight: 3,
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: slider,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(audioTime(Duration(milliseconds: current.round()))),
            Text(length > 0 ? audioTime(Duration(milliseconds: length)) : '—'),
          ],
        ),
      ],
    );
  }
}
