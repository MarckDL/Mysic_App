import 'dart:async';
import 'package:mysic/features/playback/domain/track_audio_engine.dart';

class FakeTrackAudioEngine implements TrackAudioEngine {
  final events = StreamController<TrackAudioPhase>.broadcast(sync: true);
  Completer<void>? pendingLoad;
  bool fail = false;
  String? sourceId;
  String? token;
  int plays = 0;
  int stops = 0;
  int disposals = 0;
  final seeks = <Duration>[];
  final prefetched = <String>[];
  int prefetchCancellations = 0;
  @override
  Duration? duration;
  @override
  Stream<TrackAudioPhase> get states => events.stream;
  @override
  Stream<Duration> get positions => const Stream.empty();
  @override
  Stream<Duration?> get durations => const Stream.empty();
  @override
  Future<void> load(String sourceId, String token) async {
    this.sourceId = sourceId;
    this.token = token;
    if (fail) throw StateError('Unavailable');
    await pendingLoad?.future;
  }

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
  }
}
