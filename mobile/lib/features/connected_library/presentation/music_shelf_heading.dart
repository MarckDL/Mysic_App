/// The desktop service can send editorial shelf names in English even when the
/// user is listening in Spanish. Artist names and unknown headings stay intact.
String? musicShelfHeading(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final heading = value.trim();
  const translated = {
    'quick picks': 'Selección rápida',
    'listen again': 'Volver a escuchar',
    'albums for you': 'Álbumes para ti',
    'featured playlists for you': 'Playlists destacadas para ti',
    'featured playlists': 'Playlists destacadas',
    'mixed for you': 'Mixes para ti',
    'from your library': 'De tu biblioteca',
    'forgotten favorites': 'Favoritos olvidados',
    'recommended for you': 'Recomendado para ti',
    'music videos for you': 'Vídeos musicales para ti',
    'new releases': 'Novedades',
    'new albums & singles': 'Álbumes y sencillos nuevos',
    'new albums and singles': 'Álbumes y sencillos nuevos',
    'trending': 'Tendencias',
    'new music videos': 'Vídeos musicales nuevos',
    'from the community': 'De la comunidad',
    'similar songs': 'Canciones similares',
    'recommended playlists': 'Playlists recomendadas',
    'fans might also like': 'También te puede gustar',
    'you might also like': 'También te puede gustar',
    'more from this artist': 'Más de este artista',
    'similar artists': 'Artistas similares',
  };
  final key = heading.toLowerCase();
  for (final entry in const {
    'because you listened to ': 'Porque escuchaste ',
    'based on ': 'Basado en ',
  }.entries) {
    if (key.startsWith(entry.key) && heading.length > entry.key.length) {
      return entry.value + heading.substring(entry.key.length);
    }
  }
  return translated[key] ?? heading;
}
