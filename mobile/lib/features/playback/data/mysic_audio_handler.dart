import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../application/track_playback_controller.dart';
import '../domain/track_audio_engine.dart';
import '../../search/domain/catalog_track.dart';

// Adaptador de controles del sistema; el controlador de sesión conserva la lógica.
class MysicAudioHandler extends BaseAudioHandler {
  TrackPlaybackController? _controller;
  List<CatalogTrack> _publishedQueue = const [];
  CatalogTrack? _publishedCurrent;
  TrackAudioPhase? _publishedPhase;
  int? _publishedIndex;
  Duration? _publishedDuration;
  void bind(TrackPlaybackController controller) {
    final old = _controller;
    if (old != null) old.removeListener(_publish);
    _controller = controller;
    _publishedPhase = null;
    controller.addListener(_publish);
    _publish();
  }

  void unbind(TrackPlaybackController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_publish);
    _controller = null;
    _publishedQueue = const [];
    _publishedCurrent = null;
    _publishedPhase = null;
    _publishedIndex = null;
    _publishedDuration = null;
    queue.add(const []);
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }

  MediaItem _item(CatalogTrack track, [Duration? actualDuration]) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artistName,
    duration:
        actualDuration ??
        (track.durationSeconds == null
            ? null
            : Duration(seconds: track.durationSeconds!)),
    artUri: track.thumbnailUrl == null
        ? null
        : Uri.tryParse(track.thumbnailUrl!),
  );
  void _publish() {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.current;
    final phase = controller.phase;
    final nextQueue = controller.queue;
    final queueChanged = !listEquals(_publishedQueue, nextQueue);
    if (queueChanged) {
      queue.add(nextQueue.map(_item).toList(growable: false));
      _publishedQueue = nextQueue;
    }
    if (!identical(current, _publishedCurrent) ||
        controller.duration != _publishedDuration) {
      mediaItem.add(
        current == null ? null : _item(current, controller.duration),
      );
      _publishedDuration = controller.duration;
      _publishedCurrent = current;
    }
    // El sistema extrapola la posición entre cambios de estado, sin emitir cada tick.
    if (!queueChanged &&
        _publishedPhase == phase &&
        _publishedIndex == controller.index) {
      return;
    }
    _publishedPhase = phase;
    _publishedIndex = controller.index;
    final controls = <MediaControl>[
      if (controller.hasPrevious) MediaControl.skipToPrevious,
      if (current != null)
        (phase == TrackAudioPhase.playing || phase == TrackAudioPhase.loading)
            ? MediaControl.pause
            : MediaControl.play,
      if (controller.hasNext) MediaControl.skipToNext,
      if (current != null) MediaControl.stop,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: List.generate(
          controls.length.clamp(0, 3),
          (i) => i,
        ),
        systemActions: current == null ? const {} : const {MediaAction.seek},
        processingState: switch (phase) {
          TrackAudioPhase.idle => AudioProcessingState.idle,
          TrackAudioPhase.loading => AudioProcessingState.loading,
          TrackAudioPhase.playing ||
          TrackAudioPhase.paused ||
          TrackAudioPhase.interrupted => AudioProcessingState.ready,
          TrackAudioPhase.completed => AudioProcessingState.completed,
          TrackAudioPhase.error => AudioProcessingState.error,
        },
        playing:
            phase == TrackAudioPhase.playing ||
            phase == TrackAudioPhase.loading,
        updatePosition: controller.position,
        bufferedPosition: controller.position,
        queueIndex: current == null ? null : controller.index,
        errorCode: phase == TrackAudioPhase.error ? 1 : null,
        errorMessage: phase == TrackAudioPhase.error
            ? 'No se pudo reproducir esta pista. Puedes reintentar o elegir la siguiente.'
            : null,
      ),
    );
  }

  @override
  Future<void> play() async => _controller?.resume();
  @override
  Future<void> pause() async => _controller?.pause();
  @override
  Future<void> stop() async => _controller?.stop();
  @override
  Future<void> skipToNext() async => _controller?.next();
  @override
  Future<void> skipToPrevious() async => _controller?.previous();
  @override
  Future<void> skipToQueueItem(int index) async => _controller?.jump(index);
  @override
  Future<void> seek(Duration position) async {
    await _controller?.seek(position);
    _publishedPhase = null;
    _publish();
  }

  @override
  Future<void> onTaskRemoved() async {
    await _controller?.clear();
  }
}
