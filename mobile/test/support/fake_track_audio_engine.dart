import 'dart:async';

import 'package:mysic/features/playback/domain/track_audio_engine.dart';

class FakeTrackAudioEngine implements TrackAudioEngine {
  final events = StreamController<TrackAudioPhase>.broadcast(sync: true);
  final positionEvents = StreamController<Duration>.broadcast(sync: true);
  Completer<void>? pendingLoad;
  bool fail = false;

  /// Si no es null, `load` lanza exactamente esto.
  Object? failure;
  String? sourceId;
  String? token;
  Uri? lastLicensedAudio;
  TrackAudioReader? lastReader;
  Uri? lastDeviceAudio;
  Uri? lastLiveAudio;
  int? lastDurationSeconds;
  int plays = 0;
  int stops = 0;
  int disposals = 0;
  int warmUps = 0;
  final seeks = <Duration>[];
  final prefetched = <String>[];
  int prefetchCancellations = 0;
  @override
  Duration? duration;
  @override
  Stream<TrackAudioPhase> get states => events.stream;
  @override
  Stream<Duration> get positions => positionEvents.stream;
  @override
  Stream<Duration?> get durations => const Stream.empty();
  final liveTitleEvents = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get liveTitles => liveTitleEvents.stream;
  @override
  Future<void> warmUp() async {
    warmUps++;
  }

  @override
  void markPlaybackRequested() {}

  @override
  void cancelLoad() {}

  @override
  Future<void> load(
    String sourceId,
    String token, {
    Uri? licensedAudio,
    Uri? deviceAudio,
    TrackAudioReader? readAudio,
    Uri? liveAudio,
    bool refresh = false,
    int? durationSeconds,
  }) async {
    lastLiveAudio = liveAudio;
    lastDurationSeconds = durationSeconds;
    this.sourceId = sourceId;
    lastLicensedAudio = licensedAudio;
    lastReader = readAudio;
    lastDeviceAudio = deviceAudio;
    this.token = token;
    if (failure != null) throw failure!;
    if (fail) throw StateError('Unavailable');
    await pendingLoad?.future;
  }

  final warmed = <List<String>>[];
  final touched = <String>[];

  @override
  void touch(String sourceId) => touched.add(sourceId);
  @override
  void warm(List<String> sourceIds) => warmed.add(sourceIds);

  @override
  Future<void> prefetch(String sourceId, String token) async {
    prefetched.add(sourceId);
  }

  @override
  void cancelPrefetch() {
    prefetchCancellations++;
  }

  @override
  Future<void> play() async {
    plays++;
    events.add(TrackAudioPhase.playing);
  }

  @override
  Future<void> pause() async {
    events.add(TrackAudioPhase.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
    await positionEvents.close();
  }
}
