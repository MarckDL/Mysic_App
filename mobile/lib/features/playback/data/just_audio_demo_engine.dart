import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/demo_audio_engine.dart';
import '../domain/playback_resolution.dart';

class JustAudioDemoEngine implements DemoAudioEngine {
  final _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: true,
  );
  final _states = StreamController<DemoState>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _disposed = false;
  bool _configured = false;
  int _epoch = 0;
  @override
  Stream<DemoState> get states => _states.stream;
  void _emit(DemoPhase phase, [String? message]) {
    if (!_disposed) _states.add(DemoState(phase, message: message));
  }

  void _error() => _emit(
    DemoPhase.error,
    'No se pudo reproducir el audio. Vuelve a cargarlo.',
  );

  Future<void> _configure() async {
    if (_configured) return;
    final session = await AudioSession.instance;
    if (_disposed) return;
    await session.configure(const AudioSessionConfiguration.music());
    if (_disposed) return;
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        // Sin auto-resume: la vuelta del foco requiere una acción explícita del usuario.
        if (event.begin) unawaited(pause().catchError((Object _) => _error()));
      }),
    );
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        unawaited(pause().catchError((Object _) => _error()));
      }),
    );
    _subscriptions.add(_player.errorStream.listen((_) => _error()));
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering) {
          _emit(DemoPhase.loading);
        } else if (state.processingState == ProcessingState.completed) {
          _emit(DemoPhase.completed);
        } else if (state.processingState == ProcessingState.ready) {
          _emit(state.playing ? DemoPhase.playing : DemoPhase.paused);
        }
      }),
    );
    await _player.setVolume(0.5);
    _configured = true;
  }

  @override
  Future<void> load(String assetPath) async {
    if (assetPath != PlaybackResolution.demoAsset || _disposed) {
      throw const PlaybackFailure('Fuente no habilitada.');
    }
    await _configure();
    if (_disposed) return;
    _emit(DemoPhase.loading);
    try {
      await _player.setAsset(assetPath).timeout(const Duration(seconds: 10));
      if (!_disposed) _emit(DemoPhase.ready);
    } catch (_) {
      if (!_disposed) await _player.stop();
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    final epoch = _epoch;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    if (_disposed) return;
    if (epoch != _epoch) return;
    // play() termina al finalizar el audio: no bloquear controles hasta entonces.
    unawaited(_player.play().catchError((Object _) => _error()));
  }

  @override
  Future<void> pause() async {
    _epoch++;
    if (!_disposed) await _player.pause();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _player.dispose();
    await _states.close();
  }
}
