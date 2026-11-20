import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../authentication/domain/auth_repository.dart';
import '../../history/application/listening_tracker.dart';
import '../../search/domain/catalog_track.dart';
import '../domain/track_audio_engine.dart';
import '../domain/playback_resolution.dart';

enum PlaybackRepeat { off, all, one }

class TrackPlaybackController extends ChangeNotifier {
  TrackPlaybackController(this._auth, this._engine, this._uid, {this.history}) {
    unawaited(_engine.warmUp().catchError((Object _) {}));
    _subscription = _engine.states.listen((value) {
      if (!_active) return;
      if (value == TrackAudioPhase.interrupted) {
        unawaited(pause());
        return;
      }
      if (!_eventsEnabled) return;
      // Keep the last position when a failed native source emits reset events.
      if (value == TrackAudioPhase.error) {
        _eventsEnabled = false;
      }
      if (!_wantPlayback &&
          (value == TrackAudioPhase.loading ||
              value == TrackAudioPhase.playing)) {
        return;
      }
      _set(value);
      if (value == TrackAudioPhase.completed &&
          (hasNext || repeat == PlaybackRepeat.one)) {
        final generation = _generation;
        scheduleMicrotask(() {
          if (_valid(generation)) {
            unawaited(repeat == PlaybackRepeat.one ? jump(index) : next());
          }
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
        history?.duration(value);
        notifyListeners();
      }
    });
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (!_disposed && user?.uid != _uid) unawaited(clear());
    });
  }
  bool get isDemoTrack => current?.id == demoTrack.id;
  bool get isBundledTrack => isDemoTrack || current?.isMusicPreview == true;
  MusicListenCallback? _onPreviewListened;
  MusicListenCallback? Function()? _listenForTrack;

  static const demoTrack = CatalogTrack(
    id: 'demo:${PlaybackResolution.demoId}',
    title: 'Audio de prueba',
    artistName: 'Mysic',
    durationSeconds: 8,
  );

  final ListeningTracker? history;
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
  PlaybackRepeat repeat = PlaybackRepeat.off;
  bool shuffleEnabled = false;
  final List<CatalogTrack> _originalOrder = [];
  void cycleRepeat() {
    if (!_active) return;
    repeat = PlaybackRepeat
        .values[(repeat.index + 1) % PlaybackRepeat.values.length];
    notifyListeners();
  }

  void toggleShuffle() {
    if (!_active || _queue.length < 2) return;
    final selected = current;
    shuffleEnabled = !shuffleEnabled;
    if (shuffleEnabled) {
      _originalOrder
        ..clear()
        ..addAll(_queue);
      final others = _queue.toList();
      if (index >= 0) others.removeAt(index);
      others.shuffle();
      _queue
        ..clear()
        ..addAll([if (selected != null) selected, ...others]);
    } else {
      final remaining = _queue.toList();
      final restored = <CatalogTrack>[];
      for (final track in _originalOrder) {
        final match = remaining.indexWhere((item) => identical(item, track));
        if (match >= 0) restored.add(remaining.removeAt(match));
      }
      _queue
        ..clear()
        ..addAll([...restored, ...remaining]);
      _originalOrder.clear();
    }
    index = selected == null
        ? -1
        : _queue.indexWhere((track) => identical(track, selected));
    _engine.cancelPrefetch();
    notifyListeners();
  }

  bool get hasNext =>
      index >= 0 && (index + 1 < _queue.length || repeat == PlaybackRepeat.all);
  bool get hasPrevious => index > 0;
  bool _eventsEnabled = false;
  bool _wantPlayback = false;
  bool _autoRecoveryUsed = false;
  bool _disposed = false;
  bool get _active => !_disposed && _auth.currentUser?.uid == _uid;
  TrackAudioPhase phase = TrackAudioPhase.idle;
  String? sourceId;
  Duration position = Duration.zero;
  Duration? duration;
  int _seekRevision = 0;
  int get seekRevision => _seekRevision;
  int _generation = 0;
  Future<void> _preparation = Future.value();
  bool _valid(int generation) => _active && generation == _generation;
  Future<void> _stopEngine() {
    // Serialize native stops, but never make a selection wait for old resolution.
    return _preparation = _preparation
        .catchError((Object _) {})
        .then((_) => _engine.stop());
  }

