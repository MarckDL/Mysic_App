enum TrackAudioPhase {
  idle,
  loading,
  playing,
  paused,
  completed,
  error,
  interrupted,
}

/// A source could not be resolved or opened. A fresh URL may recover it.
class PlaybackSourceFailure implements Exception {
  const PlaybackSourceFailure();
}

/// A byte range from a track, supplied directly to the native player.
typedef TrackAudioReader =
    Future<TrackAudioRange> Function(int? start, int? end);

class TrackAudioRange {
  const TrackAudioRange(
    this.stream,
    this.contentType, {
    this.length,
    this.total,
    this.offset,
    required this.acceptsRanges,
  });
  final Stream<List<int>> stream;
  final String contentType;
  final int? length, total, offset;
  final bool acceptsRanges;
}

abstract interface class TrackAudioEngine {
  Stream<TrackAudioPhase> get states;
  Stream<Duration> get positions;
  Stream<Duration?> get durations;
  Duration? get duration;
  Future<void> warmUp();
  void markPlaybackRequested();
  Future<void> load(
    String sourceId,
    String token, {
    Uri? licensedAudio,
    Uri? deviceAudio,
    TrackAudioReader? readAudio,
    bool refresh = false,
  });
  void cancelLoad();
  Future<void> prefetch(String sourceId, String token);
  void cancelPrefetch();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
