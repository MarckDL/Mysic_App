import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/playback_resolution.dart';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/network/offline_mode.dart';
import '../../downloads/data/download_store.dart';
import '../domain/playback_source_resolver.dart';
import '../domain/track_audio_engine.dart';
import 'account_audio_source.dart';
import 'audio_disk_cache.dart';

class JustAudioTrackEngine
    implements TrackAudioEngine, TrackAudioTuning, TrackAudioFade {
  JustAudioTrackEngine({
    PlaybackSourceResolver? sourceResolver,
    AudioPlayer? player,
    this.keepAudio,
  }) : _sourceResolver = sourceResolver ?? createPlaybackSourceResolver(),
       _instance = player;

  /// Si el usuario quiere guardar en disco el audio que escucha.
  final bool Function()? keepAudio;
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
    // El calentado del resolvedor abre conexiones: no con «solo descargadas».
    if (_disposed || OfflineMode.instance.active) return;
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
    TrackAudioReader? readAudio,
    bool refresh = false,
    int? durationSeconds,
  }) async {
    final demo = sourceId == PlaybackResolution.demoId;
    if ((!demo && !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId)) ||
        token.isEmpty) {
      throw StateError('Fuente inválida');
    }
    cancelLoad();
    final generation = _loadGeneration;
    try {
      final ownSource =
          demo ||
          licensedAudio != null ||
          deviceAudio != null ||
          readAudio != null;
      // Una canción descargada suena del archivo, sin resolver ni usar datos.
      final downloaded = ownSource
          ? null
          : await DownloadStore.instance.file(sourceId);
      if (ownSource || downloaded != null) {
        await (_configuration ??= _configure());
      } else {
        // Con «solo canciones descargadas» no se abre ninguna conexión.
        if (OfflineMode.instance.active) throw const PlaybackSourceFailure();
        await warmUp();
      }
      if (!_currentLoad(generation)) return;
      final resolutionTimer = Stopwatch()..start();
      final AudioSource audio;
      Uri? networkUri;
      Map<String, String> networkHeaders = const {};
      if (deviceAudio != null) {
        if (deviceAudio.scheme != 'file' ||
            deviceAudio.host.isNotEmpty ||
            deviceAudio.hasQuery ||
            deviceAudio.hasFragment ||
            !deviceAudio.path.startsWith('/')) {
          throw StateError('Archivo de audio inválido');
        }
        audio = AudioSource.file(deviceAudio.toFilePath());
      } else if (readAudio != null) {
        audio = AccountAudioSource(readAudio);
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
      } else if (downloaded != null) {
        audio = AudioSource.file(downloaded.path);
      } else {
        // Los vídeos largos no se guardan: se bajarían enteros en segundo
        // plano aunque solo se escuche un rato.
        final keep =
            (keepAudio?.call() ?? false) &&
            AudioDiskCache.worthKeeping(durationSeconds);
        // Tras un fallo (refresh) no se confía en lo guardado.
        if (keep && refresh) await AudioDiskCache.instance.remove(sourceId);
        final stored = keep
            ? await AudioDiskCache.instance.complete(sourceId)
            : null;
        if (stored != null) {
          // Entera en disco: suena sin resolver nada ni tocar la red.
          audio = AudioSource.file(stored.path);
        } else {
          final source = await _sourceResolver.resolve(
            sourceId,
            token,
            refresh: refresh,
          );
          networkUri = source.uri;
          networkHeaders = source.headers;
          final target = keep
              ? await AudioDiskCache.instance.target(sourceId)
              : null;
          if (target == null) {
            audio = AudioSource.uri(source.uri, headers: source.headers);
          } else {
            // Se reproduce mientras se guarda; el archivo solo queda con
            // su nombre definitivo cuando se descargó entero.
            // La API está marcada como experimental en just_audio; por eso
            // esta opción va apagada por defecto.
            // ignore: experimental_member_use
            audio = LockCachingAudioSource(
              source.uri,
              headers: source.headers,
              cacheFile: target,
            );
            unawaited(AudioDiskCache.instance.trim());
          }
        }
      }
      if (!_currentLoad(generation)) return;
      debugPrint(
        'audio_source_resolution durationMs=${resolutionTimer.elapsedMilliseconds}',
      );
      final preparationTimer = Stopwatch()..start();
      // Los estados por los que pasa el reproductor mientras se prepara y a los
      // cuántos ms: separa la espera de red de la preparación de ExoPlayer.
      final marks = <String>[];
      final states = _player.processingStateStream.listen(
        (state) =>
            marks.add('${state.name}@${preparationTimer.elapsedMilliseconds}'),
      );
      try {
        await _player
            .setAudioSource(audio, preload: true)
            .timeout(const Duration(seconds: 40));
      } finally {
        await states.cancel();
        debugPrint('audio_player_timeline ${marks.join(' ')}');
      }
      if (!_currentLoad(generation)) return;
      _firstProgressArmed = true;
      debugPrint(
        'audio_player_preparation durationMs=${preparationTimer.elapsedMilliseconds}',
      );
      final probeUri = networkUri;
      if (_audioProbe && probeUri != null) {
        unawaited(_probe(probeUri, networkHeaders));
      }
    } on TimeoutException {
      if (_currentLoad(generation)) throw const PlaybackSourceFailure();
    } on PlayerException {
      if (_currentLoad(generation)) throw const PlaybackSourceFailure();
    } on PlatformException catch (error) {
      if (!_currentLoad(generation)) return;
      if (error.code == 'RESOLUTION_BLOCKED') {
        throw const PlaybackSourceFailure(blocked: true);
      }
      if (error.code == 'RESOLUTION_FAILED') {
        throw const PlaybackSourceFailure();
      }
      rethrow;
    } catch (_) {
      if (_currentLoad(generation)) rethrow;
    }
  }

  /// Solo en compilaciones de medición (--dart-define=AUDIO_PROBE=true).
  static const _audioProbe = bool.fromEnvironment('AUDIO_PROBE');

  /// Una petición aparte a la misma URL, con conexión nueva: cuánto cuesta
  /// conectar (TCP + TLS) y cuánto tarda el primer byte. Es lo que el primer
  /// tramo en memoria del escritorio se ahorra. Solo mide; no cambia nada.
  Future<void> _probe(Uri uri, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final timer = Stopwatch()..start();
      final request = await client.getUrl(uri);
      final connectMs = timer.elapsedMilliseconds;
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final firstByteMs = timer.elapsedMilliseconds - connectMs;
      await response.drain<void>();
      debugPrint(
        'audio_probe connectMs=$connectMs firstByteMs=$firstByteMs '
        'status=${response.statusCode} host=${uri.host.split('.').first}',
      );
    } on Object catch (error) {
      debugPrint('audio_probe failed ${error.runtimeType}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  void cancelLoad() {
    _loadGeneration++;
    _firstProgressArmed = false;
    // Otra canción (o detener) no hereda un desvanecido a medias.
    _cancelFade();
  }

  @override
  Future<void> prefetch(String sourceId, String token) async {
    if (_disposed ||
        OfflineMode.instance.active ||
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
  void touch(String sourceId) {
    if (!_disposed && !OfflineMode.instance.active) {
      _sourceResolver.touch(sourceId);
    }
  }

  @override
  void warm(List<String> sourceIds) {
    if (!_disposed && !OfflineMode.instance.active) {
      _sourceResolver.warm(sourceIds);
    }
  }

  // Cada desvanecido lleva su número; subirlo lo cancela.
  int _fade = 0;
  static const _fadeSteps = 10;

  /// Cancela un desvanecido en marcha y devuelve el volumen.
  void _cancelFade() {
    _fade++;
    final player = _instance;
    if (!_disposed && player != null && player.volume != 1) {
      unawaited(player.setVolume(1).catchError((Object _) {}));
    }
  }

  @override
  Future<void> pauseFading(Duration duration) async {
    if (_disposed || _instance == null) return;
    if (!_player.playing || duration <= Duration.zero) {
      await pause();
      return;
    }
    final fade = ++_fade;
    unawaited(_fadeOutAndPause(fade, duration));
  }

  Future<void> _fadeOutAndPause(int fade, Duration duration) async {
    try {
      final start = _player.volume;
      final step = duration ~/ _fadeSteps;
      for (var i = 1; i <= _fadeSteps; i++) {
        await Future<void>.delayed(step);
        if (_disposed || fade != _fade) return;
        await _player.setVolume(start * (1 - i / _fadeSteps));
      }
      if (_disposed || fade != _fade) return;
      await _pauseNow();
      // En pausa, así que subir el volumen no se oye; al reanudar suena entero.
      if (!_disposed && fade == _fade) await _player.setVolume(start);
    } on Object {
      // Un fallo del desvanecido no debe dejar la canción sonando a medias.
      if (!_disposed && fade == _fade) {
        try {
          await _pauseNow();
          await _player.setVolume(1);
        } on Object {
          // Sin reproductor utilizable no hay nada más que hacer.
        }
      }
    }
  }

  @override
  Future<void> play() async {
    _cancelFade();
    if (!_disposed) {
      final generation = _loadGeneration;
      unawaited(
        _player.play().catchError((Object _) {
          if (_currentLoad(generation)) _emit(TrackAudioPhase.error);
        }),
      );
    }
  }

  /// Pausa al instante (interrupciones, y lo que no pide el usuario).
  @override
  Future<void> pause() async {
    if (_disposed) return;
    _cancelFade();
    await _pauseNow();
  }

  Future<void> _pauseNow() async {
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
  Future<void> setTuning({required double speed, required int pitch}) async {
    await _player.setSpeed(speed);
    // Un semitono es un factor de 2^(1/12).
    await _player.setPitch(math.pow(2, pitch / 12).toDouble());
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