  void _set(TrackAudioPhase value) {
    history?.phase(value);
    phase = value;
    if (!_disposed) notifyListeners();
  }

  bool _validTrack(CatalogTrack track) =>
      track.id == demoTrack.id ||
      track.isMusicPreview ||
      RegExp(r'^youtube:[A-Za-z0-9_-]{11}$').hasMatch(track.id);

  Future<void> start(String id) => playTrack(
    CatalogTrack(id: 'youtube:$id', title: id, artistName: 'YouTube'),
  );

  Future<void> playTrack(CatalogTrack track) async {
    if (!_active ||
        track.isMusicPreview ||
        _onPreviewListened != null ||
        (_queue.any((t) => t.isConnectedAudio) && !track.isConnectedAudio)) {
      return;
    }
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
    if (!_active ||
        !_validTrack(track) ||
        track.isConnectedAudio ||
        track.id == demoTrack.id ||
        track.isMusicPreview ||
        _onPreviewListened != null) {
      return;
    }
    _engine.cancelPrefetch();
    final generation = _generation;
    final token = await _auth.getIdToken();
    if (!_valid(generation) || token == null || token.isEmpty) return;
    await _engine.prefetch(track.id.substring(8), token);
  }

  void cancelPrefetch() => _engine.cancelPrefetch();

  void enqueue(CatalogTrack track) {
    if (!_active ||
        track.isMusicPreview ||
        _onPreviewListened != null ||
        (_queue.any((t) => t.isConnectedAudio) && !track.isConnectedAudio) ||
        !_validTrack(track) ||
        _queue.length >= 100 ||
        _queue.any((item) => item.id == track.id)) {
      return;
    }
    _engine.cancelPrefetch();
    _queue.add(track);
    notifyListeners();
  }

  bool queueConnected(
    Iterable<CatalogTrack> tracks, {
    required bool next,
    MusicListenCallback? Function()? listenForTrack,
  }) {
    if (!_active || _queue.any((t) => !t.isConnectedAudio)) return false;
    final playing = current;
    final existing = _queue.map((t) => t.id).toSet();
    final incoming = <String, CatalogTrack>{};
    var slots = 100 - _queue.length;
    for (final track in tracks) {
      if (!track.isConnectedAudio ||
          !_validTrack(track) ||
          track.id == playing?.id ||
          incoming.containsKey(track.id)) {
        continue;
      }
      if (!existing.contains(track.id)) {
        if (slots == 0) continue;
        slots--;
      }
      incoming[track.id] = track;
    }
    if (incoming.isEmpty) return false;
    int insert(List<CatalogTrack> list) {
      list.removeWhere((track) => incoming.containsKey(track.id));
      final selected = playing == null ? -1 : list.indexOf(playing);
      list.insertAll(
        next && selected >= 0 ? selected + 1 : list.length,
        incoming.values,
      );
      return selected;
    }

    index = insert(_queue);
    if (shuffleEnabled) insert(_originalOrder);
    _listenForTrack = listenForTrack;
    _engine.cancelPrefetch();
    notifyListeners();
    return true;
  }

  Future<void> playQueue(
    List<CatalogTrack> tracks, {
    int initialIndex = 0,
    bool shuffled = false,
    MusicListenCallback? onPreviewListened,
    MusicListenCallback? Function()? listenForTrack,
  }) async {
    if (!_active ||
        tracks.isEmpty ||
        tracks.length > 100 ||
        (tracks.any((t) => t.isConnectedAudio) &&
            tracks.any((t) => !t.isConnectedAudio)) ||
        tracks.any(
          (track) =>
              !_validTrack(track) ||
              track.isMusicPreview != (onPreviewListened != null),
        ) ||
        initialIndex < 0 ||
        initialIndex >= tracks.length) {
      return;
    }
    history?.finish();
    _onPreviewListened = onPreviewListened;
    _listenForTrack = listenForTrack;
    shuffleEnabled = shuffled && tracks.length > 1;
    _originalOrder.clear();
    _queue
      ..clear()
      ..addAll(tracks);
    if (shuffleEnabled) {
      _originalOrder.addAll(tracks);
      _queue.shuffle();
    }
    await jump(shuffleEnabled ? 0 : initialIndex);
  }

