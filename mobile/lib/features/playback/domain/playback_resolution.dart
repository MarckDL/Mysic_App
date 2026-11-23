class PlaybackFailure implements Exception {
  const PlaybackFailure(this.message);
  final String message;
}

/// La pista de demostración que lleva la app (un tono corto): no necesita red.
class PlaybackResolution {
  const PlaybackResolution._();
  static const demoId = 'mysic-tone-v1';
  static const demoAsset = 'assets/audio/mysic-demo.wav';
}
