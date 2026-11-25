import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_failure.dart';
import '../../connected_library/domain/music_mode.dart' show MusicTrack;
import '../domain/spotify_link.dart';
import '../domain/spotify_matching.dart';

/// En qué punto va la importación: pegar el enlace, ver la lista, buscar sus
/// canciones en YouTube Music, guardar la playlist en la cuenta.
enum SpotifyImportPhase {
  idle,
  loading,
  preview,
  matching,
  saving,
  done,
  failed,
  cancelled,
}

/// Una fila de «últimas encontradas».
typedef RecentMatch = ({String title, String artists, MatchTier tier});

/// La importación de una playlist de Spotify a una playlist de la cuenta de
/// YouTube Music (la de Mysic de escritorio y la de Limusic): se leen sus
/// canciones de la página pública, se busca cada una en YouTube Music y con lo
/// encontrado se crea la playlist.
class SpotifyImportController extends ChangeNotifier {
  SpotifyImportController({
    required this.fetch,
    required this.search,
    required this.create,
    this.concurrency = 4,
    this.retryDelay = const Duration(milliseconds: 400),
  });

  /// Lee la playlist de Spotify con ese id.
  final Future<SpotifyPlaylist> Function(String id) fetch;

  /// Busca [query] en YouTube Music: sus canciones.
  final Future<List<MusicTrack>> Function(String query) search;

  /// Crea la playlist en la cuenta con esas canciones (ids de vídeo) y
  /// devuelve su id.
  final Future<String> Function(
    String title,
    String description,
    List<String> videoIds,
  )
  create;

  final int concurrency;
  final Duration retryDelay;

  SpotifyImportPhase phase = SpotifyImportPhase.idle;
  SpotifyPlaylist? playlist;
  String? message;

  int done = 0;
  int matched = 0;
  int check = 0;
  int missing = 0;
  int failed = 0;
  final recent = <RecentMatch>[];
  final checkList = <({String title, String artists, String found})>[];
  final missingList = <({String title, String artists})>[];

  /// La playlist creada en la cuenta y cuántas canciones lleva.
  String? createdId;
  int created = 0;

  bool _cancel = false;
  bool _disposed = false;

  int get total => playlist?.tracks.length ?? 0;
  int get found => matched + check;
  int get percent =>
      total == 0 ? 0 : (done / total * 100).floor().clamp(0, 100);
  bool get busy =>
      phase == SpotifyImportPhase.loading ||
      phase == SpotifyImportPhase.matching ||
      phase == SpotifyImportPhase.saving;

  /// Las canciones no encontradas, una por línea (para copiarlas y buscarlas a
  /// mano).
  String get missingText => missingList
      .map((e) => [e.title, e.artists].where((s) => s.isNotEmpty).join(' - '))
      .join('\n');

  void _set(SpotifyImportPhase next, {String? text}) {
    phase = next;
    message = text;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel = true;
    super.dispose();
  }

  /// Lee el enlace pegado y deja lista la vista previa. Por ahora solo
  /// playlists.
  Future<void> open(String link) async {
    if (busy) return;
    final target = parseSpotifyLink(link);
    if (target == null) {
      _set(
        SpotifyImportPhase.failed,
        text: const SpotifyLinkFailure(SpotifyLinkError.notSpotify).message,
      );
      return;
    }
    if (target.kind != 'playlist') {
      _set(
        SpotifyImportPhase.failed,
        text: const SpotifyLinkFailure(SpotifyLinkError.notPlaylist).message,
      );
      return;
    }
    _reset();
    _set(SpotifyImportPhase.loading);
    try {
      final read = await fetch(target.id);
      if (_disposed) return;
      if (read.tracks.isEmpty) {
        _set(
          SpotifyImportPhase.failed,
          text: 'Esa playlist no tiene canciones que importar.',
        );
        return;
      }
      playlist = read;
      _set(SpotifyImportPhase.preview);
    } on SpotifyLinkFailure catch (error) {
      _set(SpotifyImportPhase.failed, text: error.message);
    } on ApiFailure catch (error) {
      _set(SpotifyImportPhase.failed, text: error.message);
    } on Object {
      _set(
        SpotifyImportPhase.failed,
        text: const SpotifyLinkFailure(SpotifyLinkError.network).message,
      );
    }
  }

