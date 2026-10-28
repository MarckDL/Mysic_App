import 'dart:async';
import 'package:dio/dio.dart';
import '../data/playback_repository.dart';
import '../domain/demo_audio_engine.dart';
import '../domain/playback_resolution.dart';

class DemoController {
  DemoController(
    this._repository,
    this._engine,
    this._owner,
    this._currentUid,
  ) {
    _subscription = _engine.states.listen((value) {
      if (_loaded &&
          _active &&
          (state.phase != DemoPhase.error || value.phase == DemoPhase.error)) {
        _emit(value);
      }
    });
  }
  final PlaybackRepository _repository;
  final DemoAudioEngine _engine;
  final String _owner;
  final String? Function() _currentUid;
  final _states = StreamController<DemoState>.broadcast();
  late final StreamSubscription<DemoState> _subscription;
  final _cancel = CancelToken();
  DemoState state = const DemoState(DemoPhase.idle);
  Stream<DemoState> get states => _states.stream;
  bool _disposed = false;
  bool _busy = false;
  bool _loaded = false;
  bool get _active => !_disposed && _currentUid() == _owner;
  void _emit(DemoState value) {
    if (_active) {
      state = value;
      _states.add(value);
    }
  }

  Future<void> load() async {
    if (!_active || _busy) return;
    _busy = true;
    _loaded = false;
    _emit(const DemoState(DemoPhase.loading));
    try {
      await _engine.pause();
      final result = await _repository.resolve(
        'demo',
        PlaybackResolution.demoId,
        cancelToken: _cancel,
      );
      if (!_active) return;
      if (!result.available) throw PlaybackFailure(result.reason!);
      await _engine.load(result.assetPath!);
      if (!_active) {
        await _engine.pause();
        return;
      }
      _loaded = true;
      _emit(const DemoState(DemoPhase.ready));
    } catch (_) {
      _emit(
        const DemoState(
          DemoPhase.error,
          message:
              'No se pudo cargar el audio. Comprueba la conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> play() async {
    if (!_active || !_loaded || _busy || state.phase == DemoPhase.error) return;
    try {
      await _engine.play();
    } catch (_) {
      _emit(
        const DemoState(
          DemoPhase.error,
          message: 'No se pudo reproducir el audio. Vuelve a cargarlo.',
        ),
      );
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    try {
      await _engine.pause();
    } catch (_) {
      _emit(
        const DemoState(
          DemoPhase.error,
          message: 'No se pudo pausar el audio.',
        ),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancel.cancel();
    await _subscription.cancel();
    try {
      await _engine.dispose();
    } catch (_) {
      // La salida de la pantalla no debe propagar errores del plugin al usuario.
    } finally {
      await _states.close();
    }
  }
}
