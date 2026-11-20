import '../../../core/network/authenticated_api_client.dart';
import '../domain/music_mode.dart';

/// Maps only catalog metadata from the read-only endpoints of Mysic original.
/// Playback uses the YouTube video ID through the existing Mysic audio engine.
class OriginalMusicCatalog {
  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _browseId = RegExp(r'^[A-Za-z0-9_-]{1,150}$');
  static bool validId(String id) => _browseId.hasMatch(id);
  static String? cursor(Map<String, dynamic> data) =>
      _text(data['continuation'], 4096);
  static String? _text(Object? value, [int limit = 300]) =>
      value is String && value.trim().isNotEmpty && value.length <= limit
      ? value.trim()
      : null;

  static String? _art(Object? value) {
    final url = value is String ? Uri.tryParse(value) : null;
    if (url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.hasPort) {
      return null;
    }
    if ([
      'ytimg.com',
      'ggpht.com',
      'googleusercontent.com',
    ].any((suffix) => url.host == suffix || url.host.endsWith('.$suffix'))) {
      return url.toString();
    }
    return null;
  }

  static MusicItem? item(Object? raw, String kind) {
    if (raw is! Map) return null;
    final id = _text(raw['id'], 150),
        title = _text(raw['title'] ?? raw['name']);
    if (id == null || title == null || !_browseId.hasMatch(id)) return null;
    final thumbnail = _art(raw['thumbnail']);
    switch (kind) {
      case 'song':
        if (!_videoId.hasMatch(id)) return null;
        final seconds = raw['durationSeconds'];
        return MusicTrack(
          id,
          title,
          _text(raw['artist']) ?? 'Artista desconocido',
          seconds is int && seconds >= 0 && seconds <= 86400 ? seconds : 0,
          false,
          null,
          nativePlayback: true,
          thumbnailUrl: thumbnail,
          artistId:
              raw['artistId'] is String &&
                  RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(raw['artistId'])
              ? raw['artistId'] as String
              : null,
        );
      case 'album':
        return MusicAlbum(id, title, thumbnailUrl: thumbnail);
      case 'artist':
        return MusicArtist(id, title, thumbnailUrl: thumbnail);
      case 'playlist':
        return MusicPlaylist(
          id.startsWith('VL') ? id.substring(2) : id,
          title,
          false,
          thumbnailUrl: thumbnail,
        );
      default:
        return null;
    }
  }

  static List<MusicItem> rows(Object? values, String kind) {
    if (values is! List) {
      throw const FormatException(
        'Mysic original no devolvió la colección solicitada.',
      );
    }
    return [
      for (final row in values)
        if (item(row, kind) case final MusicItem entry) entry,
    ];
  }

  static MusicPage homePage(Map<String, dynamic> data, {required bool first}) {
    if ((first && data['personalized'] != true) || data['shelves'] is! List) {
      throw const ApiFailure(
        'Mysic de escritorio no entregó el Inicio personal de esta cuenta.',
        code: 'DESKTOP_HOME',
      );
    }
    final items = <MusicItem>[];
    var recognizedShelf = false, hasRows = false;
    for (final shelf in data['shelves'] as List) {
      if (shelf is! Map || shelf['items'] is! List) continue;
      recognizedShelf = true;
      final rows = shelf['items'] as List;
      hasRows = hasRows || rows.isNotEmpty;
      for (final row in rows) {
        if (row is! Map || row['kind'] is! String) continue;
        final entry = item(row, row['kind'] as String);
        if (entry != null) items.add(entry);
      }
    }
    if ((data['shelves'] as List).isNotEmpty &&
        (!recognizedShelf || (hasRows && items.isEmpty))) {
      throw const ApiFailure(
        'Mysic no pudo leer las recomendaciones de esta cuenta.',
        code: 'DESKTOP_HOME',
      );
    }
    return MusicPage(items, cursor(data), null, 0);
  }
}
