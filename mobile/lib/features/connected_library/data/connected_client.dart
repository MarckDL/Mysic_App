import 'package:dio/dio.dart';

import '../../../core/network/authenticated_api_client.dart';

typedef Json = Map<String, dynamic>;
const youtubeRoot = '/api/v1/integrations/youtube';
const returnPath = '/library/youtube/return';
final _playlistIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,150}$');

Uri? youtubeMusicPlaylistUri(String id) => _playlistIdPattern.hasMatch(id)
    ? Uri.https('music.youtube.com', '/playlist', {'list': id})
    : null;
final uuidPattern = RegExp(
  r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
);
final refPattern = RegExp(r'^[a-zA-Z0-9_-]{43}$');

class Channel {
  const Channel(this.id, this.title);
  final String id, title;
  static Channel? parse(dynamic value) => value is Json
      ? Channel(value['id'] as String, value['title'] as String)
      : null;
}

class Connection {
  const Connection(this.status, {this.channel, this.generation});
  final String status;
  final Channel? channel;
  final String? generation;
  bool get linked =>
      status == 'linked' && generation != null && channel != null;
  factory Connection.parse(Json json) => Connection(
    json['status'] as String,
    channel: Channel.parse(json['channel']),
    generation: json['generation'] as String?,
  );
}

class Attempt {
  Attempt(Json json)
    : id = json['attemptId'] as String,
      status = json['status'] as String,
      expires = DateTime.parse(json['expiresAt'] as String),
      reason = json['reason'] as String?,
      channel = Channel.parse(json['channel']),
      launch = json['launchUrl'] as String?;
  final String id, status;
  final String? reason, launch;
  final Channel? channel;
  final DateTime expires;
}

class LibraryRow {
  const LibraryRow(
    this.id,
    this.title, {
    this.subtitle,
    this.thumbnail,
    this.open,
  });
  final String id, title;
  final String? subtitle, thumbnail;
  final Uri? open;

  // Only the canonical watch URL previously validated by item() can supply
  // the video ID. The caller supplies the currently authorized playlist.
  Uri? musicUri(String playlistId) {
    final video = open?.queryParameters['v'];
    if (video == null || !_playlistIdPattern.hasMatch(playlistId)) return null;
    return Uri.https('music.youtube.com', '/watch', {
      'v': video,
      'list': playlistId,
    });
  }

  factory LibraryRow.playlist(Json row) {
    final count = row['itemCount'] as int?;
    final privacy = switch (row['visibility']) {
      'private' => 'Privada',
      'unlisted' => 'No listada',
      'public' => 'Pública',
      _ => null,
    };
    return LibraryRow(
      row['id'] as String,
      row['title'] as String,
      subtitle: [
        ?privacy,
        if (count != null) '$count ${count == 1 ? 'elemento' : 'elementos'}',
      ].join(' · '),
      thumbnail: row['thumbnailUrl'] as String?,
    );
  }
  factory LibraryRow.item(Json row) {
    final id = row['videoId'], status = row['availability'];
    final expected = id is String && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
        ? Uri.https('www.youtube.com', '/watch', {'v': id})
        : null;
    final open =
        status == 'available' &&
            expected != null &&
            row['openUrl'] == expected.toString()
        ? expected
        : null;
    final seconds = row['durationSeconds'] as int?;
    final duration = seconds == null
        ? null
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final details = <String>[
      if (row['channelTitle'] case final String channel) channel,
      ?duration,
      if (status == 'unavailable')
        'No disponible'
      else if (open == null)
        'Disponibilidad por confirmar',
    ];
    return LibraryRow(
      row['playlistItemId'] as String,
      row['title'] as String? ?? 'Video sin título',
      subtitle: details.join(' · '),
      thumbnail: row['thumbnailUrl'] as String?,
      open: open,
    );
  }
}

typedef LibraryPage = ({List<LibraryRow> items, String? next});

