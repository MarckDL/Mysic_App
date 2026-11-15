import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import '../../../core/network/authenticated_api_client.dart';
import '../../playback/domain/track_audio_engine.dart';
import '../../search/domain/catalog_track.dart';

/// One tracker per authenticated account. Network work never blocks playback.
class ListeningTracker {
  ListeningTracker(this.api, this.isActive, this.uid, {Stopwatch? clock})
    : _clock = clock ?? Stopwatch() {
    _restore = _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => checkpoint());
  }
  final String uid;
  static const _storage = MethodChannel('com.mysic/history');
  late final Future<void> _restore;
  Future<void> _writes = Future.value();
  Future<void> _load() async {
    try {
      final raw = await _storage.invokeMethod<String>('load', {'uid': uid});
      final data = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      for (final entry in data.entries.take(100)) {
        if (_pending.length >= 100 && !_pending.containsKey(entry.key)) break;
        _pending.putIfAbsent(
          entry.key,
          () => Map<String, dynamic>.from(entry.value as Map),
        );
      }
    } catch (_) {
      /* Unsupported platform: retain session memory queue. */
    }
  }

  Future<void> _persist() {
    final data = jsonEncode(_pending);
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await _storage.invokeMethod<void>('save', {'uid': uid, 'data': data});
    });
    return _writes;
  }

  final AuthenticatedApiClient api;
  final bool Function() isActive;
  final Stopwatch _clock;
  final _pending = <String, Map<String, dynamic>>{};
  late final Timer _timer;
  CatalogTrack? _track;
  String? _id;
  DateTime? _started;
  int? _durationMs;
  bool _sending = false;
  bool _disposed = false;
  void begin(CatalogTrack track) {
    finish();
    _track = track;
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
    if (_id != null &&
        _started != null &&
        ms >= threshold &&
        ms <= 86400000 &&
        (_pending.length < 100 || _pending.containsKey(_id))) {
      _pending[_id!] = {
        'catalogTrackId': _track!.id,
        'startedAt': _started!.toIso8601String(),
        'listenedMs': ms,
        'completed':
            completed && _durationMs != null && ms >= _durationMs! * .9,
      };
    }
    if (isActive()) {
      unawaited(_flush());
    } else {
      // Keep the last checkpoint under its original owner, without using
      // credentials from the newly selected account.
      unawaited(_restore.then((_) => _persist()).catchError((Object _) {}));
    }
  }

  Future<void> _flush() async {
    if (_sending || _disposed || !isActive()) return;
    _sending = true;
    try {
      await _restore;
      try {
        await _persist();
      } catch (_) {
        return;
      }
      for (final id in _pending.keys.toList()) {
        if (!isActive() || _disposed) break;
        final payload = _pending[id]!;
        try {
          await api.put('/api/v1/history/$id', body: payload);
          if (identical(_pending[id], payload)) _pending.remove(id);
        } on ApiFailure catch (e) {
          if (e.statusCode == 400 || e.statusCode == 409) {
            _pending.remove(id);
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
    } catch (_) {
      // Keep pending events when local storage fails.
    } finally {
      try {
        await _persist();
      } catch (_) {}
      _sending = false;
    }
  }

  void finish({bool completed = false}) {
    _clock.stop();
    checkpoint(completed: completed);
    _clock.reset();
    _track = null;
    _id = null;
    _started = null;
  }

  void dispose() {
    finish();
    _disposed = true;
    _timer.cancel();
    // Pending records remain on the device under the original account.
    api.close();
  }
}
