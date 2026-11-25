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

  /// "Artist • 1.2M monthly audience" o "422 subscribers" → cifra en español.
  /// Un subtítulo sin cifra de audiencia (p. ej. solo "Artista") se descarta.
  static String? _audience(Object? value) {
    final text = _text(value, 120);
    if (text == null) return null;
    for (final part in text.split(RegExp(r'\s[•·]\s'))) {
      final match = RegExp(
        r'^([\d.,]+\s?[KMB]?(?:\s(?:k|mil|M|millones|B))?)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(part.trim());
      if (match == null) continue;
      final unit = match.group(2)!.toLowerCase();
      final label = unit.contains('subscri') || unit.contains('suscrip')
          ? 'suscriptores'
          : unit.contains('listener') ||
                unit.contains('audience') ||
                unit.contains('oyente')
          ? 'oyentes'
          : null;
      if (label != null) return '${match.group(1)!.trim()} $label';
    }
    return null;
  }

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

  static MusicItem? item(Object? raw, String kind, {String? shelfTitle}) {
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
          shelfTitle: shelfTitle,
          artistId:
              raw['artistId'] is String &&
                  RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(raw['artistId'])
              ? raw['artistId'] as String
              : null,
          albumId:
              raw['albumId'] is String &&
                  _albumId.hasMatch(raw['albumId'] as String)
              ? raw['albumId'] as String
              : null,
        );
      case 'album':
        return MusicAlbum(
          id,
          title,
          thumbnailUrl: thumbnail,
          detail: [
            // En la discografía `kind` es la etiqueta visible ("Álbum", "EP");
            // en el resto de filas es la clave interna y no se muestra.
            if (raw['kind'] != 'album' && _text(raw['kind'], 40) != null)
              releaseKind(_text(raw['kind'], 40)!),
            ?_text(raw['year'], 8),
          ].join(' · ').nullIfEmpty,
          artist: _text(raw['artist'], 120),
          shelfTitle: shelfTitle,
        );
      case 'artist':
        return MusicArtist(
          id,
          title,
          thumbnailUrl: thumbnail,
          detail: _audience(raw['subtitle']),
          shelfTitle: shelfTitle,
        );
      case 'playlist':
        return MusicPlaylist(
          id.startsWith('VL') ? id.substring(2) : id,
          title,
          false,
          thumbnailUrl: thumbnail,
          shelfTitle: shelfTitle,
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

  static final _albumId = RegExp(r'^MPREb_[A-Za-z0-9_-]{6,60}$');
  static final _channelId = RegExp(r'^UC[A-Za-z0-9_-]{22}$');
  static bool isAlbumId(String id) => _albumId.hasMatch(id);

  /// YouTube entrega estos textos según el idioma de la solicitud (inglés).
  /// Se traducen los que se repiten en toda la discografía; los demás se dejan.
  static String shelfTitle(String title) {
    // «Playlists by <artista>»: se conserva el nombre.
    final by = RegExp(r'^playlists by (.+)$', caseSensitive: false);
    final match = by.firstMatch(title.trim());
    if (match != null) return 'Playlists de ${match.group(1)}';
    return _shelfTitle(title);
  }

  static String _shelfTitle(String title) =>
      switch (title.trim().toLowerCase()) {
        'albums' => 'Álbumes',
        'singles & eps' || 'singles and eps' => 'Sencillos y EP',
        'singles' => 'Sencillos',
        'eps' => 'EP',
        'videos' => 'Vídeos',
        'live performances' => 'Actuaciones en directo',
        'featured on' => 'Aparece en',
        'fans might also like' => 'También te puede gustar',
        'playlists' => 'Playlists',
        'compilations' => 'Recopilatorios',
        _ => title,
      };

  static String releaseKind(String kind) => switch (kind.trim().toLowerCase()) {
    'album' => 'Álbum',
    'single' => 'Sencillo',
    'ep' => 'EP',
    'compilation' => 'Recopilatorio',
    _ => kind,
  };

  /// "8 songs • 35 minutes" → "8 canciones • 35 minutos".
  static String albumInfo(String info) => info
      .replaceAllMapped(
        RegExp(r'\b(\d+)\s+(songs?|tracks?)\b'),
        (m) => '${m[1]} ${m[1] == '1' ? 'canción' : 'canciones'}',
      )
      .replaceAllMapped(RegExp(r'\b(\d+)\s+(hours?|minutes?|seconds?)\b'), (m) {
        final n = m[1]!, one = n == '1';
        return switch (m[2]![0]) {
          'h' => '$n ${one ? 'hora' : 'horas'}',
          'm' => '$n ${one ? 'minuto' : 'minutos'}',
          _ => '$n ${one ? 'segundo' : 'segundos'}',
        };
      });
  static bool isArtistId(String id) => _channelId.hasMatch(id);

  /// `GET youtube/artist/:id` del catálogo de Mysic.
  static ArtistProfile artistProfile(Map<String, dynamic> data) {
    final id = _text(data['id'], 150), name = _text(data['name']);
    if (id == null || name == null) {
      throw const FormatException('Mysic no devolvió el artista.');
    }
    List<MusicItem> list(Object? values, String kind) => [
      if (values is List)
        for (final row in values)
          if (item(row, kind) case final MusicItem entry) entry,
    ];
    return ArtistProfile(
      id: id,
      name: name,
      audience: _audience(data['subtitle']),
      description: _text(data['description'], 4000),
      thumbnailUrl: _art(data['thumbnail']),
      topSongs: list(data['topSongs'], 'song').whereType<MusicTrack>().toList(),
      shelves: _albumShelves(data['shelves']),
      videos: list(data['videos'], 'song').whereType<MusicTrack>().toList(),
      playlistShelves: [
        if (data['playlists'] is List)
          for (final shelf in data['playlists'] as List)
            if (shelf is Map && list(shelf['items'], 'playlist').isNotEmpty)
              (
                title: shelfTitle(_text(shelf['title'], 120) ?? 'Playlists'),
                items: list(shelf['items'], 'playlist'),
              ),
      ],
    );
  }

  /// Los estantes de álbumes (`shelves`) de la página o de `/releases`: cada
  /// uno con su título traducido; los que no traen ningún álbum válido se
  /// descartan.
  static List<({String title, List<MusicItem> items})> _albumShelves(
    Object? shelves,
  ) {
    final found = <({String title, List<MusicItem> items})>[];
    if (shelves is! List) return found;
    for (final shelf in shelves) {
      if (shelf is! Map || shelf['items'] is! List) continue;
      final items = <MusicItem>[
        for (final row in shelf['items'] as List)
          if (item(row, 'album') case final MusicItem entry) entry,
      ];
      if (items.isEmpty) continue;
      found.add((
        title: shelfTitle(_text(shelf['title'], 80) ?? 'Álbumes'),
        items: items,
      ));
    }
    return found;
  }

  /// `GET youtube/artist/:id/releases`: la discografía completa (la página
  /// solo trae los primeros álbumes).
  static List<({String title, List<MusicItem> items})> artistReleases(
    Map<String, dynamic> data,
  ) {
    if (data['shelves'] is! List) {
      throw const FormatException('Mysic no devolvió la discografía.');
    }
    return _albumShelves(data['shelves']);
  }

  /// `GET youtube/artist/:id/songs`: el catálogo completo de canciones.
  static List<MusicTrack> artistSongs(Map<String, dynamic> data) {
    if (data['songs'] is! List) {
      throw const FormatException('Mysic no devolvió las canciones.');
    }
    return rows(data['songs'], 'song').whereType<MusicTrack>().toList();
  }

  /// `GET youtube/album/:id` del catálogo de Mysic.
  static AlbumDetail albumDetail(Map<String, dynamic> data) {
    final id = _text(data['id'], 150), title = _text(data['title']);
    if (id == null || title == null || data['tracks'] is! List) {
      throw const FormatException('Mysic no devolvió el álbum.');
    }
    final artistId = _text(data['artistId'], 40);
    return AlbumDetail(
      id: id,
      title: title,
      artist: _text(data['artist']) ?? 'Artista desconocido',
      artistId: artistId != null && _channelId.hasMatch(artistId)
          ? artistId
          : null,
      year: _text(data['year'], 8),
      info: switch (_text(data['info'], 80)) {
        final String text => albumInfo(text),
        null => null,
      },
      thumbnailUrl: _art(data['thumbnail']),
      tracks: rows(data['tracks'], 'song').whereType<MusicTrack>().toList(),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
