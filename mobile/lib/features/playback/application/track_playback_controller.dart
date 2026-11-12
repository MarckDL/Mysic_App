import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../search/domain/catalog_track.dart';
import '../domain/track_audio_engine.dart';

class TrackPlaybackController extends ChangeNotifier {
  TrackPlaybackController(this._auth, this._engine, this._uid) {
    unawaited(_engine.warmUp().catchError((Object _) {}));
    _subscription = _engine.states.listen((value) {
      if (!_active) return;
      if (value == TrackAudioPhase.interrupted) {
        unawaited(pause());
        return;
      }
      if (!_eventsEnabled) return;
      _set(value);
      if (value == TrackAudioPhase.completed && hasNext) {
        final generation = _generation;
        scheduleMicrotask(() {
          if (_valid(generation)) unawaited(next());
        });
      }
    });
    _positions = _engine.positions.listen((value) {
      if (_active && _eventsEnabled) {
        position = value;
        notifyListeners();
      }
    });
    _durations = _engine.durations.listen((value) {
      if (_active && _eventsEnabled && value != null) {
        duration = value;
        notifyListeners();
      }
    });
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (!_disposed && user?.uid != _uid) unawaited(clear());
    });
  }
  final AuthRepository _auth;
  final TrackAudioEngine _engine;
  final String _uid;
  late final StreamSubscription<TrackAudioPhase> _subscription;
  late final StreamSubscription<Duration> _positions;
  late final StreamSubscription<Duration?> _durations;
  late final StreamSubscription<AuthUser?> _authSubscription;
  final List<CatalogTrack> _queue = [];
  List<CatalogTrack> get queue => List.unmodifiable(_queue);
  int index = -1;
  CatalogTrack? get current =>
      index >= 0 && index < _queue.length ? _queue[index] : null;
  bool get hasNext => index >= 0 && index + 1 < _queue.length;
  bool get hasPrevious => index > 0;
  bool _eventsEnabled = false;
  bool _disposed = false;
  bool get _active => !_disposed && _auth.currentUser?.uid == _uid;
  TrackAudioPhase phase = TrackAudioPhase.idle;
  String? sourceId;
  Duration position = Duration.zero;
  Duration? duration;
  int _generation = 0;
  Future<void> _preparation = Future.value();
  bool _valid(int generation) => _active && generation == _generation;
  void _set(TrackAudioPhase value) {
    phase = value;
    if (!_disposed) notifyListeners();
  }

  bool _validTrack(CatalogTrack track) =>
      RegExp(r'^youtube:[A-Za-z0-9_-]{11}$').hasMatch(track.id);

  Future<void> start(String id) => playTrack(
    CatalogTrack(id: 'youtube:$id', title: id, artistName: 'YouTube'),
  );

  Future<void> playTrack(CatalogTrack track) async {
    if (!_active) return;
    if (!_validTrack(track)) {
      _set(TrackAudioPhase.error);
      return;
    }
    var target = _queue.indexWhere((item) => item.id == track.id);
    if (target < 0) {
      if (_queue.length >= 100) return;
      _queue.add(track);
      target = _queue.length - 1;
    } else {
      _queue[target] = track;
    }
    await jump(target);
  }

  Future<void> prefetchTrack(CatalogTrack track) async {
    if (!_active || !_validTrack(track)) return;
    _engine.cancelPrefetch();
    final generation = _generation;
    final token = await _auth.getIdToken();
    if (!_valid(generation) || token == null || token.isEmpty) return;
    await _engine.prefetch(track.id.substring(8), token);
  }

  void cancelPrefetch() => _engine.cancelPrefetch();

  void enqueue(CatalogTrack track) {
    if (!_active ||
        !_validTrack(track) ||
        _queue.length >= 100 ||
        _queue.any((item) => item.id == track.id)) {
      return;
    }
    _engine.cancelPrefetch();
    _queue.add(track);
    notifyListeners();
  }

  Future<void> playQueue(
    List<CatalogTrack> tracks, {
    int initialIndex = 0,
  }) async {
    if (!_active ||
        tracks.isEmpty ||
        tracks.length > 100 ||
        tracks.any((track) => !_validTrack(track)) ||
        initialIndex < 0 ||
        initialIndex >= tracks.length) {
      return;
    }
    _queue
      ..clear()
      ..addAll(tracks);
    await jump(initialIndex);
  }

  Future<void> jump(int target) async {
    if (!_active || target < 0 || target >= _queue.length) return;
    _engine.markPlaybackRequested();
    final generation = ++_generation;
    _eventsEnabled = false;
    index = target;
    sourceId = current!.id.substring(8);
    final requestedId = sourceId!;
    position = Duration.zero;
    duration = current!.durationSeconds == null
        ? null
        : Duration(seconds: current!.durationSeconds!);
    _set(TrackAudioPhase.loading);
    var stage = 'stop';
    try {
      // Solo serializar la preparación: una selección nueva puede cancelar una carga anterior.
      _preparation = _preparation.catchError((Object _) {}).then((_) async {
        if (_valid(generation)) await _engine.stop();
      });
      await _preparation;
      if (!_valid(generation)) return;
      stage = 'session';
      // Firebase renueva automáticamente tokens vencidos. Usar el token válido
      // en caché evita una solicitud de red adicional al iniciar cada canción;
      // los clientes HTTP conservan su reintento con refresh ante un 401.
      final token = await _auth.getIdToken();
      if (!_valid(generation)) return;
      if (token == null || token.isEmpty) throw StateError('Sesión inválida');
      stage = 'audio-load';
      await _engine.load(requestedId, token);
      if (!_valid(generation)) return;
      _eventsEnabled = true;
      final actualDuration = _engine.duration;
      if (actualDuration != null && actualDuration > Duration.zero) {
        duration = actualDuration;
      }
      await _engine.play();
      if (_valid(generation) && hasNext) {
        final nextId = _queue[index + 1].id.substring(8);
        unawaited(_engine.prefetch(nextId, token).catchError((Object _) {}));
      }
    } catch (_) {
      if (kDebugMode) debugPrint('audio_start_failed stage=$stage');
      if (_valid(generation)) {
        _eventsEnabled = false;
        try {
          await _engine.stop();
        } catch (_) {}
        if (_valid(generation)) _set(TrackAudioPhase.error);
      }
    }
  }

  Future<void> next() async {
    if (hasNext) await jump(index + 1);
  }

  Future<void> previous() async {
    if (hasPrevious) await jump(index - 1);
  }

  void remove(int target) {
    if (!_active || target < 0 || target >= _queue.length || target == index) {
      return;
    }
    _engine.cancelPrefetch();
    _queue.removeAt(target);
    if (target < index) index--;
    notifyListeners();
  }

  Future<void> pause() async {
    if (!_active) return;
    if (phase == TrackAudioPhase.loading) {
      await stop();
      return;
    }
    await _engine.pause();
    if (_active) _set(TrackAudioPhase.paused);
  }

  Future<void> resume() async {
    if (!_active) return;
    if (phase == TrackAudioPhase.paused) {
      await _engine.play();
    } else if (current != null &&
        phase != TrackAudioPhase.loading &&
        phase != TrackAudioPhase.playing) {
      await jump(index);
    }
  }

  Future<void> seek(Duration target) async {
    final limit = duration;
    if (!_active ||
        current == null ||
        limit == null ||
        limit <= Duration.zero ||
        target.isNegative ||
        phase == TrackAudioPhase.loading ||
        phase == TrackAudioPhase.error) {
      return;
    }
    final bounded = target > limit ? limit : target;
    await _engine.seek(bounded);
    if (_active) {
      position = bounded;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _engine.cancelPrefetch();
    ++_generation;
    _eventsEnabled = false;
    if (!_disposed) {
      _preparation = _preparation
          .catchError((Object _) {})
          .then((_) => _engine.stop());
      try {
        await _preparation;
      } catch (_) {}
      if (!_disposed) _set(TrackAudioPhase.idle);
    }
  }

  Future<void> clear() async {
    _engine.cancelPrefetch();
    _queue.clear();
    index = -1;
    sourceId = null;
    position = Duration.zero;
    duration = null;
    await stop();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engine.cancelPrefetch();
    ++_generation;
    _queue.clear();
    index = -1;
    sourceId = null;
    unawaited(_subscription.cancel());
    unawaited(_positions.cancel());
    unawaited(_durations.cancel());
    unawaited(_authSubscription.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }
}
