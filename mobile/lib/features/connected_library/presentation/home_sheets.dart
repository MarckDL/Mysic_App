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

/// La hoja inferior de Inicio: asa, título y una lista que se desplaza.
/// [header] (p. ej. un buscador) queda fijo bajo el título, sin desplazarse;
/// con el teclado abierto la hoja sube sobre él.
Widget _sheetFrame(
  BuildContext context,
  String title,
  List<Widget> children, {
  Widget? header,
}) {
  final theme = Theme.of(context), colors = theme.colorScheme;
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return Padding(
    padding: EdgeInsets.only(bottom: keyboard),
    child: Material(
      color: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Una biblioteca larga se desplaza dentro de la hoja en vez de
        // empujarla bajo la barra de estado; con el teclado, se encoge.
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height - keyboard) * .75,
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
            ?header,
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
    ),
  );
}

/// El texto sin mayúsculas ni acentos, para comparar al buscar («Canción» y
/// «cancion» son lo mismo).
String foldForSearch(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    out.write(at < 0 ? char : to[at]);
  }
  return out.toString().trim();
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

  // El buscador: filtra por título las tres listas a la vez.
  final _search = TextEditingController();
  var _query = '';

  // Tope de páginas que se piden de cada lista: sobra para una cuenta normal
  // y evita un bucle si el servidor repite el cursor.
  static const _maxPages = 20;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Shortcut> _filtered(List<Shortcut> items) {
    final query = foldForSearch(_query);
    if (query.isEmpty) return items;
    return [
      for (final item in items)
        if (foldForSearch(item.title).contains(query)) item,
    ];
  }

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

  // Todas las playlists (o álbumes) de la cuenta, página a página: la lista
  // crece mientras llegan. Antes solo se ofrecía la primera página.
  Future<void> _load(
    MusicSurface surface,
    void Function(List<Shortcut> list) store,
  ) async {
    final all = <Shortcut>[];
    final seen = <String>{};
    String? cursor;
    try {
      for (var round = 0; round < _maxPages; round++) {
        final page = await widget.music.page(
          widget.generation,
          surface,
          cursor: cursor,
          quiet: true,
        );
        for (final item in page.items) {
          if (item is! MusicPlaylist && item is! MusicAlbum) continue;
          final shortcut = shortcutOf(item);
          if (seen.add('${shortcut.kind.name}:${shortcut.id}')) {
            all.add(shortcut);
          }
        }
        if (!mounted) return;
        setState(() => store(List.of(all)));
        cursor = page.nextCursor;
        if (cursor == null) break;
      }
    } on Object {
      // Se queda con lo que ya se veía.
    }
  }

  // El buscador: una línea con la lupa a la izquierda (y una «x» para borrar
  // lo escrito).
  Widget _searchField(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar',
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.onSurfaceVariant,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Borrar',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          // Solo una línea debajo, sin caja.
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final music = widget.music;
    final groups = [
      (
        'Biblioteca',
        _filtered(
          collectionShortcuts(music.connection?.capabilities ?? const {}),
        ),
      ),
      ('Playlists', _filtered(_playlists)),
      ('Álbumes', _filtered(_albums)),
    ].where((group) => group.$2.isNotEmpty).toList();
    return ValueListenableBuilder(
      valueListenable: music.shortcuts,
      builder: (context, _, _) {
        final full = music.shortcutsFull;
        return _sheetFrame(
          context,
          'Añadir atajo',
          header: _searchField(context),
          [
            // Nada coincide con lo escrito.
            if (groups.isEmpty && _query.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  'No hay resultados para «${_query.trim()}».',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
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
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
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
          ],
        );
      },
    );
  }
}

/// «Ordenar atajos» (la tuerca de «De one pe»): una lista que se reordena
/// arrastrando por el asa. Cada fila dice en qué bloque cae (los seis primeros
/// son el Bloque 1; los siguientes, el Bloque 2) y el orden se guarda al soltar.
Future<void> showShortcutOrder(
  BuildContext context,
  MusicModeController music,
) => _showSheet(context, (context) => _ShortcutOrder(music: music));

class _ShortcutOrder extends StatelessWidget {
  const _ShortcutOrder({required this.music});

  final MusicModeController music;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return ValueListenableBuilder(
      valueListenable: music.shortcuts,
      builder: (context, _, _) {
        final list = music.effectiveShortcuts;
        return Material(
          color: colors.surfaceContainerHigh,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
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
                        'Ordenar atajos',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Arrastra por el asa para cambiar el orden',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
                    ),
                    itemCount: list.length,
                    // `onReorderItem` ya da el destino ajustado (tras quitar la
                    // fila de su sitio).
                    onReorderItem: music.moveShortcut,
                    itemBuilder: (context, index) {
                      final shortcut = list[index];
                      final block = index ~/ Shortcut.perBlock + 1;
                      return Material(
                        key: ValueKey('${shortcut.kind.name}:${shortcut.id}'),
                        color: Colors.transparent,
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
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      'Bloque $block',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Tooltip(
                                  message: 'Arrastrar',
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
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
            toggle(
              'Radios',
              'Emisoras en directo, bajo el carrusel',
              layout.radio,
              (on) => layout.copyWith(radio: on),
            ),
          ]);
        },
      ),
    );
