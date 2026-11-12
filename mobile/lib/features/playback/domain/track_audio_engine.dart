enum TrackAudioPhase {
  idle,
  loading,
  playing,
  paused,
  completed,
  error,
  interrupted,
}

abstract interface class TrackAudioEngine {
  Stream<TrackAudioPhase> get states;
  Stream<Duration> get positions;
  Stream<Duration?> get durations;
  Duration? get duration;
  Future<void> warmUp();
  void markPlaybackRequested();
  Future<void> load(String sourceId, String token);
  Future<void> prefetch(String sourceId, String token);
  void cancelPrefetch();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
