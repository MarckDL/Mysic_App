import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/connected_library/data/connected_client.dart';
import 'package:mysic/features/connected_library/data/link_platform.dart';
import 'fake_auth_repository.dart';

const host = 'pilot.example.test';
const sampleVideo = 'X9abc_dEfgh';
const samplePlaylist = 'PLMusic_fixture';
const id = '01234567-0123-4123-8123-0123456789ab';
final ref = 'r' * 43;
const linked = Connection(
  'linked',
  channel: Channel('ch', 'Canal de prueba'),
  generation: 'g1',
);
const previous = Connection(
  'linked',
  channel: Channel('old', 'Anterior'),
  generation: 'old',
);
final future = DateTime.now().add(const Duration(minutes: 9));

class MemoryPlatform extends LinkPlatform {
  final storage = <String, String>{};
  LinkReturn? incoming;
  VoidCallback? notifyReturn;
  @override
  void onReturn(void Function()? callback) {
    notifyReturn = callback;
  }

  bool opened = false;
  final uris = <Uri>[];
  @override
  Future<PendingLink?> load(String uid) async =>
      PendingLink.decode(storage[uid]);
  @override
  Future<void> save(String uid, PendingLink? pending) async {
    if (pending == null) {
      storage.remove(uid);
    } else {
      storage[uid] = pending.encode();
    }
  }

  @override
  Future<LinkReturn?> takeReturn() async {
    final value = incoming;
    incoming = null;
    return value;
  }

  @override
  Future<bool> open(Uri uri) async {
    uris.add(uri);
    opened = true;
    return true;
  }
}

class Client extends ConnectedClient {
  Client()
    : super(
        AuthenticatedApiClient(FakeAuthRepository(), baseUrl: 'https://$host'),
        Uri.https(host),
      );
  Connection current = const Connection('unlinked');
  final keys = <String>[], cancels = <String>[], confirms = <Json>[];
  final cursors = <String?>[], playlists = <String?>[];
  String status = 'awaiting_confirmation';
  String? reason;
  bool failStart = false, replace = false, throttle = false;
  bool failConnection = false, loseUnlinkResponse = false;
  int unlinks = 0;
  Completer<void>? wait;
  Attempt snapshot({bool launch = false}) => Attempt({
    'attemptId': id,
    'status': status,
    'expiresAt': future.toIso8601String(),
    'reason': reason,
    if (status == 'awaiting_confirmation')
      'channel': {'id': 'ch', 'title': 'Canal de prueba'},
    if (launch) 'launchUrl': 'https://$host$youtubeRoot/browser/start?ref=$ref',
  });
  @override
  Future<Connection> connection(CancelToken cancel) async {
    if (failConnection) throw const ApiFailure('offline');
    return current;
  }

  @override
  Future<Attempt> start(String key, bool force, CancelToken cancel) async {
    keys.add(key);
    await wait?.future;
    if (failStart) throw const ApiFailure('offline');
    return snapshot(launch: true);
  }

  @override
  Future<Attempt> attempt(String id, CancelToken cancel) async => snapshot();
  @override
  Future<void> confirm(String id, Json data, CancelToken cancel) async {
    confirms.add(data);
    if (replace && data['replace'] != true) {
      throw const ApiFailure(
        'replacement',
        statusCode: 409,
        code: 'CONFIRM_REPLACEMENT',
      );
    }
    current = linked;
    status = 'confirmed';
  }

  @override
  Future<void> cancelAttempt(String id, CancelToken cancel) async {
    cancels.add(id);
  }

  @override
  Future<void> unlink(CancelToken cancel, {String? generation}) async {
    unlinks++;
    current = const Connection('unlinked');
    if (loseUnlinkResponse) throw const ApiFailure('offline');
  }

  @override
  Future<LibraryPage> page(
    String? playlist,
    String? cursor,
    CancelToken cancel,
  ) async {
    cursors.add(cursor);
    playlists.add(playlist);
    if (playlist == samplePlaylist) {
      return (
        items: [
          LibraryRow.item({
            'playlistItemId': 'first',
            'videoId': sampleVideo,
            'title': 'Tema de prueba',
            'availability': 'available',
            'openUrl': 'https://www.youtube.com/watch?v=$sampleVideo',
          }),
          LibraryRow.item({
            'playlistItemId': 'second',
            'videoId': 'aBcDeFgHiJk',
            'title': 'Tema retirado',
            'availability': 'unavailable',
          }),
        ],
        next: null,
      );
    }
    if (current == previous) {
      return (
        items: [const LibraryRow('prev', 'Privada anterior')],
        next: null,
      );
    }
    const a = LibraryRow(
      'a',
      'Lista privada',
      subtitle: 'Privada · 11 elementos',
    );
    if (cursor == null) return (items: [a], next: 'page2');
    if (throttle) {
      throw const ApiFailure(
        'quota',
        statusCode: 429,
        code: 'TOO_MANY_REQUESTS',
        retryAfter: Duration(seconds: 2),
      );
    }
    return (items: [a, const LibraryRow('b', 'Lista pública')], next: null);
  }
}
