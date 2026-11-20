import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, setEquals, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../playback/application/playback_providers.dart';
import '../../history/application/listening_tracker.dart'
    show MusicListenCallback;
import '../data/device_recordings.dart';
import '../data/desktop_music_client.dart';
import '../../search/domain/catalog_track.dart';
import '../data/music_mode_client.dart';
import '../domain/music_mode.dart';

final youtubeMusicModeEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('YOUTUBE_MUSIC_MODE_ENABLED'),
);

final musicModeControllerProvider = Provider.autoDispose
    .family<MusicModeController, String>((ref, uid) {
      final auth = ref.watch(authRepositoryProvider);
      final api = AuthenticatedApiClient(
        auth,
        baseUrl: ApiConfig.baseUrl,
        ownerUid: uid,
        keepSessionOnForbidden: true,
      );
      final playback = ref.watch(trackPlaybackControllerProvider);
      bool owns() => auth.currentUser?.uid == uid;
      final desktop = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? DesktopMusicClient(DesktopSessionStore(uid), owns)
          : null;
      final controller = MusicModeController(
        MusicModeClient(api, desktop: desktop),
        owns,
        playback.clear,
        device: DeviceRecordings(uid),
        onDeviceAudioRemoved: playback.removeDeviceAudio,
      );
      ref.onDispose(() {
        controller.dispose();
        desktop?.close();
        api.close();
      });
      return controller;
    });

class MusicModeController extends ChangeNotifier {
  MusicModeController(
    this._client,
    this._isOwner,
    this._clearPlayback, {
    this.device,
    this.onDeviceAudioRemoved,
  });
  final DeviceRecordings? device;
  final Future<void> Function(Uri)? onDeviceAudioRemoved;
  Map<String, Uri> _files = {};
  String? _fileGeneration;
  bool pickingAudio = false;
  Uri? deviceAudio(String id) =>
      isCurrent(_fileGeneration ?? '') ? _files[id] : null;

  final MusicModeClient _client;
  final bool Function() _isOwner;
  final Future<void> Function() _clearPlayback;
  final _pendingListens = <String, ({String trackId, int ms, int? epoch})>{};
  MusicConnection? connection;
  bool wantsMusic = false;
  bool busy = false;
  bool transitioning = false;
  bool _localOverride = false;
  Timer? _retry;
  bool failed = false;
  String? failureCode;
  bool _disposed = false;
  bool _submitting = false;
  bool _refreshAgain = false;
  int _bindingEpoch = 0;
  int _revision = 0;
  bool get _active => !_disposed && _isOwner();
  bool get showMusic =>
      transitioning ||
      (!_localOverride &&
          (wantsMusic ||
              connection == null ||
              connection?.serverPending == true));
  int get revision => _revision;
  CatalogTrack playbackTrack(String generation, MusicTrack track) =>
      track.toPlaybackTrack(
        deviceAudio: deviceAudio(track.id),
        readAudio: connection?.isDesktop == true
            ? _client.desktop!.audioReader(generation, track.id)
            : null,
      );
  bool get hasDesktopSession => _client.desktop?.hasSession == true;
  bool get supportsDesktop => _client.desktop != null;

  String? get desktopName => _client.desktop?.accountName;
  bool get pendingDesktopLink => _client.desktop?.hasPendingLink == true;
  void cancelDesktopLink() => _client.desktop?.cancelPending();

  Future<void> connectDesktop(
    String email,
    String password, {
    required bool remember,
  }) => _activateSource(
    () => _client.desktop!.login(email, password, remember: remember),
  );

  Future<void> finishDesktopLink() =>
      _activateSource(() => _client.desktop!.finishLink());

  Future<void> switchSource({required bool toDesktop}) async {
    await _activateSource(() async {
      final desktop = _client.desktop!;
      final next = toDesktop
          ? await desktop.connection(includeInactive: true)
          : await _client.channelConnection();
      if (next == null || next.status != MusicLinkStatus.linked) {
        throw const ApiFailure(
          'Vincula y confirma la cuenta para usar su biblioteca.',
        );
      }
      await desktop.preferChannel(!toDesktop);
      return next;
    });
    if (!toDesktop && _active) await refresh();
  }

