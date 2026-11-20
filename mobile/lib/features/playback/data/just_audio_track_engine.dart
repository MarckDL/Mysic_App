import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/playback_resolution.dart';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/playback_source_resolver.dart';
import '../domain/track_audio_engine.dart';

class JustAudioTrackEngine implements TrackAudioEngine {
  JustAudioTrackEngine(
    String baseUrl, {
    PlaybackSourceResolver? sourceResolver,
    AudioPlayer? player,
  }) : _sourceResolver =
           sourceResolver ?? createPlaybackSourceResolver(baseUrl),
       _instance = player;
  final PlaybackSourceResolver _sourceResolver;
  Future<void>? _configuration;
  Future<void>? _resolverWarmUp;
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
  int _loadGeneration = 0;
  bool _currentLoad(int generation) =>
      !_disposed && generation == _loadGeneration;
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
    // A second selection must reach the native resolver even while it is busy.
    final warming = _resolverWarmUp ??= _sourceResolver.warmUp();
    try {
      await warming;
    } catch (_) {
      if (identical(_resolverWarmUp, warming)) _resolverWarmUp = null;
      rethrow;
    }
  }

  @override
  void markPlaybackRequested() {
    _audibleTimer = Stopwatch()..start();
    _firstProgressArmed = false;
  }

  @override
  Future<void> load(
    String sourceId,
    String token, {
    Uri? licensedAudio,
    Uri? deviceAudio,
    bool refresh = false,
  }) async {
    final demo = sourceId == PlaybackResolution.demoId;
    if ((!demo && !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId)) ||
        token.isEmpty) {
      throw StateError('Fuente inválida');
    }
    cancelLoad();
    final generation = _loadGeneration;
    try {
      if (demo || licensedAudio != null || deviceAudio != null) {
        await (_configuration ??= _configure());
      } else {
        await warmUp();
      }
      if (!_currentLoad(generation)) return;
      final resolutionTimer = Stopwatch()..start();
      final AudioSource audio;
      if (deviceAudio != null) {
        if (deviceAudio.scheme != 'file' ||
            deviceAudio.host.isNotEmpty ||
            deviceAudio.hasQuery ||
            deviceAudio.hasFragment ||
            !deviceAudio.path.startsWith('/')) {
          throw StateError('Archivo de audio inválido');
        }
        audio = AudioSource.file(deviceAudio.toFilePath());
      } else if (licensedAudio != null) {
        if (licensedAudio.scheme != 'https' ||
            licensedAudio.host.isEmpty ||
            licensedAudio.userInfo.isNotEmpty ||
            licensedAudio.hasQuery ||
            licensedAudio.hasFragment) {
          throw StateError('Fuente de audio inválida');
        }
        audio = AudioSource.uri(licensedAudio);
      } else if (demo) {
        audio = AudioSource.asset(PlaybackResolution.demoAsset);
      } else {
        final source = await _sourceResolver.resolve(
          sourceId,
          token,
          refresh: refresh,
        );
        audio = AudioSource.uri(source.uri, headers: source.headers);
      }
      if (!_currentLoad(generation)) return;
      debugPrint(
        'audio_source_resolution durationMs=${resolutionTimer.elapsedMilliseconds}',
      );
      final preparationTimer = Stopwatch()..start();
      await _player
          .setAudioSource(audio, preload: true)
          .timeout(const Duration(seconds: 40));
      if (!_currentLoad(generation)) return;
      _firstProgressArmed = true;
      debugPrint(
        'audio_player_preparation durationMs=${preparationTimer.elapsedMilliseconds}',
      );
    } on TimeoutException {
      if (_currentLoad(generation)) throw const PlaybackSourceFailure();
    } on PlayerException {
      if (_currentLoad(generation)) throw const PlaybackSourceFailure();
    } on PlatformException catch (error) {
      if (!_currentLoad(generation)) return;
      if (error.code == 'RESOLUTION_FAILED') {
        throw const PlaybackSourceFailure();
      }
      rethrow;
    } catch (_) {
      if (_currentLoad(generation)) rethrow;
    }
  }

  @override
  void cancelLoad() {
    _loadGeneration++;
    _firstProgressArmed = false;
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
      final generation = _loadGeneration;
      unawaited(
        _player.play().catchError((Object _) {
          if (_currentLoad(generation)) _emit(TrackAudioPhase.error);
        }),
      );
    }
  }

  @override
  Future<void> pause() async {
    if (!_disposed) {
      final generation = _loadGeneration;
      try {
        await _player.pause();
      } catch (_) {
        if (_currentLoad(generation)) _emit(TrackAudioPhase.error);
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
    cancelLoad();
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
