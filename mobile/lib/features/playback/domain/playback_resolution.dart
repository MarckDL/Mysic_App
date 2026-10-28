class PlaybackFailure implements Exception {
  const PlaybackFailure(this.message);
  final String message;
}

class PlaybackResolution {
  const PlaybackResolution._({this.assetPath, this.reason});
  static const demoId = 'mysic-tone-v1';
  static const demoAsset = 'assets/audio/mysic-demo.wav';
  final String? assetPath;
  final String? reason;
  bool get available => assetPath != null;

  factory PlaybackResolution.fromJson(Map<String, dynamic> data) {
    if (data['mode'] == 'unavailable' &&
        data['reason'] is String &&
        (data['reason'] as String).isNotEmpty &&
        (data['reason'] as String).length <= 300) {
      return PlaybackResolution._(reason: data['reason'] as String);
    }
    if (data['mode'] == 'direct' &&
        data['delivery'] == 'asset' &&
        data['assetPath'] == demoAsset &&
        data['contentType'] == 'audio/wav' &&
        data['durationSeconds'] == 8 &&
        !data.containsKey('url')) {
      return const PlaybackResolution._(assetPath: demoAsset);
    }
    throw const PlaybackFailure('La fuente de audio no está habilitada.');
  }
}
