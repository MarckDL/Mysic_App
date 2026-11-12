import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/playback_source_resolver.dart';
import '../domain/track_audio_engine.dart';

class JustAudioTrackEngine implements TrackAudioEngine {
  JustAudioTrackEngine(String baseUrl, {PlaybackSourceResolver? sourceResolver})
    : _sourceResolver = sourceResolver ?? createPlaybackSourceResolver(baseUrl);
  final PlaybackSourceResolver _sourceResolver;
  Future<void>? _configuration;
  AudioPlayer? _instance;
  AudioPlayer get _player => _instance ??= AudioPlayer(
    useProxyForRequestHeaders: false,
    handleInterruptions: false,
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 3),
        maxBufferDuration: Duration(seconds: 15),
        bufferForPlaybackDuration: Duration(milliseconds: 250),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 1),
        targetBufferBytes: 1024 * 1024,
        prioritizeTimeOverSizeThresholds: false,
      ),
    ),
  );
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _states = StreamController<TrackAudioPhase>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _configured = false;
  bool _disposed = false;
  Stopwatch? _audibleTimer;
  bool _firstProgressArmed = false;
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
        if (value > Duration.zero &&
            _audibleTimer != null &&
            _firstProgressArmed) {
          debugPrint(
            'audio_first_progress durationMs=${_audibleTimer!.elapsedMilliseconds}',
          );
          _audibleTimer = null;
          _firstProgressArmed = false;
        }
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
  Future<void> warmUp() async {
    if (_disposed) return;
    _player;
    await (_configuration ??= _configure());
    if (_disposed) return;
    await _sourceResolver.warmUp();
  }

  @override
  void markPlaybackRequested() {
    _audibleTimer = Stopwatch()..start();
    _firstProgressArmed = false;
  }

  @override
  Future<void> load(String sourceId, String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId) || token.isEmpty) {
      throw StateError('Fuente inválida');
    }
    await warmUp();
    if (_disposed) return;
    final resolutionTimer = Stopwatch()..start();
    final source = await _sourceResolver.resolve(sourceId, token);
    debugPrint(
      'audio_source_resolution durationMs=${resolutionTimer.elapsedMilliseconds}',
    );
    if (_disposed) return;
    final preparationTimer = Stopwatch()..start();
    await _player
        .setAudioSource(
          AudioSource.uri(source.uri, headers: source.headers),
          preload: true,
        )
        .timeout(const Duration(seconds: 40));
    _firstProgressArmed = true;
    debugPrint(
      'audio_player_preparation durationMs=${preparationTimer.elapsedMilliseconds}',
    );
  }

  @override
  Future<void> prefetch(String sourceId, String token) async {
    if (_disposed ||
        !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId) ||
        token.isEmpty) {
      return;
    }
    cancelPrefetch();
    await _sourceResolver.prefetch(sourceId, token);
  }

  @override
  void cancelPrefetch() {
    _sourceResolver.cancelPrefetch();
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
    _firstProgressArmed = false;
    if (!_disposed) await _instance?.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelPrefetch();
    await _sourceResolver.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _instance?.dispose();
    await _positions.close();
    await _durations.close();
    await _states.close();
  }
}
