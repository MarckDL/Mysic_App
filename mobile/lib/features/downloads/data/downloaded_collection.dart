/// Un álbum o una playlist descargados enteros (Limusic: la fila del álbum o
/// de la playlist con `downloadState = STATE_DOWNLOADED` y su lista de
/// canciones). Las canciones se guardan aparte, en el índice de descargas;
/// esto recuerda la colección: su portada, su nombre y qué canciones son
/// suyas, para mostrarla en Descargas y para que quitarla no borre las
/// canciones que también guarda otra.
class DownloadedCollection {
  const DownloadedCollection({
    required this.id,
    required this.album,
    required this.title,
    required this.trackIds,
    required this.savedAt,
    this.subtitle,
    this.thumbnailUrl,
  });

  /// El álbum (`MPREb_…`) o la playlist (sin `VL`).
  final String id;
  final bool album;
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;

  /// Las canciones de la colección (ids de vídeo de 11 caracteres), en su
  /// orden.
  final List<String> trackIds;

  /// Cuándo se pidió la descarga (milisegundos desde 1970).
  final int savedAt;

  static final _track = RegExp(r'^[A-Za-z0-9_-]{11}$');

  Map<String, Object?> toJson() => {
    'id': id,
    'album': album,
    'title': title,
    'subtitle': subtitle,
    'thumbnailUrl': thumbnailUrl,
    'trackIds': trackIds,
    'savedAt': savedAt,
  };

  static DownloadedCollection? fromJson(Object? data) {
    if (data is! Map) return null;
    final id = data['id'];
    final title = data['title'];
    final savedAt = data['savedAt'];
    final tracks = data['trackIds'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        title is! String ||
        savedAt is! int ||
        tracks is! List) {
      return null;
    }
    String? text(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return DownloadedCollection(
      id: id,
      album: data['album'] == true,
      title: title,
      subtitle: text('subtitle'),
      thumbnailUrl: text('thumbnailUrl'),
      trackIds: [
        for (final track in tracks)
          if (track is String && _track.hasMatch(track)) track,
      ],
      savedAt: savedAt,
    );
  }
}
