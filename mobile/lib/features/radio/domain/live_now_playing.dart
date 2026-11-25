/// Lo que suena ahora en una radio, según el JSON público de la emisora.
class LiveNowPlaying {
  const LiveNowPlaying({
    required this.title,
    this.artist,
    this.program,
    this.artwork,
    this.startedAt,
    this.endsAt,
    this.trackEndsAt,
    this.curator,
    this.label,
    this.moods = const [],
    this.showImage,
  });

  /// La foto del programa en el aire (`https`); sirve de portada cuando la
  /// canción no tiene la suya.
  final String? showImage;

  /// Cuándo empieza y cuándo acaba el programa en el aire, si la emisora lo da
  /// (ROVR): la línea de tiempo del reproductor es la del programa (su contador
  /// «84:01»). Llevan sumado el retraso del streaming, o sea, son los momentos
  /// en que llegan al oyente.
  final DateTime? startedAt, endsAt;

  /// Cuándo acaba la canción que suena (para volver a preguntar entonces).
  final DateTime? trackEndsAt;

  /// Quién presenta el programa («BY Pink Siifu»).
  final String? curator;

  /// La discográfica de la canción.
  final String? label;

  /// Los moods del programa (DREAM, CHILL, BRAIN…), en mayúsculas.
  final List<String> moods;

  /// Lo que se adelanta el programa respecto a lo que se oye. Cero: la web de
  /// ROVR cuenta desde la hora de la pared sin ajustes (su contador «103:17»),
  /// y el título de la canción sale del propio audio (ID3), no de este cálculo.
  static const rovrDelay = Duration.zero;

  /// La hora de pared del teléfono como un `DateTime` UTC «de mentira»: la
  /// programación de ROVR viene en la hora del huso de la señal (la del
  /// usuario), sin zona, así que se compara campo a campo.
  static DateTime wall(DateTime instant) {
    final t = instant.toLocal();
    return DateTime.utc(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
    );
  }

  /// Lo contrario: la hora de pared de la programación como un instante real
  /// (en la zona del teléfono), para la línea de tiempo.
  static DateTime instant(DateTime wall) => DateTime(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
    wall.millisecond,
  );

  final String title;
  final String? artist;

  /// El programa en el aire («MEMORY LANE AGAIN»).
  final String? program;

  /// La carátula de la canción: dirección `https`.
  final String? artwork;

  static const _maxText = 160;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty || text.length > _maxText ? null : text;
  }

  /// null si el JSON no trae una canción. Acepta `artist` y la errata `aartist`
  /// que usa la emisora de fábrica; la carátula solo si es `https`.
  static LiveNowPlaying? parse(Object? json, {DateTime? now}) {
    if (json is! Map) return null;
    if (json['nowPlaying'] is Map) return _spinitron(json['nowPlaying'] as Map);
    if (json['data'] is List) {
      return _rovr(
        json['data'] as List,
        LiveNowPlaying.wall(now ?? DateTime.now()),
      );
    }
    final title = _text(json['title']);
    if (title == null) return null;
    final image = _text(json['imagepath']);
    final uri = image == null ? null : Uri.tryParse(image);
    final safe =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
    return LiveNowPlaying(
      title: title,
      artist: _text(json['artist']) ?? _text(json['aartist']),
      program: _text(json['program']),
      artwork: safe ? image : null,
    );
  }
}

/// La forma de Spinitron (la usan muchas radios universitarias):
/// `{nowPlaying: {title: programa, djs: [{name}], song: {title, artist}}}`.
/// Con canción: título y artista de la canción, y el programa aparte. Sin ella
/// (entre canciones, o un programa hablado): el programa como título y sus
/// locutores como artista. Spinitron no da carátula.
LiveNowPlaying? _spinitron(Map show) {
  final program = LiveNowPlaying._text(show['title']);
  final song = show['song'];
  if (song is Map) {
    final title = LiveNowPlaying._text(song['title']);
    if (title != null) {
      return LiveNowPlaying(
        title: title,
        artist: LiveNowPlaying._text(song['artist']),
        program: program,
      );
    }
  }
  if (program == null) return null;
  final djs = show['djs'];
  final names = djs is List
      ? [
          for (final dj in djs)
            if (dj is Map && LiveNowPlaying._text(dj['name']) != null)
              LiveNowPlaying._text(dj['name'])!,
        ]
      : const <String>[];
  return LiveNowPlaying(
    title: program,
    artist: names.isEmpty ? null : names.join(', '),
  );
}

