import 'dart:async';
import 'dart:math';

import '../../playback/domain/track_audio_engine.dart';
import '../../search/domain/catalog_track.dart';

typedef MusicListenCallback =
    void Function(String id, String trackId, int listenedMs);

/// Mide cuánto suena cada canción y avisa una vez cuando la escucha cuenta
/// (30 s, o la mitad de una pista corta). No envía nada a ningún servidor.
class ListeningTracker {
  ListeningTracker(this.isActive, {Stopwatch? clock, this.onListened})
    : _clock = clock ?? Stopwatch() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => checkpoint());
  }

  /// Se llama una vez por canción cuando la escucha ya cuenta.
  final void Function(CatalogTrack track, int listenedMs, DateTime at)?
  onListened;
  final bool Function() isActive;
  final Stopwatch _clock;
  late final Timer _timer;
  bool _countedHere = false;
  CatalogTrack? _track;
  String? _id;
  DateTime? _started;
  int? _durationMs;
  bool _disposed = false;
  MusicListenCallback? _musicListen;

  void begin(CatalogTrack track, {MusicListenCallback? onMusicListen}) {
    finish();
    _countedHere = false;
    _track = track;
    _musicListen = onMusicListen;
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    _id =
        '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    _durationMs = track.durationSeconds == null
        ? null
        : track.durationSeconds! * 1000;
  }

  void duration(Duration value) {
    if (value.inMilliseconds > 0) _durationMs = value.inMilliseconds;
  }

  void phase(TrackAudioPhase phase) {
    _clock.stop();
    if (phase == TrackAudioPhase.playing && _track != null && isActive()) {
      _started ??= DateTime.now().toUtc();
      _clock.start();
    }
    if (phase == TrackAudioPhase.completed) {
      finish(completed: true);
    } else if (phase != TrackAudioPhase.playing) {
      checkpoint();
    }
  }

  void checkpoint({bool completed = false}) {
    if (_disposed) return;
    if (!isActive()) _clock.stop();
    final ms = _clock.elapsedMilliseconds;
    final threshold = _durationMs == null
        ? 30000
        : min(30000, _durationMs! ~/ 2);
    final id = _id;
    final started = _started;
    final track = _track;
    if (id == null ||
        started == null ||
        track == null ||
        ms < threshold ||
        ms > 86400000) {
      return;
    }
    if (!_countedHere) {
      _countedHere = true;
      onListened?.call(track, ms, DateTime.now());
    }
    if (track.isMusicPreview || track.isConnectedAudio) {
      final callback = _musicListen;
      _musicListen = null;
      callback?.call(
        id,
        track.isMusicPreview
            ? track.id.substring(CatalogTrack.musicPreviewPrefix.length)
            : track.id.substring('youtube:'.length),
        ms,
      );
    }
  }

  void finish({bool completed = false}) {
    _clock.stop();
    checkpoint(completed: completed);
    _clock.reset();
    _track = null;
    _id = null;
    _started = null;
    _musicListen = null;
  }

  void dispose() {
    finish();
    _disposed = true;
    _timer.cancel();
  }
}
