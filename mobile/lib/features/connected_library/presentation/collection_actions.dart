import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../downloads/application/download_providers.dart';
import '../../downloads/data/download_store.dart';
import '../../ytm/data/ytm_parser.dart' show YtmAlbumLibrary;
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import 'music_mode_host.dart';
import 'track_sheet.dart' show canPlayMusicTrack;

/// Si los álbumes y las playlists están en la biblioteca, por su id, mientras
/// dura la sesión: la página, su hoja y su corazón comparten lo que se sabe y
/// lo que se cambia. Para un álbum, `playlistId` es su playlist de audio
/// (`OLAK5uy_…`), con la que se guarda; para una playlist, ella misma.
final libraryState = ValueNotifier<Map<String, YtmAlbumLibrary>>(const {});

/// Lo guardado en la biblioteca, leído una vez por sesión: los álbumes de
/// `FEmusic_liked_albums` y las playlists de `FEmusic_liked_playlists`.
Future<Set<String>>? _savedAlbums;
Future<Set<String>>? _savedPlaylists;
const _savedPages = 20;

/// El id de una playlist sin el prefijo `VL` con que a veces llega.
String playlistKey(String id) => id.replaceFirst(RegExp('^VL'), '');

Future<Set<String>> _readSaved(
  MusicModeController music,
  String generation,
  MusicSurface surface,
  void Function() forget,
) async {
  final ids = <String>{};
  String? cursor;
  try {
    for (var round = 0; round < _savedPages; round++) {
      final page = await music.page(
        generation,
        surface,
        cursor: cursor,
        quiet: true,
      );
      for (final item in page.items) {
        if (surface == MusicSurface.albums && item is MusicAlbum) {
          ids.add(item.id);
        } else if (surface == MusicSurface.playlists && item is MusicPlaylist) {
          ids.add(playlistKey(item.id));
        }
      }
      cursor = page.nextCursor;
      if (cursor == null) break;
    }
  } on Object {
    // Se queda con lo que llegó; la próxima vez se vuelve a pedir.
    forget();
  }
  return ids;
}

Future<Set<String>> _loadSavedAlbums(
  MusicModeController music,
  String generation,
) => _savedAlbums ??= _readSaved(
  music,
  generation,
  MusicSurface.albums,
  () => _savedAlbums = null,
);

Future<Set<String>> _loadSavedPlaylists(
  MusicModeController music,
  String generation,
) => _savedPlaylists ??= _readSaved(
  music,
  generation,
  MusicSurface.playlists,
  () => _savedPlaylists = null,
);

/// Pregunta a YouTube Music si [albumId] está en la biblioteca (una vez por
/// sesión) y devuelve lo que se sabe; null si no se pudo saber.
///
/// La página del álbum da la playlist con que se guarda, pero su botón viene
/// siempre como «no guardado», también después de guardarlo: si está en la
/// biblioteca se sabe por la lista de álbumes guardados, como hace Limusic.
Future<YtmAlbumLibrary?> loadAlbumLibrary(
  MusicModeController music,
  String albumId,
) async {
  final known = libraryState.value[albumId];
  if (known != null) return known;
  final generation = music.connection?.generation;
  if (generation == null || music.connection?.isDirect != true) return null;
  try {
    final results = await Future.wait([
      music.ask(generation, (client) => client.ytm.albumLibrary(albumId)),
      _loadSavedAlbums(music, generation),
    ]);
    final header = results[0] as YtmAlbumLibrary;
    final saved = (results[1] as Set<String>).contains(albumId);
    final found = YtmAlbumLibrary(header.playlistId, saved || header.saved);
    libraryState.value = {...libraryState.value, albumId: found};
    return found;
  } on Object {
    return null;
  }
}

/// Si la playlist [playlistId] está guardada en la biblioteca (una vez por
/// sesión); null si no se pudo saber.
Future<YtmAlbumLibrary?> loadPlaylistLibrary(
  MusicModeController music,
  String playlistId,
) async {
  final key = playlistKey(playlistId);
  final known = libraryState.value[key];
  if (known != null) return known;
  final generation = music.connection?.generation;
  if (generation == null || music.connection?.isDirect != true) return null;
  try {
    final saved = (await _loadSavedPlaylists(music, generation)).contains(key);
    final found = YtmAlbumLibrary(key, saved);
    libraryState.value = {...libraryState.value, key: found};
    return found;
  } on Object {
    return null;
  }
}

