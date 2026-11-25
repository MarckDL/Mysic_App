import 'dart:async';

import '../../../core/text/fold_text.dart';
import '../../connected_library/domain/music_mode.dart' show MusicTrack;
import 'spotify_link.dart';

/// Cuánto se parece lo encontrado a la canción de Spotify (los niveles del
/// importador del escritorio y de Limusic).
enum MatchTier {
  /// Título y artista coinciden.
  matched,

  /// Hay un candidato razonable pero con dudas: se incluye y se avisa.
  check,

  /// Nada se le parece.
  missing,
}

/// El resultado de buscar una canción de Spotify en YouTube Music.
class MatchEntry {
  const MatchEntry(this.track, this.tier, {this.song, this.failed = false});

  final SpotifyTrack track;
  final MatchTier tier;

  /// La canción de YouTube Music que se usará; null si no se encontró.
  final MusicTrack? song;

  /// La búsqueda falló (red) y no es que la canción no exista.
  final bool failed;
}

// Sufijos de edición que Spotify añade al título («- 2015 Remaster»,
// «(Remastered 2011)», «- Radio Edit») y con los que YouTube Music no encuentra
// nada: se quitan, pero no un «feat.» ni un título que solo contenga un guion.
final _edition = RegExp(
  r'remaster|version|versión|edit\b|mono\b|stereo|deluxe|bonus|live\b|en vivo|\b(19|20)\d\d\b',
  caseSensitive: false,
);

String cleanTitle(String title) {
  var text = title;
  text = text.replaceAllMapped(
    RegExp(r'\s+-\s+([^-]*)$'),
    (m) => _edition.hasMatch(m[1]!) ? '' : m[0]!,
  );
  text = text.replaceAllMapped(
    RegExp(r'\s*[(\[]([^()\[\]]*)[)\]]'),
    (m) => _edition.hasMatch(m[1]!) ? '' : m[0]!,
  );
  return text.trim();
}

/// Texto comparable: minúsculas, sin tildes ni signos.
String normalizeText(String text) => foldText(
  text,
).replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

final _feature = RegExp(
  r'\s*[(\[]\s*(feat|ft|with)\b[^)\]]*[)\]]',
  caseSensitive: false,
);

/// De 0 a 1, cuánto se parecen dos títulos (sin sufijos de edición ni
/// «(feat. …)»).
double titleSimilarity(String a, String b) {
  final first = normalizeText(cleanTitle(a).replaceAll(_feature, ''));
  final second = normalizeText(cleanTitle(b).replaceAll(_feature, ''));
  if (first.isEmpty || second.isEmpty) return 0;
  if (first == second) return 1;
  if (first.contains(second) || second.contains(first)) return .9;
  final one = first.split(' ').toSet();
  final two = second.split(' ').toSet();
  final shared = one.where(two.contains).length;
  final smaller = one.length < two.length ? one.length : two.length;
  return shared / smaller * .8;
}

/// ¿Alguno de los artistas de Spotify aparece en el resultado (artista o
/// título)?
bool artistMatches(List<String> artists, MusicTrack result) {
  final haystack = normalizeText('${result.artist} ${result.title}');
  if (haystack.isEmpty) return false;
  return artists.any((name) {
    final clean = normalizeText(name);
    return clean.length > 1 && haystack.contains(clean);
  });
}

/// Texto de búsqueda de una pista de Spotify en YouTube Music: «título
/// artista principal».
String trackQuery(SpotifyTrack track) => [
  cleanTitle(track.title),
  if (track.artists.isNotEmpty) track.artists.first,
].where((part) => part.isNotEmpty).join(' ').trim();

/// Cuántos resultados de la búsqueda se miran.
const _candidates = 5;

/// La canción de YouTube Music para una de Spotify, entre los primeros
/// resultados de su búsqueda.
MatchEntry pickMatch(SpotifyTrack track, List<MusicTrack> results) {
  final candidates = results
      .where((song) => song.id.isNotEmpty)
      .take(_candidates)
      .toList();
  if (candidates.isEmpty) return MatchEntry(track, MatchTier.missing);
  final scored = [
    for (final (index, song) in candidates.indexed)
      (
        song: song,
        index: index,
        title: titleSimilarity(track.title, song.title),
        artist: artistMatches(track.artists, song),
      ),
  ];
  for (final entry in scored) {
    if (entry.title >= .8 && entry.artist) {
      return MatchEntry(track, MatchTier.matched, song: entry.song);
    }
  }
  final maybe =
      scored.where((e) => e.title >= .8 || (e.artist && e.title >= .5)).toList()
        ..sort((x, y) {
          final byScore = (y.title + (y.artist ? 1 : 0)).compareTo(
            x.title + (x.artist ? 1 : 0),
          );
          return byScore != 0 ? byScore : x.index.compareTo(y.index);
        });
  if (maybe.isNotEmpty) {
    return MatchEntry(track, MatchTier.check, song: maybe.first.song);
  }
  return MatchEntry(track, MatchTier.missing);
}

/// Busca todas las canciones con [concurrency] búsquedas a la vez. Una
/// búsqueda que falla se reintenta una vez; si vuelve a fallar, la canción
/// cuenta como no encontrada (`failed`). [onProgress] se llama con cada pista
/// resuelta. Devuelve la lista en el orden de las pistas; las que no llegaron a
/// mirarse (si se paró) quedan en null.
Future<List<MatchEntry?>> runMatching({
  required List<SpotifyTrack> tracks,
  required Future<List<MusicTrack>> Function(String query) search,
  required bool Function() cancelled,
  void Function(MatchEntry entry, int index)? onProgress,
  int concurrency = 4,
  Duration retryDelay = const Duration(milliseconds: 400),
}) async {
  final results = List<MatchEntry?>.filled(tracks.length, null);
  var next = 0;

  Future<MatchEntry> lookup(SpotifyTrack track) async {
    final query = trackQuery(track);
    if (query.isEmpty) return MatchEntry(track, MatchTier.missing);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return pickMatch(track, await search(query));
      } on Object {
        if (cancelled()) rethrow;
        if (attempt == 0) await Future<void>.delayed(retryDelay);
      }
    }
    return MatchEntry(track, MatchTier.missing, failed: true);
  }

  Future<void> worker() async {
    while (!cancelled()) {
      final index = next++;
      if (index >= tracks.length) return;
      final MatchEntry entry;
      try {
        entry = await lookup(tracks[index]);
      } on Object {
        return; // se paró en mitad de una búsqueda
      }
      if (cancelled()) return;
      results[index] = entry;
      onProgress?.call(entry, index);
    }
  }

  await Future.wait([
    for (
      var i = 0;
      i < (tracks.length < concurrency ? tracks.length : concurrency);
      i++
    )
      worker(),
  ]);
  return results;
}
