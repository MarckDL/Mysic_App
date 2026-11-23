import 'dart:async';

import 'package:flutter/material.dart';

import '../../search/presentation/catalog_widgets.dart' show TrackArtwork;
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';
import '../domain/shortcut.dart';
import 'track_sheet.dart' show shortcutOf;

/// El icono de un atajo sin portada: el de su colección o el de su tipo.
IconData shortcutIcon(Shortcut shortcut) => switch (shortcut.kind) {
  ShortcutKind.playlist => Icons.queue_music_rounded,
  ShortcutKind.album => Icons.album_rounded,
  ShortcutKind.track => Icons.music_note_rounded,
  ShortcutKind.collection => switch (shortcut.id) {
    Shortcut.liked => Icons.favorite_rounded,
    Shortcut.downloads => Icons.download_for_offline_rounded,
    Shortcut.mostPlayed => Icons.trending_up_rounded,
    Shortcut.artists => Icons.people_alt_rounded,
    _ => Icons.history_rounded,
  },
};

/// Las colecciones de la Biblioteca que la cuenta puede fijar, en el orden de
/// sus teselas.
List<Shortcut> collectionShortcuts(Set<String> capabilities) => [
  if (capabilities.contains('liked') || capabilities.contains('channelLiked'))
    const Shortcut(
      ShortcutKind.collection,
      Shortcut.liked,
      'Tus Me gusta',
      subtitle: 'Tus favoritas',
    ),
  const Shortcut(
    ShortcutKind.collection,
    Shortcut.downloads,
    'Descargas',
    subtitle: 'En este teléfono',
  ),
  if (capabilities.contains('onRepeat'))
    const Shortcut(
      ShortcutKind.collection,
      Shortcut.mostPlayed,
      'Lo más oído',
      subtitle: 'Últimos 30 días',
    ),
  if (capabilities.contains('artists'))
    const Shortcut(
      ShortcutKind.collection,
      Shortcut.artists,
      'Artistas',
      subtitle: 'Los que sigues',
    ),
  if (capabilities.contains('history') || capabilities.contains('mysicRecents'))
    const Shortcut(
      ShortcutKind.collection,
      Shortcut.recents,
      'Recientes',
      subtitle: 'Tu historial',
    ),
];

Widget _sheetFrame(BuildContext context, String title, List<Widget> children) {
  final theme = Theme.of(context), colors = theme.colorScheme;
  return Material(
    color: colors.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      // Una biblioteca larga se desplaza dentro de la hoja en vez de
      // empujarla bajo la barra de estado.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
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
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
              ),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showSheet(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .5),
      elevation: 0,
      builder: builder,
    );

/// «Añadir atajo» (Limusic `ShortcutPicker`): fija desde la Biblioteca sin
/// buscar un menú. Sigue abierta para fijar varios; lo fijado lleva una marca
/// y un segundo toque lo quita. Con la cuadrícula llena, lo no fijado se
/// apaga.
Future<void> showShortcutPicker(
  BuildContext context,
  MusicModeController music,
  String generation,
) => _showSheet(
  context,
  (context) => _ShortcutPicker(music: music, generation: generation),
);

class _ShortcutPicker extends StatefulWidget {
  const _ShortcutPicker({required this.music, required this.generation});

  final MusicModeController music;
  final String generation;

  @override
  State<_ShortcutPicker> createState() => _ShortcutPickerState();
}

class _ShortcutPickerState extends State<_ShortcutPicker> {
  var _playlists = const <Shortcut>[];
  var _albums = const <Shortcut>[];

  @override
  void initState() {
    super.initState();
    final music = widget.music, generation = widget.generation;
    List<Shortcut> seen(MusicSurface surface) => [
      for (final item
          in music.recalledPage(generation, surface)?.items ??
              const <MusicItem>[])
        if (item is MusicPlaylist || item is MusicAlbum) shortcutOf(item),
    ];
    // Lo visto en la sesión se pinta ya; la red lo confirma.
    _playlists = seen(MusicSurface.playlists);
    _albums = seen(MusicSurface.albums);
    final caps = music.connection?.capabilities ?? const <String>{};
    if (caps.contains('playlists')) {
      unawaited(_load(MusicSurface.playlists, (list) => _playlists = list));
    }
    if (caps.contains('albums')) {
      unawaited(_load(MusicSurface.albums, (list) => _albums = list));
    }
  }

