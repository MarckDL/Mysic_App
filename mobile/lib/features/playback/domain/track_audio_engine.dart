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
  Future<void> load(String sourceId, String token);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}