/// Guarda o quita de la biblioteca de YouTube Music el álbum o la playlist
/// [id]. Cambia al instante y, si YouTube no lo acepta, se deshace. Devuelve
/// el aviso.
Future<String> toggleLibrary(
  MusicModeController music,
  String id, {
  required bool album,
}) async {
  final key = album ? id : playlistKey(id);
  final known = album
      ? await loadAlbumLibrary(music, key)
      : await loadPlaylistLibrary(music, key);
  final playlistId = known?.playlistId;
  final generation = music.connection?.generation;
  final what = album ? 'el álbum' : 'la playlist';
  if (known == null || playlistId == null || generation == null) {
    return 'YouTube Music no permite guardar $what.';
  }
  final saved = !known.saved;
  void set(bool value) => libraryState.value = {
    ...libraryState.value,
    key: YtmAlbumLibrary(playlistId, value),
  };
  set(saved);
  try {
    await music.ask(
      generation,
      (client) => client.ytm.saveToLibrary(playlistId, saved: saved),
    );
    // La lista guardada de la sesión también cambia.
    final ids = await (album ? _savedAlbums : _savedPlaylists);
    if (ids != null) saved ? ids.add(key) : ids.remove(key);
    final noun = album ? 'Álbum' : 'Playlist';
    return saved
        ? '$noun ${album ? 'guardado' : 'guardada'} en tu biblioteca'
        : '$noun ${album ? 'quitado' : 'quitada'} de tu biblioteca';
  } on ApiFailure catch (error) {
    set(!saved);
    return error.message;
  } on Object {
    set(!saved);
    return 'No se pudo cambiar $what en YouTube Music.';
  }
}

/// Los botones de la cabecera de un álbum o una playlist (Limusic:
/// `CollectionDownloadButton` y `HeartCheckBox`): descargar la colección
/// entera y guardarla en la biblioteca de YouTube Music. Reproducir y
/// aleatorio quedan en la hoja de tres puntos y en las propias canciones.
class CollectionActions extends ConsumerStatefulWidget {
  const CollectionActions({
    super.key,
    required this.id,
    required this.album,
    required this.tracks,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.loadAll,
    this.heart = true,
  });

  /// Nombre, subtítulo y portada de la colección: con ellos se ve en
  /// Descargas. El nombre de un álbum se guarda también con cada canción,
  /// para poder ordenar las descargas por álbum.
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;

  String? get albumName => album ? title : null;

  /// El álbum (`MPREb_…`) o la playlist.
  final String id;
  final bool album;

  /// Las canciones ya cargadas: con ellas se pinta el estado de la descarga.
  final List<MusicTrack> tracks;

  /// Carga las que faltan (una playlist larga llega por páginas) antes de
  /// descargar; sin él se descargan [tracks].
  final Future<List<MusicTrack>> Function()? loadAll;

  /// Una playlist propia ya es de la biblioteca: no lleva corazón.
  final bool heart;

  @override
  ConsumerState<CollectionActions> createState() => _CollectionActionsState();
}

class _CollectionActionsState extends ConsumerState<CollectionActions> {
  final _store = DownloadStore.instance;
  var _started = false;
  var _loading = false;

