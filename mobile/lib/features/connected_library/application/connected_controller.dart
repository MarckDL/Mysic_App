import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../../../core/network/request_id.dart';
import '../data/connected_client.dart';
import '../data/link_platform.dart';

class ConnectedController extends ChangeNotifier {
  ConnectedController(this.uid, this.client, this.platform);
  final String uid;
  final ConnectedClient client;
  final LinkPlatform platform;
  final _cancel = CancelToken();
  late Future<void> _tail = Future.value();
  bool _dead = false, _loaded = false;
  bool busy = false, forceConsent = false, replaceRequired = false;
  Connection? connection;
  PendingLink? pending;
  Channel? candidate;
  String? message;
  bool get alive => !_dead;

  Future<void> _serial(Future<void> Function() action) {
    return _tail = _tail.then((_) async {
      if (_dead) return;
      busy = true;
      _notify();
      try {
        await action();
      } catch (e) {
        if (!_dead) message = libraryError(e);
      } finally {
        busy = false;
        _notify();
      }
    });
  }

  void _notify() {
    if (!_dead) notifyListeners();
  }

  Future<void> _write(PendingLink? value) async {
    if (_dead) return;
    await platform.save(uid, value);
    if (!_dead) pending = value;
  }

  Future<void> _end() async {
    candidate = null;
    replaceRequired = false;
    await _write(null);
  }

  Future<void> _connection() async {
    final value = await client.connection(_cancel);
    if (!_dead) connection = value;
  }

  Future<void> sync({bool browser = false, void Function()? onReturn}) =>
      _serial(() async {
        message = null;
        if (!_loaded) {
          pending = await platform.load(uid);
          _loaded = true;
        }
        final returned = browser ? await platform.takeReturn() : null;
        if (_dead) return;
        final match = returned != null && pending?.id == returned.id;
        if (match) onReturn?.call();
        if (pending != null && !pending!.expires.isAfter(DateTime.now())) {
          await _end();
          message = 'El intento venció. Puedes volver a vincular.';
        } else if (pending?.id != null) {
          await _inspect(match ? returned.ref : null);
        }
        await _connection();
      });
  Future<void> start({bool restart = false}) => _serial(() async {
    message = null;
    candidate = null;
    replaceRequired = false;
    PendingLink? local = pending;
    if (restart || local == null || !local.expires.isAfter(DateTime.now())) {
      local = PendingLink(
        newRequestId(),
        DateTime.now().add(const Duration(minutes: 10)),
        force: forceConsent,
      );
      await _write(local);
    }
    if (_dead) return;
    final Attempt started;
    try {
      started = await client.start(local.key, local.force, _cancel);
    } on ApiFailure catch (error) {
      if (error.code == 'LINK_DISABLED') await _end();
      rethrow;
    }
    if (_dead) return;
    await _write(
      PendingLink(
        local.key,
        started.expires,
        id: started.id,
        force: local.force,
      ),
    );
    if (_dead) return;
    if (started.launch == null) {
      await _inspect(null);
      return;
    }
    final uri = client.launchUri(started.launch);
    if (uri == null || !await platform.open(uri)) {
      message = 'No se pudo abrir el navegador. Reintenta la vinculación.';
    }
  });
  Future<void> _inspect(String? returnRef) async {
    final local = pending;
    if (local?.id == null) return;
    final Attempt attempt;
    try {
      attempt = await client.attempt(local!.id!, _cancel);
    } on ApiFailure catch (e) {
      if (e.statusCode != 404) rethrow;
      await _end();
      message = 'Este intento ya no está disponible.';
      return;
    }
    if (_dead || attempt.id != local.id) return;
    switch (attempt.status) {
      case 'awaiting_confirmation':
        candidate = attempt.channel;
        message = null;
        if (returnRef != null) await _confirm({'returnRef': returnRef});
      case 'confirmed':
        await _end();
        forceConsent = false;
        message = null;
      case 'created':
      case 'authorizing':
      case 'exchanging':
        message = null;
      default:
        await _end();
        forceConsent =
            attempt.reason == 'MISSING_REFRESH_TOKEN' ||
            attempt.reason == 'MISSING_SCOPE';
        message = switch (attempt.status) {
          'denied' || 'canceled' => 'La vinculación se canceló.',
          'expired' => 'El intento venció. Puedes volver a vincular.',
          _ => libraryError(ApiFailure('', code: attempt.reason)),
        };
    }
  }

  Future<void> _confirm(Json body) async {
    final id = pending?.id;
    if (id == null) return;
    try {
      await client.confirm(id, body, _cancel);
    } on ApiFailure catch (e) {
      if (e.code != 'CONFIRM_REPLACEMENT') rethrow;
      replaceRequired = true;
      message = null;
      return;
    }
    await _end();
    forceConsent = false;
    message = null;
  }

  Future<void> confirmCandidate() => _serial(() async {
    final channel = candidate;
    if (channel == null) return;
    await _confirm({
      'channelId': channel.id,
      if (replaceRequired) 'replace': true,
    });
    await _connection();
  });
  Future<void> cancel() => _serial(() async {
    final id = pending?.id;
    if (id != null) {
      try {
        await client.cancelAttempt(id, _cancel);
      } on ApiFailure catch (error) {
        if (error.statusCode != 404) rethrow;
      }
    }
    await _end();
    await _connection();
    message = 'La vinculación se canceló.';
  });
  Future<void> unlink() => _serial(() async {
    message = null;
    await client.unlink(_cancel);
    connection = null;
    _notify();
    await _end();
    forceConsent = false;
    await _connection();
  });
  @override
  void dispose() {
    _dead = true;
    _cancel.cancel();
    super.dispose();
  }
}