/// La forma de ROVR: la programación de la radio a una hora dada,
/// `{data: [{startTime (UTC), show: {title, curators}, playlist: {tracks,
/// stitchedTracksMetadata: {tracks_cues: [{start, end, track_index}]}}}]}`.
/// Cada programa es una mezcla continua: las marcas dicen en qué segundo del
/// programa empieza cada pista, así que la que suena ahora es la última cuyo
/// inicio ya pasó. Si no se puede saber, se muestra el programa y su curador.
LiveNowPlaying? _rovr(List data, DateTime now) {
  final entry = data.firstOrNull;
  if (entry is! Map) return null;
  final show = entry['show'];
  final playlist = entry['playlist'];
  final showMap = show is Map ? show : const {};
  final program = LiveNowPlaying._text(
    (playlist is Map ? playlist['overwriteShowName'] : null) ??
        showMap['title'],
  );
  final curators = showMap['curators'];
  final curator = curators is List && curators.isNotEmpty
      ? (curators.first is Map
            ? LiveNowPlaying._text((curators.first as Map)['name'])
            : null)
      : null;
  // La foto del programa, si es https.
  final radioImage = showMap['radioImage'];
  final imageText = radioImage is Map
      ? LiveNowPlaying._text(radioImage['url'])
      : null;
  final imageUri = imageText == null ? null : Uri.tryParse(imageText);
  final showImage =
      imageUri != null &&
          imageUri.scheme == 'https' &&
          imageUri.host.isNotEmpty &&
          imageUri.userInfo.isEmpty &&
          !imageUri.hasFragment
      ? imageText
      : null;
  // Los moods del programa y su ventana (de inicio a fin, en hora de pared).
  final tags = playlist is Map ? playlist['playlistTags'] : null;
  final moods = <String>[
    if (tags is List)
      for (final tag in tags)
        if (tag is Map && LiveNowPlaying._text(tag['label']) != null)
          LiveNowPlaying._text(tag['label'])!.toUpperCase(),
  ];
  DateTime? utc(Object? text) =>
      DateTime.tryParse('${'$text'.replaceFirst(' ', 'T')}Z');
  final started = utc(entry['startTime']);
  final finished = utc(entry['endTime']);
  DateTime? shifted(DateTime? t) => t == null
      ? null
      : LiveNowPlaying.instant(t).add(LiveNowPlaying.rovrDelay);
  LiveNowPlaying? fallback() => program == null
      ? null
      : LiveNowPlaying(
          title: program,
          artist: curator,
          curator: curator,
          moods: moods,
          showImage: showImage,
          startedAt: shifted(started),
          endsAt: shifted(finished),
        );

  if (started == null || playlist is! Map) return fallback();
  final tracks = playlist['tracks'];
  final meta = playlist['stitchedTracksMetadata'];
  final cues = meta is Map ? meta['tracks_cues'] : null;
  if (tracks is! List || cues is! List) return fallback();
  // Lo que se oye ahora es lo que pasó hace [rovrDelay] en el programa.
  final elapsed =
      now
          .subtract(LiveNowPlaying.rovrDelay)
          .difference(started)
          .inMilliseconds /
      1000;
  Map? current;
  for (final cue in cues) {
    if (cue is Map && cue['start'] is num && (cue['start'] as num) <= elapsed) {
      current = cue;
    }
  }
  final index = current?['track_index'];
  if (index is! int || index < 0 || index >= tracks.length) return fallback();
  final track = tracks[index];
  if (track is! Map) return fallback();
  final title = LiveNowPlaying._text(track['title']);
  if (title == null) return fallback();
  final cover = LiveNowPlaying._text(track['albumCoverUrl']);
  final uri = cover == null ? null : Uri.tryParse(cover);
  final safe =
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;
  // Cuándo acaba esta canción, para preguntar de nuevo justo entonces.
  final start = current!['start'] as num;
  final cueEnd = current['end'];
  final duration = track['duration'];
  final endSeconds = cueEnd is num && cueEnd > start
      ? cueEnd
      : duration is num && duration > 0
      ? start + duration
      : null;
  return LiveNowPlaying(
    title: title,
    artist: LiveNowPlaying._text(track['artist']),
    program: program,
    artwork: safe ? cover : null,
    startedAt: shifted(started),
    endsAt: shifted(finished),
    trackEndsAt: endSeconds == null
        ? null
        : LiveNowPlaying.instant(
            started.add(Duration(milliseconds: (endSeconds * 1000).round())),
          ).add(LiveNowPlaying.rovrDelay),
    curator: curator,
    label: LiveNowPlaying._text(track['label']),
    moods: moods,
    showImage: showImage,
  );
}

/// Pide el JSON de una emisora; null si no se pudo o no trae canción.
typedef LiveInfoFetcher = Future<LiveNowPlaying?> Function(Uri url);
