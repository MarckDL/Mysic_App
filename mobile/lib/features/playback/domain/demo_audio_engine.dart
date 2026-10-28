enum DemoPhase { idle, loading, ready, playing, paused, completed, error }

class DemoState {
  const DemoState(this.phase, {this.message});
  final DemoPhase phase;
  final String? message;
}

abstract interface class DemoAudioEngine {
  Stream<DemoState> get states;
  Future<void> load(String assetPath);
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}