  Future<void> _load(
    MusicSurface surface,
    void Function(List<Shortcut> list) store,
  ) async {
    try {
      final page = await widget.music.page(
        widget.generation,
        surface,
        quiet: true,
      );
      if (!mounted) return;
      setState(
        () => store([
          for (final item in page.items)
            if (item is MusicPlaylist || item is MusicAlbum) shortcutOf(item),
        ]),
      );
    } on Object {
      // Se queda con lo que ya se veía.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final music = widget.music;
    final groups = [
      (
        'Biblioteca',
        collectionShortcuts(music.connection?.capabilities ?? const {}),
      ),
      ('Playlists', _playlists),
      ('Álbumes', _albums),
    ].where((group) => group.$2.isNotEmpty);
    return ValueListenableBuilder(
      valueListenable: music.shortcuts,
      builder: (context, _, _) {
        final full = music.shortcutsFull;
        return _sheetFrame(context, 'Añadir atajo', [
          for (final (label, items) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            for (final shortcut in items)
              Builder(
                key: ValueKey('${shortcut.kind.name}:${shortcut.id}'),
                builder: (context) {
                  final pinned = music.isShortcut(shortcut);
                  final enabled = pinned || !full;
                  return Opacity(
                    opacity: enabled ? 1 : .4,
                    child: InkWell(
                      onTap: enabled
                          ? () => music.toggleShortcut(shortcut)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            ShortcutArt(shortcut: shortcut, size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shortcut.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (shortcut.subtitle != null)
                                    Text(
                                      shortcut.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              pinned
                                  ? Icons.check_circle_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: pinned
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ]);
      },
    );
  }
}

/// La imagen de un atajo: una colección pinta su icono sobre un tinte del
/// acento, como las teselas de la Biblioteca; lo demás, su portada.
class ShortcutArt extends StatelessWidget {
  const ShortcutArt({super.key, required this.shortcut, required this.size});

  final Shortcut shortcut;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (shortcut.kind != ShortcutKind.collection) {
      return TrackArtwork(
        url: shortcut.thumbnail,
        size: size,
        borderRadius: 8,
        fallbackIcon: shortcutIcon(shortcut),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(shortcutIcon(shortcut), size: 24, color: colors.primary),
      ),
    );
  }
}

/// «Editar inicio» (Limusic `EditHomeSheet`, con lo que Mysic tiene): qué
/// partes de Inicio se ven. Cada interruptor se aplica y se guarda al tocarlo.
Future<void> showEditHome(BuildContext context, MusicModeController music) =>
    _showSheet(
      context,
      (context) => ValueListenableBuilder(
        valueListenable: music.homeLayout,
        builder: (context, layout, _) {
          Widget toggle(
            String title,
            String subtitle,
            bool value,
            HomeLayout Function(bool on) apply,
          ) => SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(title),
            subtitle: Text(subtitle),
            value: value,
            onChanged: (on) => music.setHomeLayout(apply(on)),
          );
          return _sheetFrame(context, 'Editar inicio', [
            toggle(
              'Ambientes',
              'La fila de Relax, Dormir, Energía…',
              layout.chips,
              (on) => layout.copyWith(chips: on),
            ),
            toggle(
              'Fondo con la carátula',
              'Lo que suena, desenfocado tras la cabecera',
              layout.backdrop,
              (on) => layout.copyWith(backdrop: on),
            ),
            toggle(
              'Atajos',
              'Lo que fijaste de tu biblioteca',
              layout.shortcuts,
              (on) => layout.copyWith(shortcuts: on),
            ),
            toggle(
              'Accesos directos',
              'El collage de lo que más escuchas',
              layout.dial,
              (on) => layout.copyWith(dial: on),
            ),
          ]);
        },
      ),
    );
