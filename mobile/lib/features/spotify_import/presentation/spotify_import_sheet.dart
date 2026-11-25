import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../connected_library/domain/music_mode.dart' show MusicTrack;
import '../../connected_library/domain/music_search.dart' show SearchKind;
import '../../connected_library/presentation/catalog_pages.dart' show PageSeed;
import '../../connected_library/presentation/library_screen.dart'
    show libraryRefreshRequests;
import '../../connected_library/presentation/music_mode_host.dart';
import '../application/spotify_import_controller.dart';
import '../data/spotify_fetcher.dart';
import '../domain/spotify_matching.dart' show MatchTier;

/// «Importar de Spotify»: pega el enlace de una playlist de Spotify y sus
/// canciones se buscan en YouTube Music y se guardan en una playlist nueva de tu
/// cuenta (como «Abrir enlace» de Mysic de escritorio).
Future<void> showSpotifyImport(BuildContext context) async {
  final music = MusicModeScope.of(context);
  final generation = music?.connection?.generation;
  if (music == null ||
      generation == null ||
      music.connection?.isDirect != true) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inicia sesión en YouTube Music para importar.'),
      ),
    );
    return;
  }
  final fetcher = SpotifyFetcher();
  final controller = SpotifyImportController(
    fetch: fetcher.playlist,
    search: (query) async => [
      for (final item in await music.ask(
        generation,
        (client) => client.searchKind(query, SearchKind.songs),
      ))
        if (item is MusicTrack) item,
    ],
    create: (title, description, ids) => music.ask(generation, (client) async {
      final id = await client.ytm.createPlaylist(title, videoIds: ids);
      try {
        await client.ytm.editPlaylist(id, description: description);
      } on Object {
        // Sin descripción la playlist se crea igual.
      }
      return id;
    }),
  );
  // El router se toma aquí, de la pantalla que abre la hoja: la hoja se abre
  // sobre el navegador raíz, fuera del árbol de rutas, y desde ella
  // `GoRouter.of` falla («No GoRouter found in context»).
  final router = GoRouter.of(context);
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    isDismissible: true,
    builder: (sheet) => SpotifyImportBody(
      controller: controller,
      onOpenPlaylist: (id, name) => router.push(
        '/music/playlist/${Uri.encodeComponent(id)}',
        extra: PageSeed(title: name),
      ),
    ),
  );
  // La búsqueda no se corta al cerrar la hoja a medias: se detiene y se guarda
  // lo encontrado.
  controller.stop();
  if (controller.createdId != null) libraryRefreshRequests.value++;
  // El controlador sigue vivo mientras la búsqueda termina de guardar.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 30), controller.dispose),
  );
}

/// El contenido de la hoja. Público para poder probarlo.
class SpotifyImportBody extends StatefulWidget {
  const SpotifyImportBody({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
  });

  final SpotifyImportController controller;

  /// Abre la playlist creada ([id], [name]). Lo da quien abre la hoja, que es
  /// quien tiene el router.
  final void Function(String id, String name) onOpenPlaylist;

  @override
  State<SpotifyImportBody> createState() => _SpotifyImportBodyState();
}

class _SpotifyImportBodyState extends State<SpotifyImportBody> {
  final _link = TextEditingController();