  Future<void> jump(int target) => _loadTrack(target);

  Future<void>? _recoverSource() {
    if (!_wantPlayback || _autoRecoveryUsed || current == null) return null;
    _autoRecoveryUsed = true;
    return _loadTrack(index, resumeAt: position, refresh: true);
  }

  Future<void> _loadTrack(
    int target, {
    Duration? resumeAt,
    bool refresh = false,
  }) async {
    if (!_active || target < 0 || target >= _queue.length) return;
    // Only an explicit selection starts a new listening session. Retrying a
    // failed source keeps both its accumulated listening time and position.
    if (resumeAt == null) {
      final track = _queue[target];
      final listen = track.isConnectedAudio
          ? _listenForTrack?.call()
          : _onPreviewListened;
      if (track.id == demoTrack.id ||
          (track.isConnectedAudio && listen == null)) {
        history?.finish();
      } else {
        history?.begin(track, onMusicListen: listen);
      }
      _autoRecoveryUsed = false;
    }
    _wantPlayback = true;
    _engine.cancelLoad();
    _engine.markPlaybackRequested();
    final generation = ++_generation;
    _eventsEnabled = false;
    index = target;
    sourceId = isBundledTrack
        ? PlaybackResolution.demoId
        : current!.id.substring(8);
    final requestedId = sourceId!;
    position = resumeAt ?? Duration.zero;
    duration = current!.durationSeconds == null
        ? null
        : Duration(seconds: current!.durationSeconds!);
    var stage = 'stop';
    try {
      final stopped = _stopEngine();
      _set(TrackAudioPhase.loading);
      await stopped;
      if (!_valid(generation)) return;
      stage = 'session';
      // Firebase renueva automáticamente tokens vencidos. Usar el token válido
      // en caché evita una solicitud de red adicional al iniciar cada canción;
      // los clientes HTTP conservan su reintento con refresh ante un 401.
      final token = await _auth.getIdToken();
      if (!_valid(generation)) return;
      if (token == null || token.isEmpty) throw StateError('Sesión inválida');
      stage = 'audio-load';
      await _engine.load(
        requestedId,
        token,
        refresh: refresh,
        licensedAudio: current!.licensedAudio,
        deviceAudio: current!.deviceAudio,
      );
      if (!_valid(generation)) return;
      final actualDuration = _engine.duration;
      if (actualDuration != null && actualDuration > Duration.zero) {
        history?.duration(actualDuration);
        duration = actualDuration;
      }
      if (resumeAt != null && resumeAt > Duration.zero) {
        final limit = duration;
        final destination = limit != null && resumeAt > limit
            ? limit
            : resumeAt;
        await _engine.seek(destination);
        if (!_valid(generation)) return;
        position = destination;
      }
      _eventsEnabled = true;
      if (!_wantPlayback) {
        _set(TrackAudioPhase.paused);
        return;
      }
      await _engine.play();
      if (_valid(generation) && _wantPlayback && index + 1 < _queue.length) {
        final next = _queue[index + 1];
        if (next.id != demoTrack.id &&
            !next.isMusicPreview &&
            !next.isConnectedAudio) {
          unawaited(
            _engine
                .prefetch(next.id.substring(8), token)
                .catchError((Object _) {}),
          );
        }
      }
    } catch (error) {
      if (_valid(generation)) {
        if (kDebugMode) debugPrint('audio_start_failed stage=$stage');
        final recovery = error is PlaybackSourceFailure && !refresh
            ? _recoverSource()
            : null;
        if (recovery != null) {
          await recovery;
          return;
        }
        _eventsEnabled = false;
        try {
          await _stopEngine();
        } catch (_) {}
        if (_valid(generation)) _set(TrackAudioPhase.error);
      }
    }
  }

