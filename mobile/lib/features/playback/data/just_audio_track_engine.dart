import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/network/api_dio.dart';
import '../domain/track_audio_engine.dart';

class JustAudioTrackEngine implements TrackAudioEngine {
  JustAudioTrackEngine(String baseUrl) : _base = validatedApiUri(baseUrl);
  final Uri _base;
  Future<void>? _configuration;
  // Android envía Authorization directamente a nuestro backend, sin proxy local.
  AudioPlayer? _instance;
  AudioPlayer get _player => _instance ??= AudioPlayer(
    useProxyForRequestHeaders: false,
    handleInterruptions: false,
  );
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _states = StreamController<TrackAudioPhase>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _configured = false;
  bool _disposed = false;
  @override
  Stream<TrackAudioPhase> get states => _states.stream;
  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<Duration?> get durations => _durations.stream;
  @override
  Duration? get duration => _instance?.duration;
  void _emit(TrackAudioPhase phase) {
    if (!_disposed) _states.add(phase);
  }

  Future<void> _configure() async {
    if (_configured) return;
    final session = await AudioSession.instance;
    if (_disposed) return;
    await session.configure(const AudioSessionConfiguration.music());
    if (_disposed) return;
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _emit(TrackAudioPhase.interrupted);
          unawaited(pause());
        }
      }),
    );
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        _emit(TrackAudioPhase.interrupted);
        unawaited(pause());
      }),
    );
    _subscriptions.add(
      _player.errorStream.listen((error) {
        if (kDebugMode) debugPrint('audio_native_failed code=${error.code}');
        _emit(TrackAudioPhase.error);
      }),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering) {
          _emit(TrackAudioPhase.loading);
        } else if (state.processingState == ProcessingState.completed) {
          _emit(TrackAudioPhase.completed);
        } else if (state.processingState == ProcessingState.ready) {
          _emit(
            state.playing ? TrackAudioPhase.playing : TrackAudioPhase.paused,
          );
        }
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((value) {
        if (!_disposed) _positions.add(value);
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((value) {
        if (!_disposed) _durations.add(value);
      }),
    );
    _configured = true;
  }

  @override
  Future<void> load(String sourceId, String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId) || token.isEmpty) {
      throw StateError('Fuente inválida');
    }
    await (_configuration ??= _configure());
    if (_disposed) return;
    await _player
        .setUrl(
          _base.resolve('/api/v1/playback/audio/$sourceId').toString(),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 40));
  }

  @override
  Future<void> play() async {
    if (!_disposed) {
      unawaited(
        _player.play().catchError((Object _) => _emit(TrackAudioPhase.error)),
      );
    }
  }

  @override
  Future<void> pause() async {
    if (!_disposed) {
      try {
        await _player.pause();
      } catch (_) {
        _emit(TrackAudioPhase.error);
      }
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed || _instance == null || position.isNegative) return;
    final limit = _player.duration;
    await _player.seek(limit != null && position > limit ? limit : position);
  }

  @override
  Future<void> stop() async {
    if (!_disposed) await _instance?.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _instance?.dispose();
    await _positions.close();
    await _durations.close();
    await _states.close();
  }
}
