import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_widgets.dart';

/// Cabecera de la hoja de una canción: portada de 52 dp (radio 10), título y
/// subtítulo (Limusic `SongMenuHeader`).
class SheetHeader {
  const SheetHeader({
    required this.title,
    this.subtitle,
    this.url,
    this.liked,
    this.onLike,
  });

  final String title;
  final String? subtitle;
  final String? url;

  /// Si la canción tiene Me gusta; null (o sin [onLike]) no pinta corazón. Es
  /// una función para que el corazón siga al estado mientras la hoja está
  /// abierta.
  final bool Function()? liked;

  /// Tocar el corazón, al final de la cabecera (en Limusic no es una fila).
  final VoidCallback? onLike;
}

/// Acción rápida de la cuadrícula 2×2 (Limusic `QuickTile`).
class SheetTile {
  const SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.progress,
    this.closes = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Círculo del icono relleno con el acento (p. ej. «Descargada»).
  final bool active;

  /// Avance de una descarga (0–1; -1 sin tamaño conocido); null si no hay.
  final double? progress;

  /// Si la hoja se cierra al tocar. «Descargar» la deja abierta, como Limusic.
  final bool closes;
}

/// Fila de la lista bajo la cuadrícula (Limusic `ActionButton`).
class SheetRow {
  const SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.subtitle,
    this.closes = true,
  });

  final IconData icon;
  final String label;

  /// Null: la fila se ve apagada (p. ej. mientras carga lo que necesita).
  final VoidCallback? onTap;
  final bool destructive;

  /// Línea bajo el nombre (el artista o el álbum al que lleva la fila).
  final String? subtitle;

  /// Si la hoja se cierra al tocar. «No me gusta» la deja abierta: el pulgar
  /// relleno es la respuesta.
  final bool closes;
}

/// Hoja inferior de un elemento (canción, álbum, playlist, artista…), con el
/// aspecto de las de Limusic: tarjeta con esquinas superiores de 20 dp sobre un
/// velo negro al 50 %, tirador de 32×4, cabecera opcional, fila «Reproducir» con
/// botón de aleatorio, cuadrícula de acciones rápidas y lista de acciones.
///
/// [tiles] y [rows] son funciones para que la hoja se reconstruya con
/// [refresh] (p. ej. el estado de una descarga) mientras está abierta.
Future<void> showItemSheet(
  BuildContext context, {
  SheetHeader? header,
  VoidCallback? onPlay,
  VoidCallback? onShuffle,
  List<SheetTile> Function()? tiles,
  List<SheetRow> Function()? rows,
  Listenable? refresh,
}) {
  // Se abre al mantener pulsado: una vibración corta lo confirma.
  HapticFeedback.mediumImpact();
  return _show(
    context,
    header: header,
    onPlay: onPlay,
    onShuffle: onShuffle,
    tiles: tiles,
    rows: rows,
    refresh: refresh,
  );
}

Future<void> _show(
  BuildContext context, {
  SheetHeader? header,
  VoidCallback? onPlay,
  VoidCallback? onShuffle,
  List<SheetTile> Function()? tiles,
  List<SheetRow> Function()? rows,
  Listenable? refresh,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // Sobre la barra de pestañas y el mini reproductor, como en Limusic.
  useRootNavigator: true,
  useSafeArea: true,
  // El tema de la app pone un tirador propio; esta hoja dibuja el suyo.
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .5),
  elevation: 0,
  builder: (sheetContext) {
    Widget build(BuildContext context) => _SheetCard(
      header: header,
      onPlay: onPlay,
      onShuffle: onShuffle,
      tiles: tiles?.call() ?? const [],
      rows: rows?.call() ?? const [],
      close: () => Navigator.of(sheetContext).pop(),
    );
    return refresh == null
        ? Builder(builder: build)
        : ListenableBuilder(
            listenable: refresh,
            builder: (context, _) => build(context),
          );
  },
);

class _SheetCard extends StatelessWidget {
  const _SheetCard({
    required this.header,
    required this.onPlay,
    required this.onShuffle,
    required this.tiles,
    required this.rows,
    required this.close,
  });

  final SheetHeader? header;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final List<SheetTile> tiles;
  final List<SheetRow> rows;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
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
            if (header != null) _Header(header: header!),
            if (onPlay != null)
              _PlayRow(onPlay: onPlay!, onShuffle: onShuffle, close: close),
            if (tiles.isNotEmpty) _TileGrid(tiles: tiles, close: close),
            for (final row in rows) _Row(row: row, close: close),
            // Margen inferior: la barra de navegación del sistema y 8 dp.
            SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.header});

  final SheetHeader header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
      child: Row(
        children: [
          TrackArtwork(url: header.url, size: 52, borderRadius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (header.subtitle != null && header.subtitle!.isNotEmpty)
                  Text(
                    header.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (header.liked != null && header.onLike != null)
            IconButton(
              tooltip: header.liked!() ? 'Quitar Me gusta' : 'Me gusta',
              iconSize: 28,
              icon: Icon(
                header.liked!()
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: header.liked!()
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
              onPressed: header.onLike,
            ),
        ],
      ),
    );
  }
}

/// «Reproducir» con el botón redondo de aleatorio al final (Limusic
/// `PlayActionRow`).
class _PlayRow extends StatelessWidget {
  const _PlayRow({
    required this.onPlay,
    required this.onShuffle,
    required this.close,
  });

  final VoidCallback onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        close();
        onPlay();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Row(
          children: [
            Icon(Icons.play_arrow_rounded, color: colors.primary),
            const SizedBox(width: 22),
            Expanded(
              child: Text(
                'Reproducir',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: colors.primary),
              ),
            ),
            if (onShuffle != null)
              IconButton.filledTonal(
                tooltip: 'Aleatorio',
                icon: const Icon(Icons.shuffle),
                onPressed: () {
                  close();
                  onShuffle!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.close});

  final List<SheetTile> tiles;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final chunks = <List<SheetTile>>[
      for (var i = 0; i < tiles.length; i += 2)
        tiles.sublist(i, i + 2 > tiles.length ? tiles.length : i + 2),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (final (index, chunk) in chunks.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (final (i, tile) in chunk.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Tile(tile: tile, close: close),
                  ),
                ],
                // Una fila con una sola acción deja el otro medio hueco.
                if (chunk.length == 1) ...[
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.close});

  final SheetTile tile;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = tile.onTap != null;
    final progress = tile.progress;
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: Material(
        color: colors.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  if (tile.closes) close();
                  tile.onTap!();
                }
              : null,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tile.active
                          ? colors.primary
                          : colors.primary.withValues(alpha: .16),
                    ),
                    child: progress == null
                        ? Icon(
                            tile.icon,
                            size: 20,
                            color: tile.active
                                ? colors.onPrimary
                                : colors.primary,
                          )
                        : SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              // -1: aún no se conoce el tamaño.
                              value: progress < 0 ? null : progress,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tile.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.close});

  final SheetRow row;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = row.onTap != null;
    final color =
        (row.destructive
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface)
            .withValues(alpha: enabled ? 1 : .38);
    return InkWell(
      onTap: !enabled
          ? null
          : () {
              if (row.closes) close();
              row.onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 32, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(row.icon, size: 24, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (row.subtitle != null && row.subtitle!.isNotEmpty)
                      Text(
                        row.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: enabled ? 1 : .38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