  SpotifyImportController get _c => widget.controller;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _link.text = text);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Importar de Spotify',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._content(context),
          ],
        ),
      ),
    ),
  );

  List<Widget> _content(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    switch (_c.phase) {
      case SpotifyImportPhase.idle:
      case SpotifyImportPhase.failed when _c.playlist == null:
        return [
          Text(
            'Pega el enlace de una playlist de Spotify. Sus canciones se '
            'buscan en YouTube Music y se guardan en una playlist nueva de '
            'tu cuenta.',
            style: muted,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => unawaited(_c.open(_link.text)),
            decoration: InputDecoration(
              hintText: 'https://open.spotify.com/playlist/…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Pegar',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
            ),
          ),
          if (_c.message != null) ...[
            const SizedBox(height: 10),
            Text(
              _c.message!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => unawaited(_c.open(_link.text)),
              child: const Text('Leer playlist'),
            ),
          ),
        ];
      case SpotifyImportPhase.loading:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      case SpotifyImportPhase.preview:
        final list = _c.playlist!;
        return [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 84,
                  child: list.cover == null
                      ? ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: const Icon(Icons.queue_music, size: 36),
                        )
                      : Image.network(
                          list.cover!,
                          fit: BoxFit.cover,
                          // Mientras llega (o si no llega) se ve el icono, no un
                          // hueco vacío.
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                              ? child
                              : ColoredBox(
                                  color: colors.surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.queue_music,
                                    size: 36,
                                  ),
                                ),
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: const Icon(Icons.queue_music, size: 36),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (list.owner != null)
                      Text(list.owner!, maxLines: 1, style: muted),
                    Text(
                      '${list.tracks.length}${list.truncated ? '+' : ''} '
                      '${list.tracks.length == 1 ? 'canción' : 'canciones'}',
                      style: muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (list.truncated) ...[
            const SizedBox(height: 10),
            Text(
              'Spotify solo deja leer las primeras ${list.tracks.length} '
              'canciones de una playlist pública.',
              style: muted,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Se creará una playlist privada en tu cuenta de YouTube Music con '
            'las canciones que se encuentren.',
            style: muted,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => unawaited(_c.start()),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Importar a YouTube Music'),
            ),
          ),
          TextButton(onPressed: _c.restart, child: const Text('Otro enlace')),
        ];
      case SpotifyImportPhase.matching:
        return [
          Text('Buscando canciones · ${_c.percent} %', style: muted),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _c.total == 0 ? null : _c.percent / 100,
          ),
          const SizedBox(height: 8),
          Text(
            '${_c.done} de ${_c.total} · encontradas ${_c.found}'
            '${_c.check > 0 ? ' (${_c.check} por revisar)' : ''}'
            '${_c.missing > 0 ? ' · sin encontrar ${_c.missing}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in _c.recent) _recentRow(context, row),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _c.stop,
              child: const Text('Detener y guardar lo encontrado'),
            ),
          ),
        ];
      case SpotifyImportPhase.saving:
        return [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          Center(
            child: Text('Guardando la playlist en tu cuenta…', style: muted),
          ),
        ];
      case SpotifyImportPhase.done:
      case SpotifyImportPhase.cancelled when _c.createdId != null:
        return [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _c.message ??
                      'Playlist «${_c.playlist?.name}» creada: ${_c.created} '
                          'de ${_c.total} canciones.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          if (_c.check > 0)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${_c.check} por revisar'),
              subtitle: const Text(
                'Se añadieron, pero pueden no ser la misma.',
              ),
              children: [
                for (final item in _c.checkList)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.title, maxLines: 1),
                    subtitle: Text('→ ${item.found}', maxLines: 1),
                  ),
              ],
            ),
          if (_c.missing > 0)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${_c.missing} sin encontrar'),
              subtitle: const Text('No están en la playlist.'),
              children: [
                for (final item in _c.missingList)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.title, maxLines: 1),
                    subtitle: item.artists.isEmpty
                        ? null
                        : Text(item.artists, maxLines: 1),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _c.missingText),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lista copiada')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar la lista'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final id = _c.createdId;
                    final name = _c.playlist?.name ?? 'Playlist';
                    Navigator.of(context).pop();
                    if (id != null) widget.onOpenPlaylist(id, name);
                  },
                  child: const Text('Abrir playlist'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Listo'),
              ),
            ],
          ),
        ];
      case SpotifyImportPhase.failed:
      case SpotifyImportPhase.cancelled:
        return [
          Text(
            _c.message ?? 'La importación se detuvo.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton(
                onPressed: _c.restart,
                child: const Text('Intentar de nuevo'),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ];
    }
  }

  Widget _recentRow(BuildContext context, RecentMatch row) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (row.tier) {
      MatchTier.matched => (Icons.check_rounded, colors.primary),
      MatchTier.check => (Icons.help_outline_rounded, colors.tertiary),
      MatchTier.missing => (Icons.close_rounded, colors.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [row.title, if (row.artists.isNotEmpty) row.artists].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