class ConnectedClient {
  ConnectedClient(this._api, this.base);
  final AuthenticatedApiClient _api;
  final Uri base;
  Future<Connection> connection(CancelToken cancel) async => Connection.parse(
    await _api.get('$youtubeRoot/connection', cancelToken: cancel),
  );
  Future<Attempt> start(String key, bool force, CancelToken cancel) async =>
      Attempt(
        await _api.post(
          '$youtubeRoot/link-attempts',
          body: {'forceConsent': force},
          idempotencyKey: key,
          cancelToken: cancel,
        ),
      );
  Future<Attempt> attempt(String id, CancelToken cancel) async => Attempt(
    await _api.get(
      '$youtubeRoot/link-attempts/${Uri.encodeComponent(id)}',
      cancelToken: cancel,
    ),
  );
  Future<void> confirm(String id, Json data, CancelToken cancel) async =>
      _api.post(
        '$youtubeRoot/link-attempts/${Uri.encodeComponent(id)}/confirm',
        body: data,
        cancelToken: cancel,
      );
  Future<void> cancelAttempt(String id, CancelToken cancel) async =>
      _api.delete(
        '$youtubeRoot/link-attempts/${Uri.encodeComponent(id)}',
        cancelToken: cancel,
      );
  Future<void> unlink(CancelToken cancel, {String? generation}) async =>
      _api.delete(
        '$youtubeRoot/connection',
        query: {if (generation != null) 'generation': generation},
        cancelToken: cancel,
      );
  Future<LibraryPage> page(
    String? playlist,
    String? cursor,
    CancelToken cancel,
  ) async {
    final data = await _api.get(
      '$youtubeRoot/playlists${playlist == null ? '' : '/${Uri.encodeComponent(playlist)}/items'}',
      query: {if (cursor != null) 'cursor': cursor},
      cancelToken: cancel,
    );
    return (
      items: (data['items'] as List)
          .cast<Json>()
          .map(playlist == null ? LibraryRow.playlist : LibraryRow.item)
          .toList(),
      next: data['nextCursor'] as String?,
    );
  }

  Uri? launchUri(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        !uri.isAbsolute ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.origin != base.origin ||
        uri.path != '$youtubeRoot/browser/start' ||
        uri.hasFragment ||
        uri.queryParametersAll.length != 1) {
      return null;
    }
    final ref = uri.queryParametersAll['ref'];
    return ref != null && ref.length == 1 && refPattern.hasMatch(ref.single)
        ? uri
        : null;
  }
}

String libraryError(Object error) {
  if (error is! ApiFailure) {
    return 'No pudimos completar la operación. Vuelve a intentarlo.';
  }
  return switch (error.code) {
    'MISSING_SCOPE' => 'Se necesita el permiso de lectura de YouTube.',
    'MISSING_REFRESH_TOKEN' =>
      'Google requiere que vuelvas a dar tu consentimiento.',
    'LINK_DISABLED' => 'La vinculación está desactivada en este servidor.',
    'NO_CHANNEL' => 'La cuenta elegida no tiene un canal de YouTube.',
    'SELECT_CHANNEL_IN_GOOGLE' =>
      'Vuelve a Google y selecciona un único canal.',
    'LINK_CONFLICT' =>
      'Ese canal ya tiene otra vinculación o una revocación pendiente.',
    'REAUTHORIZE_YOUTUBE' => 'Vuelve a conectar tu cuenta de YouTube.',
    'PLAYLIST_NOT_FOUND' => 'Esta playlist ya no está disponible.',
    'YOUTUBE_FORBIDDEN' => 'YouTube restringe el acceso a esta playlist.',
    'YOUTUBE_QUOTA' || 'TOO_MANY_REQUESTS' =>
      'Se alcanzó el límite de consultas. Inténtalo más tarde.',
    'INVALID_CURSOR' || 'CURSOR_EXPIRED' || 'YOUTUBE_LINK_CHANGED' =>
      'La biblioteca cambió. Actualiza para volver a cargarla.',
    _ =>
      error.statusCode == null
          ? 'Sin conexión con Mysic. Revisa tu red y reintenta.'
          : 'No se pudo completar la consulta. Inténtalo de nuevo.',
  };
}
