import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../downloads/application/download_providers.dart';
import '../../downloads/data/download_store.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../../search/presentation/item_sheet.dart';
import '../../ytm/data/liked_tracks.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import '../domain/shortcut.dart';
import 'collection_actions.dart';
import 'catalog_pages.dart';
import 'music_mode_host.dart';

/// Si [track] se puede reproducir con la conexión musical activa.
bool canPlayMusicTrack(MusicModeController music, MusicTrack track) {
  final connection = music.connection;
  if (connection == null) return false;
  return connection.isPreview
      ? connection.capabilities.contains('playback') && track.canPreview
      : (music.deviceAudio(track.id) != null ||
            (connection.capabilities.contains('playback') &&
                track.canPlayInMysic));
}

/// Añade [tracks] a la cola (a continuación o al final) y devuelve el aviso
/// para el usuario.
String addMusicTracksToQueue(
  WidgetRef ref,
  MusicModeController music,
  Iterable<MusicTrack> tracks, {
  required bool next,
}) {
  final generation = music.connection?.generation;
  if (generation == null || !music.isCurrent(generation)) {
    return 'Cambió la conexión.';
  }
  final added = ref
      .read(trackPlaybackControllerProvider)
      .queueConnected(
        tracks
            .where((track) => canPlayMusicTrack(music, track))
            .map((track) => music.playbackTrack(generation, track)),
        next: next,
        listenForTrack: () => music.listenForTrack(generation),
      );
  if (!added) return 'La cola no cambió';
  return next ? 'Se reproducirá a continuación' : 'Añadido al final de la cola';
}

const _shareChannel = MethodChannel('com.mysic/share');

/// Abre el menú de compartir del sistema con [link]. Donde no lo hay (o si
/// falla) lo copia al portapapeles y lo dice.
Future<void> shareMusicLink(
  ScaffoldMessengerState messenger,
  String title,
  Uri link,
) async {
  try {
    await _shareChannel.invokeMethod<void>('text', {
      'text': link.toString(),
      'title': title,
    });
  } on Object {
    await Clipboard.setData(ClipboardData(text: link.toString()));
    messenger.showSnackBar(const SnackBar(content: Text('Enlace copiado')));
  }
}

/// Las canciones a las que se dio No me gusta en esta sesión: YouTube Music
/// no las devuelve en ninguna lista, así que el pulgar relleno vive aquí.
final _disliked = ValueNotifier<Set<String>>(const {});

/// Lo que una hoja necesita para actuar después de cerrarse.
class _Menu {
  _Menu(this.context, this.ref, this.music, this.generation)
    : messenger = ScaffoldMessenger.of(context),
      router = GoRouter.maybeOf(context);

  final BuildContext context;
  final WidgetRef ref;
  final MusicModeController music;
  final String generation;
  final ScaffoldMessengerState messenger;

  /// Null sin enrutador (pruebas): se reproduce sin abrir el reproductor.
  final GoRouter? router;

  static _Menu? of(BuildContext context, WidgetRef ref) {
    final music = MusicModeScope.of(context);
    final generation = music?.connection?.generation;
    if (music == null || generation == null || !music.isCurrent(generation)) {
      return null;
    }
    return _Menu(context, ref, music, generation);
  }