  String get _key => widget.album ? widget.id : playlistKey(widget.id);
  String get _what => widget.album ? 'el álbum' : 'la playlist';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final music = MusicModeScope.of(context);
    if (music == null) return;
    _fillAlbum();
    unawaited(
      widget.album
          ? loadAlbumLibrary(music, widget.id)
          : loadPlaylistLibrary(music, widget.id),
    );
  }

  @override
  void didUpdateWidget(CollectionActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracks.length != widget.tracks.length ||
        oldWidget.title != widget.title) {
      _fillAlbum();
    }
  }

  /// Las ya descargadas de este álbum sin su nombre lo reciben ahora; y un
  /// álbum que ya estaba entero en el teléfono, bajado canción a canción
  /// antes de que se guardaran las colecciones, pasa a ser un álbum
  /// descargado.
  void _fillAlbum() {
    final name = widget.albumName;
    if (!widget.album || name == null || name.isEmpty) return;
    if (widget.tracks.isEmpty) return;
    final ids = [for (final track in widget.tracks) track.id];
    unawaited(() async {
      await _store.load();
      await _store.fillAlbum(ids, widget.id, name);
      if (_store.collection(_key) == null && ids.every(_store.isDownloaded)) {
        await _store.keepCollection(_collection(ids));
      }
    }());
  }

  DownloadedCollection _collection(List<String> ids) => DownloadedCollection(
    id: _key,
    album: widget.album,
    title: widget.title,
    subtitle: widget.subtitle,
    thumbnailUrl: widget.thumbnailUrl,
    trackIds: ids,
    savedAt: DateTime.now().millisecondsSinceEpoch,
  );

  /// Pregunta qué hacer con una colección ya descargada: quitarla o, si le
  /// faltan canciones, bajar las que faltan. null: nada.
  Future<String?> _askKept(int missing) => showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) => AlertDialog(
      title: Text(widget.album ? 'Álbum descargado' : 'Playlist descargada'),
      content: Text(
        missing == 0
            ? '¿Quitar la descarga? Las canciones que no guarde otro álbum o '
                  'playlist dejarán de estar en el teléfono.'
            : 'Faltan $missing ${missing == 1 ? 'canción' : 'canciones'} '
                  'por bajar.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('remove'),
          child: const Text('Quitar descarga'),
        ),
        if (missing > 0)
          FilledButton(
            onPressed: () => Navigator.of(context).pop('missing'),
            child: const Text('Bajar las que faltan'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
      ],
    ),
  );

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Las canciones de [from] que se pueden descargar.
  List<MusicTrack> _downloadable(
    MusicModeController music,
    List<MusicTrack> from,
  ) => [
    for (final track in from)
      if (canPlayMusicTrack(music, track) &&
          music.deviceAudio(track.id) == null)
        track,
  ];

  Future<void> _download(MusicModeController music) async {
    final generation = music.connection?.generation;
    if (generation == null) return;
    var all = widget.tracks;
    final loadAll = widget.loadAll;
    if (loadAll != null) {
      setState(() => _loading = true);
      try {
        all = await loadAll();
      } on Object {
        // Con lo ya cargado.
      }
      if (!mounted) return;
      setState(() => _loading = false);
    }
    final tracks = _downloadable(music, all);
    if (tracks.isEmpty) {
      _say('No hay canciones que descargar.');
      return;
    }
    final missing = [
      for (final track in tracks)
        if (!_store.isDownloaded(track.id) && !_store.isBusy(track.id)) track,
    ];
    // Ya descargada (como en Limusic, «descargada» es haberla pedido): el
    // botón ofrece quitarla o bajar lo que falte.
    if (_store.collection(_key) != null) {
      if (missing.isEmpty && tracks.any((track) => _store.isBusy(track.id))) {
        _say('Se está descargando $_what');
        return;
      }
      if (!mounted) return;
      final choice = await _askKept(missing.length);
      if (choice == 'remove') {
        await _store.releaseCollection(_key);
        _say(
          widget.album
              ? 'Descarga del álbum quitada'
              : 'Descarga de la playlist quitada',
        );
        return;
      }
      if (choice != 'missing') return;
    }
    // La colección se guarda con todas sus canciones y su portada; las
    // canciones bajan después, una a una.
    await _store.keepCollection(
      _collection([for (final track in tracks) track.id]),
    );
    if (missing.isEmpty) {
      _say(
        widget.album
            ? 'Álbum guardado en Descargas'
            : 'Playlist guardada en Descargas',
      );
      return;
    }
    final resolver = ref.read(downloadResolverProvider);
    String? last;
    var queued = 0;
    for (final track in missing) {
      final playable = music.playbackTrack(generation, track);
      final name = widget.albumName;
      last = _store.enqueue(
        widget.album && name != null && name.isNotEmpty
            ? playable.withAlbum(widget.id, name)
            : playable,
        resolver,
      );
      if (_store.isBusy(track.id)) queued++;
    }
    _say(
      queued == 0
          ? (last ?? 'No se pudo descargar $_what.')
          : queued == 1
          ? 'Descargando 1 canción'
          : 'Descargando $queued canciones',
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = MusicModeScope.of(context);
    if (music == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final direct = music.connection?.isDirect == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final tracks = _downloadable(music, widget.tracks);
            // Descargada: la colección está guardada (Limusic:
            // `STATE_DOWNLOADED`); el avance es cuántas canciones llegaron.
            final done = _store.collection(_key) != null;
            final busy = _loading || tracks.any((t) => _store.isBusy(t.id));
            // Avance: canciones ya en el teléfono entre las cargadas.
            final progress = tracks.isEmpty
                ? 0.0
                : tracks.where((t) => _store.isDownloaded(t.id)).length /
                      tracks.length;
            return IconButton(
              tooltip: done
                  ? 'Descargado'
                  : busy
                  ? 'Descargando'
                  : widget.album
                  ? 'Descargar álbum'
                  : 'Descargar playlist',
              iconSize: 28,
              style: IconButton.styleFrom(fixedSize: const Size.square(52)),
              color: done ? colors.primary : colors.onSurface,
              onPressed: tracks.isEmpty || _loading
                  ? null
                  : () => unawaited(_download(music)),
              icon: busy
                  ? SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        value: _loading || progress == 0 ? null : progress,
                      ),
                    )
                  : Icon(
                      done
                          ? Icons.download_for_offline_rounded
                          : Icons.download_for_offline_outlined,
                    ),
            );
          },
        ),
        if (direct && widget.heart) ...[
          const SizedBox(width: 4),
          ValueListenableBuilder(
            valueListenable: libraryState,
            builder: (context, state, _) {
              final known = state[_key];
              final saved = known?.saved ?? false;
              return IconButton.filled(
                tooltip: saved
                    ? 'Quitar de tu biblioteca'
                    : 'Guardar en tu biblioteca',
                iconSize: 28,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(52),
                  backgroundColor: saved
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  foregroundColor: saved ? colors.onPrimary : colors.onSurface,
                ),
                // Apagado hasta saber si ya está guardado.
                onPressed: known == null || known.playlistId == null
                    ? null
                    : () async {
                        final message = await toggleLibrary(
                          music,
                          widget.id,
                          album: widget.album,
                        );
                        _say(message);
                      },
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