  void _reset() {
    playlist = null;
    done = matched = check = missing = failed = 0;
    recent.clear();
    checkList.clear();
    missingList.clear();
    createdId = null;
    created = 0;
    _cancel = false;
  }

  /// Vuelve a pedir un enlace.
  void restart() {
    if (busy) return;
    _reset();
    _set(SpotifyImportPhase.idle);
  }

  /// Busca las canciones y crea la playlist.
  Future<void> start() async {
    final read = playlist;
    if (phase != SpotifyImportPhase.preview || read == null) return;
    _cancel = false;
    _set(SpotifyImportPhase.matching);

    final results = await runMatching(
      tracks: read.tracks,
      search: search,
      cancelled: () => _cancel || _disposed,
      concurrency: concurrency,
      retryDelay: retryDelay,
      onProgress: (entry, index) {
        done++;
        switch (entry.tier) {
          case MatchTier.matched:
            matched++;
          case MatchTier.check:
            check++;
            checkList.add((
              title: entry.track.title,
              artists: entry.track.artists.join(', '),
              found: entry.song?.title ?? '',
            ));
          case MatchTier.missing:
            missing++;
            missingList.add((
              title: entry.track.title,
              artists: entry.track.artists.join(', '),
            ));
        }
        if (entry.failed) failed++;
        recent.insert(0, (
          title: entry.track.title,
          artists: entry.track.artists.join(', '),
          tier: entry.tier,
        ));
        if (recent.length > 3) recent.removeRange(3, recent.length);
        _notify();
      },
    );
    if (_disposed) return;

    // Las encontradas, sin repetidas y en el orden de la lista de Spotify.
    final ids = <String>[];
    for (final entry in results) {
      final song = entry?.song;
      if (song != null && !ids.contains(song.id)) ids.add(song.id);
    }
    final stopped = _cancel;
    if (ids.isEmpty) {
      _set(
        stopped ? SpotifyImportPhase.cancelled : SpotifyImportPhase.failed,
        text: stopped
            ? 'Importación detenida antes de encontrar canciones.'
            : (failed > 0 && failed == done
                  ? 'No se pudo buscar en YouTube Music. Comprueba tu '
                        'conexión e inténtalo otra vez.'
                  : 'No se encontró ninguna de esas canciones en YouTube '
                        'Music.'),
      );
      return;
    }

    _set(SpotifyImportPhase.saving);
    try {
      final title = read.name.trim().isEmpty
          ? 'Playlist de Spotify'
          : read.name.trim();
      createdId = await create(
        title.length > 80 ? title.substring(0, 80) : title,
        read.owner == null
            ? 'Importada de Spotify'
            : 'Importada de Spotify · ${read.owner}',
        ids,
      );
      created = ids.length;
      _set(
        stopped ? SpotifyImportPhase.cancelled : SpotifyImportPhase.done,
        text: stopped
            ? 'Importación detenida: se guardaron ${ids.length} canciones.'
            : null,
      );
    } on ApiFailure catch (error) {
      _set(
        SpotifyImportPhase.failed,
        text:
            'Se encontraron las canciones, pero no se pudo crear la '
            'playlist en tu cuenta. ${error.message}',
      );
    } on Object {
      _set(
        SpotifyImportPhase.failed,
        text:
            'Se encontraron las canciones, pero no se pudo crear la '
            'playlist en tu cuenta.',
      );
    }
  }

  /// Para la búsqueda: se crea la playlist con lo encontrado hasta ahora.
  void stop() {
    if (phase == SpotifyImportPhase.matching) _cancel = true;
  }
}