  Future<void> next() async {
    if (hasNext) await jump(index + 1 < _queue.length ? index + 1 : 0);
  }

  Future<void> previous() async {
    if (hasPrevious) await jump(index - 1);
  }

  Future<void> removeDeviceAudio(Uri audio) async {
    if (!_active || !_queue.any((track) => track.deviceAudio == audio)) return;
    final selected = current;
    final selectedRemoved = selected?.deviceAudio == audio;
    _engine.cancelPrefetch();
    _queue.removeWhere((track) => track.deviceAudio == audio);
    _originalOrder.removeWhere((track) => track.deviceAudio == audio);
    index = selected == null ? -1 : _queue.indexOf(selected);
    if (_queue.isEmpty) {
      await clear();
    } else if (selectedRemoved) {
      sourceId = null;
      position = Duration.zero;
      duration = null;
      await stop();
    } else {
      notifyListeners();
    }
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
    if (phase == TrackAudioPhase.error) return;
    _wantPlayback = false;
    if (!_eventsEnabled &&
        (phase == TrackAudioPhase.loading || phase == TrackAudioPhase.paused)) {
      await stop();
      return;
    }
    final generation = _generation;
    await _engine.pause();
    if (_valid(generation) &&
        !_wantPlayback &&
        phase != TrackAudioPhase.error) {
      _set(TrackAudioPhase.paused);
    }
  }

  Future<void> resume() async {
    if (!_active) return;
    if (phase == TrackAudioPhase.error && current != null) {
      await _loadTrack(index, resumeAt: position, refresh: true);
    } else if (phase == TrackAudioPhase.paused) {
      _wantPlayback = true;
      if (_eventsEnabled) {
        await _engine.play();
      } else {
        _set(TrackAudioPhase.loading);
      }
    } else if (current != null &&
        phase != TrackAudioPhase.loading &&
        phase != TrackAudioPhase.playing) {
      await jump(index);
    }
  }

  bool get canSeek =>
      _active &&
      current != null &&
      (duration ?? Duration.zero) > Duration.zero &&
      _eventsEnabled &&
      phase != TrackAudioPhase.loading &&
      phase != TrackAudioPhase.error;

  Future<void> seek(Duration target) async {
    if (!canSeek || target.isNegative) return;
    final limit = duration!;
    final bounded = target > limit ? limit : target;
    final generation = _generation;
    history?.phase(TrackAudioPhase.paused);
    try {
      await _engine.seek(bounded);
      if (_valid(generation) && _eventsEnabled) {
        position = bounded;
        _seekRevision++;
        notifyListeners();
      }
    } finally {
      if (_valid(generation)) history?.phase(phase);
    }
  }

  Future<void> stop() async {
    history?.finish();
    _engine.cancelPrefetch();
    _engine.cancelLoad();
    ++_generation;
    _wantPlayback = false;
    _eventsEnabled = false;
    if (!_disposed) {
      final stopped = _stopEngine();
      _set(TrackAudioPhase.idle);
      try {
        await stopped;
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    _engine.cancelPrefetch();
    _queue.clear();
    _onPreviewListened = null;
    _listenForTrack = null;
    _originalOrder.clear();
    shuffleEnabled = false;
    repeat = PlaybackRepeat.off;
    index = -1;
    sourceId = null;
    position = Duration.zero;
    duration = null;
    await stop();
  }

  @override
  void dispose() {
    if (_disposed) return;
    history?.dispose();
    _disposed = true;
    _engine.cancelPrefetch();
    ++_generation;
    _queue.clear();
    _onPreviewListened = null;
    _listenForTrack = null;
    _originalOrder.clear();
    shuffleEnabled = false;
    repeat = PlaybackRepeat.off;
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
