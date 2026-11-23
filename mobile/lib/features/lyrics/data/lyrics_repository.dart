import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../search/domain/catalog_track.dart';
import '../domain/lyrics_provider.dart';
import 'lyrics_sources.dart';

/// Consulta varias fuentes a la vez y se queda con la mejor letra.
///
/// Las fuentes arrancan escalonadas (250 ms) para no pedir a todas lo que la
/// primera suele resolver. Gana la primera letra palabra a palabra; si ninguna
/// la tiene, la primera sincronizada por línea (por orden de preferencia) y, en
/// último caso, la primera en texto plano.
class LyricsRepository {
  LyricsRepository(this.sources);

  /// Por orden de preferencia.
  final List<LyricsSource> sources;

  static const stagger = Duration(milliseconds: 250);
  static const budget = Duration(seconds: 10);
  static const _maxCached = 60;

  final _cache = <String, SongLyrics>{};

  Future<SongLyrics?> fetch(
    CatalogTrack track, {
    CancelToken? cancelToken,
  }) async {
    final query = LyricsQuery.of(track);
    final cached = _cache.remove(query.key);
    if (cached != null) return _cache[query.key] = cached;

    final results = List<SongLyrics?>.filled(sources.length, null);
    final done = List<bool>.filled(sources.length, false);
    var failures = 0;
    final winner = Completer<SongLyrics?>();

    SongLyrics? pick() {
      for (final lyrics in results) {
        if (lyrics != null && lyrics.hasWordSync) return lyrics;
      }
      for (final lyrics in results) {
        if (lyrics != null && lyrics.isSynced) return lyrics;
      }
      for (final lyrics in results) {
        if (lyrics != null) return lyrics;
      }
      return null;
    }

    void evaluate() {
      if (winner.isCompleted) return;
      // Una letra palabra a palabra no se mejora: se entrega al instante.
      for (final lyrics in results) {
        if (lyrics != null && lyrics.hasWordSync) {
          winner.complete(lyrics);
          return;
        }
      }
      if (done.every((finished) => finished)) {
        final best = pick();
        // Si todas fallaron (no "no la tienen") es un error, no una ausencia.
        if (best == null && failures == sources.length) {
          winner.completeError(
            const SocketException('Ninguna fuente de letras respondió.'),
          );
        } else {
          winner.complete(best);
        }
      }
    }

    for (final (index, source) in sources.indexed) {
      unawaited(
        Future<void>(() async {
          await Future<void>.delayed(stagger * index);
          if (winner.isCompleted || (cancelToken?.isCancelled ?? false)) {
            return;
          }
          try {
            final lyrics = await source
                .fetch(query, cancelToken: cancelToken)
                .timeout(budget);
            results[index] = lyrics?.withSource(source.label);
          } on Object {
            failures++;
          } finally {
            done[index] = true;
            evaluate();
          }
        }),
      );
    }

    final best = await winner.future;
    if (best != null) {
      _cache[query.key] = best;
      if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
    }
    return best;
  }
}

final lyricsRepositoryProvider = Provider<LyricsRepository>(
  (ref) => LyricsRepository([BoiduSource(), LrclibSource()]),
);

final trackLyricsProvider = FutureProvider.autoDispose
    .family<SongLyrics?, CatalogTrack>((ref, track) {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return ref
          .watch(lyricsRepositoryProvider)
          .fetch(track, cancelToken: cancel);
    }, retry: (count, error) => null);

/// Desfase de las letras en milisegundos (Limusic: paso de 100 ms). Se guarda
/// en un archivo pequeño para que sobreviva al cierre de la app.
final lyricsOffsetProvider = NotifierProvider<LyricsOffset, int>(
  LyricsOffset.new,
);

class LyricsOffset extends Notifier<int> {
  static const limit = 30000;
  static const step = 100;

  @override
  int build() {
    unawaited(_load());
    return 0;
  }

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}lyrics_offset.txt');
    } on Object {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final value = int.tryParse((await file.readAsString()).trim());
      if (value != null && ref.mounted) state = value.clamp(-limit, limit);
    } on Object {
      // Sin archivo legible se parte de cero.
    }
  }

  void change(int delta) => set(state + delta);

  void reset() => set(0);

  void set(int value) {
    state = value.clamp(-limit, limit);
    unawaited(() async {
      try {
        await (await _file())?.writeAsString('$state');
      } on Object {
        // El desfase vale para esta sesión aunque no se pueda guardar.
      }
    }());
  }
}
