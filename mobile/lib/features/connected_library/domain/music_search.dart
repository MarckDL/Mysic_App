import 'music_mode.dart';

/// Los filtros de la pestaña Buscar, en el orden de sus chips.
enum SearchKind { all, songs, videos, albums, artists, playlists }

/// Lo que devuelve una búsqueda: el resultado principal de YouTube Music con
/// su línea y las canciones que le empareja, y una lista por tipo.
class SearchResults {
  const SearchResults({
    this.top,
    this.topSubtitle = '',
    this.topSongs = const [],
    this.songs = const [],
    this.videos = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  final MusicItem? top;
  final String topSubtitle;
  final List<MusicTrack> topSongs;
  final List<MusicTrack> songs;
  final List<MusicTrack> videos;
  final List<MusicAlbum> albums;
  final List<MusicArtist> artists;
  final List<MusicPlaylist> playlists;

  /// Si el filtro [kind] tiene algo que enseñar.
  bool has(SearchKind kind) => switch (kind) {
    SearchKind.all =>
      top != null ||
          songs.isNotEmpty ||
          videos.isNotEmpty ||
          albums.isNotEmpty ||
          artists.isNotEmpty ||
          playlists.isNotEmpty,
    SearchKind.songs => songs.isNotEmpty,
    SearchKind.videos => videos.isNotEmpty,
    SearchKind.albums => albums.isNotEmpty,
    SearchKind.artists => artists.isNotEmpty,
    SearchKind.playlists => playlists.isNotEmpty,
  };

  /// Los mismos resultados con la lista completa de un tipo ([items] viene de
  /// la búsqueda filtrada de [kind]).
  SearchResults withKind(SearchKind kind, List<MusicItem> items) =>
      SearchResults(
        top: top,
        topSubtitle: topSubtitle,
        topSongs: topSongs,
        songs: kind == SearchKind.songs
            ? items.whereType<MusicTrack>().toList()
            : songs,
        videos: kind == SearchKind.videos
            ? items.whereType<MusicTrack>().toList()
            : videos,
        albums: kind == SearchKind.albums
            ? items.whereType<MusicAlbum>().toList()
            : albums,
        artists: kind == SearchKind.artists
            ? items.whereType<MusicArtist>().toList()
            : artists,
        playlists: kind == SearchKind.playlists
            ? items.whereType<MusicPlaylist>().toList()
            : playlists,
      );
}

/// Lo que se propone mientras se escribe: consultas y elementos directos.
class SearchSuggestions {
  const SearchSuggestions({this.queries = const [], this.items = const []});

  final List<String> queries;
  final List<MusicItem> items;
}

/// Un ambiente o género de YouTube Music: su nombre, la clave para abrirlo y
/// el color (ARGB) con que YouTube lo marca.
class MoodItem {
  const MoodItem(this.title, this.params, this.color);

  final String title;
  final String params;
  final int color;
}

/// Una sección de «Ambientes y géneros» («Para ti», «Ambientes», «Géneros»).
class MoodSection {
  const MoodSection(this.title, this.items);

  final String title;
  final List<MoodItem> items;

  /// Las secciones de un JSON `{sections: [{title, items: [...]}]}`; lo que
  /// no se entiende se descarta.
  static List<MoodSection> listFromJson(Object? data) {
    final sections = <MoodSection>[];
    if (data is! List) return sections;
    for (final section in data) {
      if (section is! Map || section['items'] is! List) continue;
      final items = <MoodItem>[
        for (final item in section['items'] as List)
          if (item is Map &&
              item['title'] is String &&
              item['params'] is String &&
              (item['params'] as String).isNotEmpty)
            MoodItem(
              item['title'] as String,
              item['params'] as String,
              item['color'] is int ? item['color'] as int : 0,
            ),
      ];
      if (items.isNotEmpty) {
        sections.add(
          MoodSection(
            section['title'] is String ? section['title'] as String : '',
            items,
          ),
        );
      }
    }
    return sections;
  }
}
