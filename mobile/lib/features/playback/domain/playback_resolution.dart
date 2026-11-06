class PlaybackFailure implements Exception {
  const PlaybackFailure(this.message);
  final String message;
}

class PlaybackResolution {
  const PlaybackResolution._({
    this.assetPath,
    this.reason,
    this.streamPath,
    this.sourceId,
  });
  static const demoId = 'mysic-tone-v1';
  static const demoAsset = 'assets/audio/mysic-demo.wav';
  final String? assetPath;
  final String? reason;
  final String? streamPath;
  final String? sourceId;
  bool get available => assetPath != null || streamPath != null;

  factory PlaybackResolution.fromJson(Map<String, dynamic> data) {
    if (data['mode'] == 'unavailable' &&
        data['reason'] is String &&
        (data['reason'] as String).isNotEmpty &&
        (data['reason'] as String).length <= 300) {
      return PlaybackResolution._(reason: data['reason'] as String);
    }
    if (data['mode'] == 'direct' &&
        data['delivery'] == 'api-stream' &&
        data['sourceId'] is String &&
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(data['sourceId'] as String) &&
        data['path'] == '/api/v1/playback/audio/${data['sourceId']}' &&
        data['contentType'] == 'audio/mp4' &&
        data['seekable'] == false &&
        data['availabilityVerified'] == false &&
        !data.containsKey('url')) {
      return PlaybackResolution._(
        streamPath: data['path'] as String,
        sourceId: data['sourceId'] as String,
      );
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