  void say(String? message) {
    if (message != null && message.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Ejecuta [action] y avisa de su resultado o de su fallo.
  Future<void> run(Future<String?> Function() action) async {
    if (!music.isCurrent(generation)) return;
    try {
      say(await action());
    } on ApiFailure catch (error) {
      say(error.message);
    } on Object {
      say('No se pudo completar la acción.');
    }
  }

  TrackPlaybackController get player =>
      ref.read(trackPlaybackControllerProvider);

  /// Reproduce [tracks] (barajadas con [shuffled]) y abre el reproductor.
  String? play(List<MusicTrack> tracks, {bool shuffled = false}) {
    final playable = tracks
        .where((track) => canPlayMusicTrack(music, track))
        .take(TrackPlaybackController.maxQueue)
        .toList();
    if (playable.isEmpty) return 'No hay canciones que reproducir.';
    if (shuffled) playable.shuffle();
    unawaited(
      player.playQueue([
        for (final track in playable) music.playbackTrack(generation, track),
      ], listenForTrack: () => music.listenForTrack(generation)),
    );
    // Desde el propio reproductor no se abre otro encima.
    final router = this.router;
    if (router != null &&
        router.routerDelegate.currentConfiguration.uri.path != '/player') {
      router.push('/player');
    }
    return null;
  }

  /// Las canciones de un álbum o de una playlist (hasta cinco páginas).
  Future<List<MusicTrack>> tracksOf(MusicItem item) async {
    if (item is MusicAlbum) {
      if (music.hasPublicCatalog) {
        try {
          return (await music.albumDetail(item.id)).tracks;
        } on Object {
          // Se prueba con la página de la cuenta.
        }
      }
      final page = await music.page(
        generation,
        MusicSurface.album,
        playlistId: item.id,
        quiet: true,
      );
      return page.items.whereType<MusicTrack>().toList();
    }
    final tracks = <MusicTrack>[];
    String? cursor;
    for (var round = 0; round < 5; round++) {
      final page = await music.page(
        generation,
        MusicSurface.playlist,
        playlistId: item.id,
        cursor: cursor,
        quiet: true,
      );
      tracks.addAll(page.items.whereType<MusicTrack>());
      cursor = page.nextCursor;
      if (cursor == null) break;
    }
    return tracks;
  }
}

/// El atajo que corresponde a una playlist, a un álbum o a una canción.
Shortcut shortcutOf(MusicItem item) => switch (item) {
  MusicTrack() => Shortcut(
    ShortcutKind.track,
    item.id,
    item.title,
    subtitle: item.artist,
    thumbnail: item.thumbnailUrl,
  ),
  MusicAlbum() => Shortcut(
    ShortcutKind.album,
    item.id,
    item.title,
    subtitle: item.artist ?? item.detail ?? 'Álbum',
    thumbnail: item.thumbnailUrl,
  ),
  MusicPlaylist() => Shortcut(
    ShortcutKind.playlist,
    item.id,
    item.title,
    subtitle: 'Playlist',
    thumbnail: item.thumbnailUrl,
  ),
  MusicArtist() => throw ArgumentError('Un artista no es un atajo.'),
};

/// La canción de un atajo, con lo que el atajo sabe de ella.
MusicTrack trackOfShortcut(Shortcut shortcut) => MusicTrack(
  shortcut.id,
  shortcut.title,
  shortcut.subtitle ?? '',
  0,
  false,
  null,
  nativePlayback: true,
  thumbnailUrl: shortcut.thumbnail,
);

/// «Guardar en tu biblioteca» o «Quitar de tu biblioteca» de un álbum o una
/// playlist; se ve apagada hasta saber si ya está guardado.
SheetRow _libraryRow(_Menu menu, String id, {required bool album}) {
  final known = libraryState.value[album ? id : playlistKey(id)];
  final saved = known?.saved ?? false;
  return SheetRow(
    icon: saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
    label: saved ? 'Quitar de tu biblioteca' : 'Guardar en tu biblioteca',
    onTap: known?.playlistId == null
        ? null
        : () => unawaited(
            menu.run(() => toggleLibrary(menu.music, id, album: album)),
          ),
  );
}

/// La fila «Añadir a atajos» o «Quitar de atajos» (Limusic `ShortcutRow`),
/// la que corresponda. Con la cuadrícula llena no se esconde: se ve apagada
/// y dice por qué, para que no parezca que la opción no existe.
SheetRow _shortcutRow(MusicModeController music, Shortcut shortcut) {
  final pinned = music.isShortcut(shortcut);
  final full = !pinned && music.shortcutsFull;
  return SheetRow(
    icon: Icons.grid_view_rounded,
    label: pinned ? 'Quitar de atajos' : 'Añadir a atajos',
    subtitle: full ? 'Ya hay ${Shortcut.max} atajos: quita uno primero' : null,
    onTap: full ? null : () => music.toggleShortcut(shortcut),
  );
}

/// La hoja de opciones de una canción (Limusic `NowPlayingBottomSheet`):
/// cabecera con el corazón, cuatro acciones rápidas y la lista. Se abre al
/// mantener pulsada la canción en cualquier lista, collage o estante.
///
/// Con [playlistId] (una playlist propia) añade «Quitar de la playlist»;
/// [onRemoved] avisa de que se quitó.
Future<void> showTrackSheet(
  BuildContext context,
  WidgetRef ref,
  MusicTrack track, {
  String? playlistId,
  VoidCallback? onRemoved,

  /// Las filas propias del reproductor (temporizador, velocidad, información),
  /// cuando la hoja es la de la canción que suena. [playerRefresh] las
  /// mantiene al día mientras la hoja está abierta.
  List<SheetRow> Function()? playerRows,
  Listenable? playerRefresh,
}) async {
  final menu = _Menu.of(context, ref);
  if (menu == null) return;
  final music = menu.music, generation = menu.generation;
  final connection = music.connection!;
  final store = DownloadStore.instance;
  final canPlay = canPlayMusicTrack(music, track);
  // El corazón solo existe con la sesión de YouTube Music; sin ella (o sin su
  // lista de Me gusta) la cabecera va sin él.
  LikedTracks? likes;
  if (connection.isDirect) {
    try {
      likes = ref.read(likedTracksProvider);
    } on Object {
      likes = null;
    }
  }
  final link = Uri.https('music.youtube.com', '/watch', {'v': track.id});

  await showItemSheet(
    context,
    header: SheetHeader(
      title: track.title,
      subtitle: [
        track.artist,
        if (track.albumName != null) track.albumName!,
      ].join(' • '),
      url: track.thumbnailUrl,
      liked: likes == null ? null : () => likes!.isLiked(track.id),
      onLike: likes == null ? null : () => unawaited(likes!.toggle(track.id)),
    ),
    // La hoja refleja la descarga, el corazón y el pulgar mientras está
    // abierta.
    refresh: Listenable.merge([
      store,
      ?likes,
      _disliked,
      music.shortcuts,
      ?playerRefresh,
    ]),
    tiles: () {
      final file = music.deviceAudio(track.id) != null;
      final busy = store.isBusy(track.id);
      final done = store.isDownloaded(track.id);
      return [
        if (canPlay)
          SheetTile(
            icon: Icons.play_circle_outline,
            label: 'A continuación',
            onTap: () => menu.say(
              addMusicTracksToQueue(ref, music, [track], next: true),
            ),
          ),
        if (canPlay)
          SheetTile(
            icon: Icons.queue_music,
            label: 'Añadir a la cola',
            onTap: () => menu.say(
              addMusicTracksToQueue(ref, music, [track], next: false),
            ),
          ),
        if (connection.isDirect)
          SheetTile(
            icon: Icons.playlist_add_rounded,
            label: 'Guardar en playlist',
            onTap: () => unawaited(showSaveToPlaylist(context, ref, [track])),
          ),
        if (canPlay && !file)
          SheetTile(
            icon: done
                ? Icons.download_for_offline
                : Icons.download_for_offline_outlined,
            label: done
                ? 'Descargada'
                : busy
                ? 'Descargando'
                : 'Descargar',
            active: done,
            progress: busy ? (store.progressOf(track.id) ?? -1) : null,
            closes: false,
            onTap: done || busy
                ? null
                : () => menu.say(
                    store.enqueue(
                      music.playbackTrack(generation, track),
                      ref.read(downloadResolverProvider),
                    ),
                  ),
          ),
      ];
    },
    rows: () {
      final file = music.deviceAudio(track.id) != null;
      final disliked = _disliked.value.contains(track.id);
      return [
        if (canPlay)
          SheetRow(
            icon: Icons.sensors_rounded,
            label: 'Iniciar radio',
            // La canción y, tras ella, su radio.
            onTap: () => menu.say(menu.play([track])),
          ),
        if (music.hasPublicCatalog ||
            (track.artistId != null &&
                connection.capabilities.contains('artist')))
          SheetRow(
            icon: Icons.people_alt,
            label: music.hasPublicCatalog
                ? 'Ir al artista'
                : 'Más de este canal',
            subtitle: track.artist,
            onTap: () => unawaited(
              openTrackLink(
                context,
                album: false,
                videoId: track.id,
                title: track.title,
                artist: track.artist,
                artistId: track.artistId,
                albumId: track.albumId,
              ),
            ),
          ),
        if (music.hasPublicCatalog)
          SheetRow(
            icon: Icons.album,
            label: 'Ir al álbum',
            subtitle: track.albumName,
            onTap: () => unawaited(
              openTrackLink(
                context,
                album: true,
                videoId: track.id,
                title: track.title,
                artist: track.artist,
                artistId: track.artistId,
                albumId: track.albumId,
              ),
            ),
          ),
        if (connection.isDirect)
          SheetRow(
            icon: disliked
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_outlined,
            label: disliked ? 'Quitar No me gusta' : 'No me gusta',
            // Sigue abierta: el pulgar relleno es la respuesta al toque.
            closes: false,
            onTap: () => unawaited(
              menu.run(() async {
                await music.ask(
                  generation,
                  (client) => client.ytm.dislike(track.id, disliked: !disliked),
                );
                _disliked.value = disliked
                    ? ({..._disliked.value}..remove(track.id))
                    : {..._disliked.value, track.id};
                if (!disliked) likes?.forget(track.id);
                return null;
              }),
            ),
          ),
        SheetRow(
          icon: Icons.share_rounded,
          label: 'Compartir',
          onTap: () =>
              unawaited(shareMusicLink(menu.messenger, track.title, link)),
        ),
        // Una canción también se puede fijar en Inicio.
        if (canPlay) _shortcutRow(music, shortcutOf(track)),
        ...?playerRows?.call(),
        if (connection.isDirect && music.device != null)
          SheetRow(
            icon: Icons.audio_file_outlined,
            label: file
                ? 'Cambiar archivo de audio'
                : 'Vincular archivo de audio',
            onTap: music.pickingAudio
                ? null
                : () => unawaited(
                    menu.run(
                      () async => await music.attachAudio(generation, track.id)
                          ? 'Archivo listo para reproducir en Mysic'
                          : null,
                    ),
                  ),
          ),
        if (file)
          SheetRow(
            icon: Icons.delete_outline,
            label: 'Retirar archivo de Mysic',
            destructive: true,
            onTap: music.pickingAudio
                ? null
                : () => unawaited(
                    menu.run(() async {
                      await music.removeAudio(generation, track.id);
                      return 'Archivo retirado de Mysic';
                    }),
                  ),
          ),
        if (store.isDownloaded(track.id))
          SheetRow(
            icon: Icons.delete_outline,
            label: 'Quitar descarga',
            destructive: true,
            onTap: () => unawaited(
              menu.run(() async {
                await store.remove(track.id);
                return 'Descarga quitada';
              }),
            ),
          ),
        // Quitar va al final, en el color de error, como en Limusic.
        if (playlistId != null && track.entryId != null)
          SheetRow(
            icon: Icons.delete_outline,
            label: 'Quitar de la playlist',
            destructive: true,
            onTap: () => unawaited(
              menu.run(() async {
                await music.ask(
                  generation,
                  (client) => client.ytm.removeFromPlaylist(
                    playlistId,
                    track.id,
                    track.entryId!,
                  ),
                );
                onRemoved?.call();
                return 'Quitada de la playlist';
              }),
            ),
          ),
      ];
    },
  );
}

/// La hoja que corresponde a [item] al mantenerlo pulsado: la de canción, la
/// de playlist o álbum, o la de artista. [onChanged] avisa de que la
/// biblioteca cambió (se editó o eliminó una playlist, se siguió a un
/// artista) para que quien la muestra la refresque.
Future<void> showItemMenu(
  BuildContext context,
  WidgetRef ref,
  MusicItem item, {
  String? playlistId,
  VoidCallback? onChanged,
}) => switch (item) {
  MusicTrack() => showTrackSheet(
    context,
    ref,
    item,
    playlistId: playlistId,
    onRemoved: onChanged,
  ),
  MusicArtist() => _showArtistMenu(context, ref, item, onChanged),
  MusicAlbum() ||
  MusicPlaylist() => _showCollectionMenu(context, ref, item, onChanged),
};

/// La hoja de un atajo de Inicio (Limusic `ItemMenu`): la de su playlist o
/// su álbum; una colección de la Biblioteca solo ofrece quitarla o añadirla.
Future<void> showShortcutMenu(
  BuildContext context,
  WidgetRef ref,
  Shortcut shortcut, {
  VoidCallback? onChanged,
}) async {
  switch (shortcut.kind) {
    case ShortcutKind.playlist:
      return showItemMenu(
        context,
        ref,
        MusicPlaylist(
          shortcut.id,
          shortcut.title,
          false,
          thumbnailUrl: shortcut.thumbnail,
        ),
        onChanged: onChanged,
      );
    case ShortcutKind.album:
      return showItemMenu(
        context,
        ref,
        MusicAlbum(
          shortcut.id,
          shortcut.title,
          thumbnailUrl: shortcut.thumbnail,
          artist: shortcut.subtitle,
        ),
        onChanged: onChanged,
      );
    case ShortcutKind.track:
      return showTrackSheet(context, ref, trackOfShortcut(shortcut));
    case ShortcutKind.collection:
      final music = MusicModeScope.of(context);
      if (music == null) return;
      return showItemSheet(
        context,
        header: SheetHeader(title: shortcut.title, subtitle: shortcut.subtitle),
        refresh: music.shortcuts,
        rows: () => [_shortcutRow(music, shortcut)],
      );
  }
}

/// La hoja de una playlist o de un álbum (Limusic `PlaylistBottomSheet`):
/// Reproducir con Aleatorio, A continuación, Añadir a la cola, Iniciar radio,
/// Guardar en playlist, Compartir, el atajo y, en una playlist propia, Editar
/// y Eliminar. Se abre al instante; lo que necesita la playlist la espera.
Future<void> _showCollectionMenu(
  BuildContext context,
  WidgetRef ref,
  MusicItem item,
  VoidCallback? onChanged,
) async {
  final menu = _Menu.of(context, ref);
  if (menu == null) return;
  final music = menu.music, generation = menu.generation;
  final isAlbum = item is MusicAlbum;
  final shortcut = shortcutOf(item);
  final link = isAlbum
      ? Uri.https('music.youtube.com', '/browse/${item.id}')
      : Uri.https('music.youtube.com', '/playlist', {'list': item.id});
  // Solo una playlist de la cuenta se edita o elimina: se sabe al cargarla.
  final own = ValueNotifier(false);
  var open = true;
  // Un álbum: si está guardado en la biblioteca de YouTube Music.
  if (isAlbum && music.connection!.isDirect) {
    unawaited(loadAlbumLibrary(music, item.id));
  }
  // Sin saber aún si es propia: así la fila de biblioteca no aparece y se va.
  final ownKnown = ValueNotifier(false);
  if (item is MusicPlaylist && music.connection!.isDirect) {
    unawaited(loadPlaylistLibrary(music, item.id));
    unawaited(() async {
      try {
        final page = await music.page(
          generation,
          MusicSurface.playlist,
          playlistId: item.id,
          quiet: true,
        );
        if (open) own.value = page.editable;
      } on Object {
        // Sin saberlo no se ofrecen.
      }
      if (open) ownKnown.value = true;
    }());
  }

  /// Carga las canciones y hace [then] con ellas.
  void withTracks(String? Function(List<MusicTrack> tracks) then) =>
      unawaited(menu.run(() async => then(await menu.tracksOf(item))));

  await showItemSheet(
    context,
    header: SheetHeader(
      title: item.title,
      subtitle: shortcut.subtitle,
      url: shortcut.thumbnail,
    ),
    refresh: Listenable.merge([own, ownKnown, music.shortcuts, libraryState]),
    onPlay: () => withTracks(menu.play),
    onShuffle: () => withTracks((tracks) => menu.play(tracks, shuffled: true)),
    rows: () => [
      SheetRow(
        icon: Icons.play_circle_outline,
        label: 'A continuación',
        onTap: () => withTracks(
          (tracks) => addMusicTracksToQueue(ref, music, tracks, next: true),
        ),
      ),
      SheetRow(
        icon: Icons.queue_music,
        label: 'Añadir a la cola',
        onTap: () => withTracks(
          (tracks) => addMusicTracksToQueue(ref, music, tracks, next: false),
        ),
      ),
      SheetRow(
        icon: Icons.sensors_rounded,
        label: 'Iniciar radio',
        onTap: () => unawaited(
          menu.run(() async {
            if (isAlbum) {
              // La radio de un álbum arranca de su primera canción.
              final tracks = await menu.tracksOf(item);
              return menu.play(tracks.take(1).toList());
            }
            final radio = await music.ask(
              generation,
              (client) => client.ytm.playlistRadio(item.id),
            );
            return menu.play([
              for (final track in radio.tracks) MusicTrack.fromJson(track),
            ]);
          }),
        ),
      ),
      if (music.connection!.isDirect)
        SheetRow(
          icon: Icons.playlist_add_rounded,
          label: 'Guardar en playlist',
          onTap: () => unawaited(
            menu.run(() async {
              final tracks = await menu.tracksOf(item);
              if (tracks.isEmpty) return 'No hay canciones que guardar.';
              if (context.mounted) {
                unawaited(showSaveToPlaylist(context, ref, tracks));
              }
              return null;
            }),
          ),
        ),
      SheetRow(
        icon: Icons.share_rounded,
        label: 'Compartir',
        onTap: () =>
            unawaited(shareMusicLink(menu.messenger, item.title, link)),
      ),
      _shortcutRow(music, shortcut),
      if (isAlbum && music.connection!.isDirect)
        _libraryRow(menu, item.id, album: true),
      // Una playlist propia ya es de la biblioteca.
      if (item is MusicPlaylist &&
          music.connection!.isDirect &&
          ownKnown.value &&
          !own.value)
        _libraryRow(menu, item.id, album: false),
      if (own.value) ...[
        SheetRow(
          icon: Icons.edit_rounded,
          label: 'Editar playlist',
          onTap: () => unawaited(() async {
            final edit = await _askPlaylistEdit(context, item.title);
            if (edit == null) return;
            await menu.run(() async {
              await music.ask(
                generation,
                (client) => client.ytm.editPlaylist(
                  item.id,
                  title: edit.title == item.title ? null : edit.title,
                  description: edit.description,
                  privacy: edit.privacy,
                ),
              );
              // El atajo conserva el nombre nuevo.
              if (music.isShortcut(shortcut) && edit.title != item.title) {
                music
                  ..toggleShortcut(shortcut)
                  ..toggleShortcut(
                    Shortcut(
                      shortcut.kind,
                      shortcut.id,
                      edit.title,
                      subtitle: shortcut.subtitle,
                      thumbnail: shortcut.thumbnail,
                    ),
                  );
              }
              onChanged?.call();
              return 'Playlist actualizada';
            });
          }()),
        ),
        SheetRow(
          icon: Icons.delete_outline,
          label: 'Eliminar playlist',
          destructive: true,
          onTap: () => unawaited(() async {
            if (!await _confirmDelete(context, item.title)) return;
            await menu.run(() async {
              await music.ask(
                generation,
                (client) => client.ytm.deletePlaylist(item.id),
              );
              if (music.isShortcut(shortcut)) music.toggleShortcut(shortcut);
              onChanged?.call();
              return 'Playlist eliminada';
            });
          }()),
        ),
      ],
    ],
  );
  open = false;
}

/// La hoja de un artista (Limusic `ArtistBottomSheet`): Iniciar radio, Seguir
/// o Dejar de seguir y Compartir.
Future<void> _showArtistMenu(
  BuildContext context,
  WidgetRef ref,
  MusicArtist artist,
  VoidCallback? onChanged,
) async {
  final menu = _Menu.of(context, ref);
  if (menu == null) return;
  final music = menu.music, generation = menu.generation;
  final direct = music.connection!.isDirect;
  // Se sabe si se le sigue por la lista de la Biblioteca; si aún no se ha
  // visto en esta sesión, se pide.
  final followed = ValueNotifier<bool?>(
    music
        .recalledPage(generation, MusicSurface.artists)
        ?.items
        .any((item) => item.id == artist.id),
  );
  var open = true;
  if (followed.value == null && direct) {
    unawaited(() async {
      bool found;
      try {
        final page = await music.page(
          generation,
          MusicSurface.artists,
          quiet: true,
        );
        found = page.items.any((item) => item.id == artist.id);
      } on Object {
        found = false;
      }
      if (open) followed.value = found;
    }());
  }
  await showItemSheet(
    context,
    header: SheetHeader(
      title: artist.title,
      subtitle: artist.detail ?? 'Artista',
      url: artist.thumbnailUrl,
    ),
    refresh: followed,
    rows: () => [
      SheetRow(
        icon: Icons.sensors_rounded,
        label: 'Iniciar radio',
        onTap: !music.hasPublicCatalog
            ? null
            : () => unawaited(
                menu.run(() async {
                  // Sus canciones destacadas y, tras ellas, la radio.
                  final profile = await music.artistProfile(artist.id);
                  return menu.play(profile.topSongs);
                }),
              ),
      ),
      if (direct)
        SheetRow(
          icon: followed.value == true
              ? Icons.check_rounded
              : Icons.person_add_alt_1_rounded,
          label: followed.value == true ? 'Dejar de seguir' : 'Seguir',
          // Apagada hasta saber si ya se le sigue.
          onTap: followed.value == null
              ? null
              : () {
                  final follow = followed.value != true;
                  unawaited(
                    menu.run(() async {
                      await music.ask(
                        generation,
                        (client) =>
                            client.ytm.follow(artist.id, followed: follow),
                      );
                      onChanged?.call();
                      return follow
                          ? 'Ahora sigues a ${artist.title}'
                          : 'Dejaste de seguir a ${artist.title}';
                    }),
                  );
                },
        ),
      SheetRow(
        icon: Icons.share_rounded,
        label: 'Compartir',
        onTap: () => unawaited(
          shareMusicLink(
            menu.messenger,
            artist.title,
            Uri.https('music.youtube.com', '/channel/${artist.id}'),
          ),
        ),
      ),
    ],
  );
  open = false;
}

typedef _PlaylistEdit = ({String title, String? description, String? privacy});

/// Pide el nombre, la descripción y la privacidad nuevos de una playlist. La
/// descripción y la privacidad que no se tocan no se envían.
Future<_PlaylistEdit?> _askPlaylistEdit(BuildContext context, String title) {
  final name = TextEditingController(text: title);
  final description = TextEditingController();
  String? privacy;
  return showDialog<_PlaylistEdit>(
    context: context,
    useRootNavigator: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Editar playlist'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLength: 1000,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción nueva (opcional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: privacy,
                decoration: const InputDecoration(labelText: 'Privacidad'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Sin cambios')),
                  DropdownMenuItem(value: 'PRIVATE', child: Text('Privada')),
                  DropdownMenuItem(
                    value: 'UNLISTED',
                    child: Text('No listada'),
                  ),
                  DropdownMenuItem(value: 'PUBLIC', child: Text('Pública')),
                ],
                onChanged: (value) => setState(() => privacy = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = name.text.trim();
              if (text.isEmpty) return;
              Navigator.of(context).pop((
                title: text,
                description: description.text.trim().isEmpty
                    ? null
                    : description.text.trim(),
                privacy: privacy,
              ));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text(
          '«$title» se eliminará de tu cuenta de YouTube Music. No se puede '
          'deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ) ??
    false;

/// «Guardar en playlist» (Limusic `AddToPlaylistModalBottomSheet`): las
/// playlists de la cuenta y, lo primero, crear una nueva con [tracks] dentro.
Future<void> showSaveToPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<MusicTrack> tracks,
) async {
  final menu = _Menu.of(context, ref);
  if (menu == null || tracks.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .5),
    elevation: 0,
    builder: (context) => _PlaylistPicker(menu: menu, tracks: tracks),
  );
}

class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker({required this.menu, required this.tracks});

  final _Menu menu;
  final List<MusicTrack> tracks;

  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  List<MusicPlaylist>? _playlists;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final menu = widget.menu;
    // Lo visto en la sesión se pinta ya; la red lo confirma.
    _playlists = menu.music
        .recalledPage(menu.generation, MusicSurface.playlists)
        ?.items
        .whereType<MusicPlaylist>()
        .toList();
    unawaited(_load());
  }

  Future<void> _load() async {
    final menu = widget.menu;
    try {
      final page = await menu.music.page(
        menu.generation,
        MusicSurface.playlists,
        quiet: true,
      );
      if (mounted) {
        setState(
          () => _playlists = page.items.whereType<MusicPlaylist>().toList(),
        );
      }
    } on Object {
      if (mounted && _playlists == null) setState(() => _failed = true);
    }
  }

  List<String> get _ids => [for (final track in widget.tracks) track.id];

  String get _count => widget.tracks.length == 1
      ? '«${widget.tracks.single.title}»'
      : '${widget.tracks.length} canciones';

  void _saveTo(MusicPlaylist playlist) {
    final menu = widget.menu;
    Navigator.of(context).pop();
    unawaited(
      menu.run(() async {
        await menu.music.ask(
          menu.generation,
          (client) => client.ytm.addToPlaylist(playlist.id, _ids),
        );
        return 'Guardado en «${playlist.title}»';
      }),
    );
  }

  Future<void> _createNew() async {
    final menu = widget.menu;
    final name = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Nueva playlist'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 150,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(name.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    Navigator.of(context).pop();
    unawaited(
      menu.run(() async {
        await menu.music.ask(
          menu.generation,
          (client) => client.ytm.createPlaylist(title, videoIds: _ids),
        );
        return 'Playlist «$title» creada con $_count';
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final playlists = _playlists;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Una biblioteca larga se desplaza dentro de la hoja.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guardar en playlist',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    _count,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
                ),
                children: [
                  _PickRow(
                    title: 'Nueva playlist',
                    leading: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(Icons.add_rounded, color: colors.primary),
                      ),
                    ),
                    onTap: () => unawaited(_createNew()),
                  ),
                  if (playlists == null && !_failed)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (playlists == null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No se pudieron cargar tus playlists.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final playlist in playlists)
                      _PickRow(
                        key: ValueKey(playlist.id),
                        title: playlist.title,
                        leading: TrackArtwork(
                          url: playlist.thumbnailUrl,
                          size: 48,
                          borderRadius: 8,
                          fallbackIcon: Icons.queue_music,
                        ),
                        onTap: () => _saveTo(playlist),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    super.key,
    required this.title,
    required this.leading,
    required this.onTap,
  });

  final String title;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