  Future<void> _activateSource(
    Future<MusicConnection> Function() operation,
  ) async {
    if (!_active || busy || _client.desktop == null) {
      throw const ApiFailure('Espera a que termine la consulta.');
    }
    busy = true;
    final epoch = ++_bindingEpoch;
    notifyListeners();
    try {
      final next = await operation();
      if (!_active || epoch != _bindingEpoch) return;
      transitioning = true;
      _forgetData();
      _files = {};
      _fileGeneration = null;
      await _clearPlayback();
      if (!_active || epoch != _bindingEpoch) return;
      connection = next;
      wantsMusic = true;
      _localOverride = false;
      failed = false;
      failureCode = null;
    } finally {
      busy = false;
      transitioning = false;
      if (_active) {
        notifyListeners();
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<void> disconnectDesktop() async {
    if (!_active || busy || _client.desktop == null) return;
    await _change(() async {
      await _client.desktop!.disconnect();
      return _client.connection();
    }, true);
    if (_active && connection?.isDirect == true && device != null) {
      await refresh();
    }
  }

  bool isCurrent(String generation) =>
      _active &&
      !transitioning &&
      !_localOverride &&
      wantsMusic &&
      connection?.status == MusicLinkStatus.linked &&
      generation == connection?.generation;

  void _forgetData() {
    _revision++;
    _pendingListens.clear();
    _retry?.cancel();
  }

  Future<bool> attachAudio(String generation, String id) async {
    if (!isCurrent(generation) || pickingAudio || device == null) return false;
    final revision = _revision;
    bool current() => isCurrent(generation) && revision == _revision;
    pickingAudio = true;
    notifyListeners();
    try {
      final uri = await device!.attach(
        connection!.libraryId ?? generation,
        id,
        current,
      );
      if (uri == null || !current()) return false;
      _files[id] = uri;
      _fileGeneration = generation;
      return true;
    } finally {
      pickingAudio = false;
      if (_active) notifyListeners();
    }
  }

  Future<void> removeAudio(String generation, String id) async {
    final audio = deviceAudio(id);
    if (!isCurrent(generation) || pickingAudio || audio == null) {
      return;
    }
    pickingAudio = true;
    notifyListeners();
    try {
      await onDeviceAudioRemoved?.call(audio);
      if (!isCurrent(generation)) return;
      await device?.remove(connection!.libraryId ?? generation, id);
      if (isCurrent(generation)) _files.remove(id);
    } finally {
      pickingAudio = false;
      if (_active) notifyListeners();
    }
  }

  Future<void> refresh({bool invalidate = false}) async {
    if (!_active) return;
    if (invalidate) {
      _bindingEpoch++;
      connection = null;
      transitioning = true;
      _forgetData();
      unawaited(_clearPlayback());
    }
    if (busy) {
      _refreshAgain = true;
      if (invalidate) notifyListeners();
      return;
    }
    final epoch = _bindingEpoch;
    busy = true;
    failed = false;
    failureCode = null;
    notifyListeners();
    try {
      final next = await _client.connection();
      if (!_active || epoch != _bindingEpoch) return;
      final previous = connection;
      if (previous != null &&
          next.generation != null &&
          next.generation == previous.generation &&
          next.activityEpoch < previous.activityEpoch) {
        return;
      }
      final changed =
          connection?.generation != next.generation ||
          connection?.status != next.status;
      if (!changed &&
          (connection?.personalization != next.personalization ||
              !setEquals(connection?.capabilities, next.capabilities))) {
        _revision++;
      }
      if (!changed && connection?.activityEpoch != next.activityEpoch) {
        _revision++;
        _pendingListens.removeWhere(
          (id, listen) => listen.epoch != next.activityEpoch,
        );
      }
      if (!_localOverride &&
          changed &&
          (wantsMusic || next.status == MusicLinkStatus.linked)) {
        transitioning = true;
        _forgetData();
        notifyListeners();
        await _clearPlayback();
      }
      if (!_active || epoch != _bindingEpoch) return;
      if (next.isDirect &&
          device != null &&
          (next.status == MusicLinkStatus.linked ||
              next.status == MusicLinkStatus.unlinked) &&
          (_fileGeneration != next.generation ||
              invalidate ||
              connection == null)) {
        try {
          final files = await device!.open(
            next.libraryId ?? next.generation,
            () => _active && epoch == _bindingEpoch,
          );
          if (!_active || epoch != _bindingEpoch) return;
          _files = files;
          _fileGeneration = next.generation;
        } on Object {
          if (!_active || epoch != _bindingEpoch) return;
          _files = {};
          _fileGeneration = null;
        }
      }
      connection = next;
      wantsMusic =
          !_localOverride &&
          (next.status == MusicLinkStatus.linked ||
              next.status == MusicLinkStatus.expired ||
              (next.isDesktop && next.status == MusicLinkStatus.unavailable));
    } catch (_) {
      if (_active && epoch == _bindingEpoch) failed = true;
    } finally {
      busy = false;
      if (_active && _refreshAgain) {
        _refreshAgain = false;
        unawaited(refresh());
      } else {
        transitioning = false;
        if (_active) notifyListeners();
      }
    }
    if (_active) unawaited(_flushListens());
  }

  Future<void> select(MusicAccount account) =>
      _change(() => _client.link(account.id, connection?.generation), true);

  Future<void> useLinkedAccount() async {
    _localOverride = false;
    await refresh(invalidate: true);
  }

  void useLocal({bool disconnecting = false}) {
    if (!_active || (busy && !disconnecting)) return;
    if (disconnecting) _bindingEpoch++;
    _localOverride = true;
    wantsMusic = false;
    _forgetData();
    unawaited(_clearPlayback());
    notifyListeners();
  }

  Future<void> returnToMysic() => _change(() async {
    final generation = connection?.generation;
    if (generation != null) await _client.unlink(generation);
    return _client.connection();
  }, false);

  Future<void> _change(
    Future<MusicConnection> Function() operation,
    bool useMusic,
  ) async {
    if (!_active || busy) return;
    busy = true;
    failed = false;
    failureCode = null;
    transitioning = true;
    _forgetData();
    notifyListeners();
    try {
      await _clearPlayback();
      if (!_active) return;
      final next = await operation();
      if (!_active) return;
      connection = next;
      _localOverride = false;
      wantsMusic = useMusic && next.status == MusicLinkStatus.linked;
    } catch (error) {
      if (error is ApiFailure) failureCode = error.code;
      // A lost response may follow a successful server mutation.
      try {
        final latest = await _client.connection();
        if (!_active) return;
        connection = latest;
        wantsMusic = !_localOverride && latest.generation != null;
      } catch (_) {
        connection = null;
      }
      failed = true;
    } finally {
      busy = false;
      if (_active && _refreshAgain) {
        _refreshAgain = false;
        unawaited(refresh());
      } else {
        transitioning = false;
        if (_active) notifyListeners();
      }
    }
  }

  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (!isCurrent(generation)) throw const ApiFailure('Cambió la conexión.');
    final requestRevision = _revision;
    try {
      late final MusicPage page;
      try {
        page = await _client.page(
          generation,
          surface,
          playlistId: playlistId,
          query: query,
          cursor: cursor,
          cancelToken: cancelToken,
        );
      } on ApiFailure catch (error) {
        if (error.code != 'MUSIC_SEARCH_UNAVAILABLE' ||
            surface != MusicSurface.search ||
            cursor != null ||
            query == null ||
            connection?.isDirect != true ||
            _client.desktop == null ||
            !isCurrent(generation) ||
            _revision != requestRevision) {
          rethrow;
        }
        page = await _client.desktop!.publicSongs(query, cancelToken);
      }
      if (!isCurrent(generation) || _revision != requestRevision) {
        throw const ApiFailure('Cambió la conexión.');
      }
      return page;
    } on ApiFailure catch (error) {
      if (isCurrent(generation) && _revision == requestRevision) {
        if (error.code == 'MUSIC_LINK_CHANGED' ||
            error.code == 'MUSIC_RECONNECT') {
          unawaited(refresh(invalidate: true));
        } else if (error.code == 'DESKTOP_EXPIRED' ||
            error.code == 'DESKTOP_MUSIC_LINK' ||
            (error.code == 'MUSIC_ACCESS_DENIED' &&
                connection?.channelOnly != true) ||
            error.code == 'MYSIC_ACTIVITY_CHANGED') {
          unawaited(refresh());
        }
      }
      rethrow;
    }
  }

  bool updatingActivity = false;
  Future<void> updateActivity(String generation, {bool? paused}) async {
    if (!isCurrent(generation) || updatingActivity) return;
    updatingActivity = true;
    notifyListeners();
    try {
      await _client.activityPreference(generation, paused: paused);
      if (!isCurrent(generation)) return;
      if (paused != false) _pendingListens.clear();
      final latest = await _client.connection();
      if (!isCurrent(generation) || latest.generation != generation) return;
      connection = latest;
      _revision++;
    } finally {
      updatingActivity = false;
      if (_active) notifyListeners();
    }
  }

  MusicListenCallback? listenForTrack(String generation) {
    final current = connection;
    if (!isCurrent(generation) ||
        current == null ||
        updatingActivity ||
        current.account?.historyPaused == true ||
        !current.capabilities.contains('recordInMysic')) {
      return null;
    }
    final epoch = current.activityEpoch;
    return (id, trackId, ms) {
      if (!updatingActivity && connection?.activityEpoch == epoch) {
        onListened(generation, id, trackId, ms);
      }
    };
  }

  void onListened(String generation, String id, String trackId, int ms) {
    if (!isCurrent(generation) ||
        connection?.account?.historyPaused == true ||
        !(connection!.capabilities.contains('recordListen') ||
            connection!.capabilities.contains('recordInMysic'))) {
      return;
    }
    if (_pendingListens.length < 100) {
      _pendingListens.putIfAbsent(
        id,
        () => (
          trackId: trackId,
          ms: ms,
          epoch: connection!.isDirect ? connection!.activityEpoch : null,
        ),
      );
    }
    unawaited(_flushListens());
  }

  Future<void> _flushListens() async {
    final generation = connection?.generation;
    if (generation == null || !isCurrent(generation) || _submitting) return;
    _retry?.cancel();
    _submitting = true;
    try {
      while (_pendingListens.isNotEmpty && isCurrent(generation)) {
        final id = _pendingListens.keys.first;
        final listen = _pendingListens[id]!;
        try {
          final recorded = await _client.hasListen(generation, id);
          if (!isCurrent(generation)) return;
          if (!_pendingListens.containsKey(id)) continue;
          if (!recorded) {
            await _client.record(
              generation,
              id,
              listen.trackId,
              listen.ms,
              activityEpoch: listen.epoch,
            );
          }
          if (isCurrent(generation)) _pendingListens.remove(id);
        } on ApiFailure catch (error) {
          if (!isCurrent(generation)) return;
          if (error.code == 'MUSIC_LINK_CHANGED' ||
              error.code == 'MUSIC_RECONNECT') {
            unawaited(refresh(invalidate: true));
          } else if (error.code == 'MYSIC_ACTIVITY_CHANGED' ||
              error.code == 'MYSIC_HISTORY_PAUSED') {
            _pendingListens.remove(id);
            unawaited(refresh());
          } else if (error.code == 'MUSIC_LISTEN_CONFLICT' ||
              error.statusCode == 400 ||
              error.statusCode == 404) {
            _pendingListens.remove(id);
            continue;
          }
          return;
        } catch (_) {
          return;
        }
      }
    } finally {
      _submitting = false;
      // A new connection may have enqueued work while the old request drained.
      if (_active && connection?.generation != generation) {
        unawaited(_flushListens());
      } else if (isCurrent(generation) && _pendingListens.isNotEmpty) {
        _retry = Timer(const Duration(seconds: 15), _flushListens);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _forgetData();
    super.dispose();
  }
}
