import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/playback_providers.dart';

class PlaybackAvailabilityPanel extends ConsumerStatefulWidget {
  const PlaybackAvailabilityPanel({super.key, required this.sourceId});
  final String sourceId;
  @override
  ConsumerState<PlaybackAvailabilityPanel> createState() =>
      _PlaybackAvailabilityPanelState();
}

class _PlaybackAvailabilityPanelState
    extends ConsumerState<PlaybackAvailabilityPanel> {
  bool _requested = false;
  @override
  Widget build(BuildContext context) {
    final provider = playbackAvailabilityProvider(widget.sourceId);
    final availability = _requested ? ref.watch(provider) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: availability?.isLoading == true
              ? null
              : () {
                  if (_requested) ref.invalidate(provider);
                  setState(() => _requested = true);
                },
          child: const Text('Comprobar reproducción'),
        ),
        if (availability != null)
          availability.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => const Text(
              'No se pudo comprobar la disponibilidad. Inténtalo de nuevo.',
            ),
            data: (result) => Text(
              result.reason ?? 'Esta fuente no está habilitada en el catálogo.',
            ),
          ),
      ],
    );
  }
}
