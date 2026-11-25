import 'dart:convert';

/// Una canción de una playlist de Spotify: lo que dice la página pública.
class SpotifyTrack {
  const SpotifyTrack(this.title, this.artists);

  final String title;
  final List<String> artists;

  @override
  bool operator ==(Object other) =>
      other is SpotifyTrack &&
      other.title == title &&
      _same(other.artists, artists);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(artists));

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
}

/// Una playlist de Spotify leída de su página pública (sin cuenta ni API de
/// Spotify).
class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.name,
    required this.tracks,
    this.owner,
    this.cover,
    this.truncated = false,
  });

  final String name;
  final String? owner;
  final String? cover;
  final List<SpotifyTrack> tracks;

  /// La página pública deja leer como mucho las primeras 100 canciones: con
  /// ese tope puede que la lista tenga más.
  final bool truncated;
}

/// Por qué no se pudo leer un enlace de Spotify. Códigos cortos, como los del
/// escritorio.
enum SpotifyLinkError {
  /// No es un enlace de Spotify.
  notSpotify,

  /// Es de Spotify pero no es una playlist (por ahora solo se importan esas).
  notPlaylist,

  /// Privada, borrada o con el id mal escrito.
  private,

  /// Spotify cambió su página y no se puede leer.
  changed,

  /// Sin conexión o Spotify no respondió.
  network,
}

class SpotifyLinkFailure implements Exception {
  const SpotifyLinkFailure(this.error);

  final SpotifyLinkError error;

  String get message => switch (error) {
    SpotifyLinkError.notSpotify => 'Ese no es un enlace de Spotify.',
    SpotifyLinkError.notPlaylist =>
      'Por ahora solo se pueden importar playlists de Spotify.',
    SpotifyLinkError.private =>
      'Esa playlist de Spotify es privada o ya no existe.',
    SpotifyLinkError.changed =>
      'Spotify cambió su página y no se pudo leer esa playlist.',
    SpotifyLinkError.network =>
      'No se pudo leer la playlist de Spotify. Revisa tu conexión.',
  };

  @override
  String toString() => 'SpotifyLinkFailure($error)';
}

/// Qué es un enlace de Spotify: su tipo y su id.
typedef SpotifyTarget = ({String kind, String id});

/// El tipo y el id de lo que se pega, o null si no es de Spotify. Acepta las
/// formas que se pegan de verdad: `open.spotify.com/playlist/<id>?si=…`, con
/// `/intl-xx/` o `/embed/`, sin esquema, `/user/<nombre>/playlist/<id>` y
/// `spotify:playlist:<id>`.
SpotifyTarget? parseSpotifyLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final List<String> segments;
  if (text.toLowerCase().startsWith('spotify:')) {
    segments = text.substring(8).split(':');
  } else {
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    final host = uri?.host.toLowerCase();
    if (uri == null ||
        (host != 'open.spotify.com' && host != 'play.spotify.com')) {
      return null;
    }
    segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  }
  const kinds = {'track', 'album', 'artist', 'playlist'};
  // El tipo es la primera palabra conocida y el id el segmento siguiente: así
  // se saltan `intl-xx`, `embed` y `user/<nombre>`.
  for (var i = 0; i + 1 < segments.length; i++) {
    if (!kinds.contains(segments[i])) continue;
    final id = segments[i + 1];
    if (id.isNotEmpty &&
        id.length <= 64 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) {
      return (kind: segments[i], id: id);
    }
  }
  return null;
}

/// El máximo de canciones que deja leer la página pública de una playlist.
const spotifyMaxTracks = 100;

Map<String, dynamic>? _nextData(String html) {
  const open = '<script id="__NEXT_DATA__" type="application/json">';
  final start = html.indexOf(open);
  if (start < 0) return null;
  final from = start + open.length;
  final end = html.indexOf('</script>', from);
  if (end < 0) return null;
  try {
    final data = jsonDecode(html.substring(from, end));
    return data is Map<String, dynamic> ? data : null;
  } on FormatException {
    return null;
  }
}

String? _text(Object? map, String key) {
  if (map is! Map) return null;
  final value = map[key];
  return value is String && value.isNotEmpty ? value : null;
}

Object? _at(Object? root, List<String> path) {
  var node = root;
  for (final key in path) {
    if (node is Map) {
      node = node[key];
    } else if (node is List && int.tryParse(key) != null) {
      final index = int.parse(key);
      node = index < node.length ? node[index] : null;
    } else {
      return null;
    }
  }
  return node;
}

/// Lee la página «embed» de una playlist de Spotify. Lanza
/// [SpotifyLinkFailure] con `private` o `changed`.
SpotifyPlaylist parseSpotifyPlaylistEmbed(String html) {
  final data = _nextData(html);
  if (data == null) {
    throw const SpotifyLinkFailure(SpotifyLinkError.changed);
  }
  if (_at(data, ['props', 'pageProps', 'status']) == 404) {
    throw const SpotifyLinkFailure(SpotifyLinkError.private);
  }
  final entity = _at(data, ['props', 'pageProps', 'state', 'data', 'entity']);
  if (entity is! Map) {
    throw const SpotifyLinkFailure(SpotifyLinkError.private);
  }
  final name = _text(entity, 'name') ?? _text(entity, 'title');
  if (name == null) {
    throw const SpotifyLinkFailure(SpotifyLinkError.changed);
  }
  final cover = _at(entity, ['coverArt', 'sources', '0', 'url']);
  final list = entity['trackList'];
  final tracks = <SpotifyTrack>[];
  if (list is List) {
    for (final item in list) {
      if (item is! Map) continue;
      final type = item['entityType'];
      if (type is String && type != 'track') continue;
      final title = _text(item, 'title');
      if (title == null) continue;
      final artists = (_text(item, 'subtitle') ?? '')
          .split(', ')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      tracks.add(SpotifyTrack(title, artists));
      if (tracks.length >= spotifyMaxTracks) break;
    }
  }
  return SpotifyPlaylist(
    name: name,
    owner: _text(entity, 'subtitle'),
    cover: cover is String && cover.startsWith('https://') ? cover : null,
    tracks: tracks,
    truncated: tracks.length >= spotifyMaxTracks,
  );
}
