import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'connected_client.dart';

class PendingLink {
  const PendingLink(this.key, this.expires, {this.id, this.force = false});
  final String key;
  final String? id;
  final DateTime expires;
  final bool force;
  String encode() => jsonEncode({
    'key': key,
    'id': id,
    'expires': expires.toUtc().toIso8601String(),
    'force': force,
  });
  static PendingLink? decode(String? value) {
    if (value == null) return null;
    try {
      final data = jsonDecode(value) as Json;
      final key = data['key'] as String, id = data['id'] as String?;
      if (!uuidPattern.hasMatch(key) ||
          (id != null && !uuidPattern.hasMatch(id))) {
        return null;
      }
      return PendingLink(
        key,
        DateTime.parse(data['expires'] as String),
        id: id,
        force: data['force'] == true,
      );
    } on Object {
      return null;
    }
  }
}

typedef LinkReturn = ({String id, String? ref});
LinkReturn? parseLinkReturn(String? raw, String host) {
  if (raw == null || raw.length > 512 || host.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != host ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.path != returnPath) {
    return null;
  }
  try {
    final fields = Uri(query: uri.fragment).queryParametersAll;
    final ids = fields['attemptId'], refs = fields['returnRef'];
    if (fields.keys.any((key) => key != 'attemptId' && key != 'returnRef') ||
        ids == null ||
        ids.length != 1 ||
        !uuidPattern.hasMatch(ids.single)) {
      return null;
    }
    if (refs != null &&
        (refs.length != 1 || !refPattern.hasMatch(refs.single))) {
      return null;
    }
    return (id: ids.single, ref: refs?.single);
  } on FormatException {
    return null;
  }
}

class LinkPlatform {
  static const channel = MethodChannel('com.mysic/connected_library');
  static const host = String.fromEnvironment('YOUTUBE_APP_LINK_HOST');
  Future<PendingLink?> load(String uid) async => PendingLink.decode(
    await channel.invokeMethod<String>('load', {'uid': uid}),
  );
  Future<void> save(String uid, PendingLink? pending) => channel
      .invokeMethod<void>('save', {'uid': uid, 'data': pending?.encode()});
  Future<LinkReturn?> takeReturn() async =>
      parseLinkReturn(await channel.invokeMethod<String>('takeReturn'), host);
  void onReturn(void Function()? callback) {
    channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'returnReady') callback();
            },
    );
  }

  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
