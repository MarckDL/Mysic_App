import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/offline_mode.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/presentation/live_cover.dart' show RadioLogo;
import '../data/radio_store.dart';
import '../domain/radio_station.dart';

/// El bloque «Radio» del Inicio: un rectángulo por emisora con sus colores, su
/// nombre y su dial. Tocarlo sintoniza y suena el directo.
class RadioShelf extends ConsumerStatefulWidget {
  const RadioShelf({super.key, this.store});

  /// Para las pruebas; la app usa la lista guardada en el teléfono.
  final RadioStore? store;

  /// El título del bloque.
  static const title = 'Radio (Auspiciado por Borregon)';

  static const tileHeight = 92.0;
  static const gap = 10.0;

  /// Cuánto asoma la ficha siguiente por el borde derecho.
  static const peek = 40.0;

  /// El ancho de cada ficha: caben dos y la tercera asoma [peek]. Con un ancho
  /// fijo (180) dos fichas llenaban justo la fila y la tercera quedaba
  /// exactamente en el borde, sin asomar (Flutter no dibuja lo que empieza
  /// fuera de la vista). En pantallas anchas, 200 como máximo.
  static double tileWidthFor(double rowWidth) =>
      ((rowWidth - gap - peek) / 2).clamp(140.0, 200.0);

  @override
  ConsumerState<RadioShelf> createState() => _RadioShelfState();
}

class _RadioShelfState extends ConsumerState<RadioShelf> {
  late final RadioStore _store = widget.store ?? RadioStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    unawaited(_store.load());
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _tune(RadioStation station) {
    if (OfflineMode.instance.active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La radio necesita conexión a internet.')),
      );
      return;
    }
    unawaited(
      ref.read(trackPlaybackControllerProvider).playQueue([station.toTrack()]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stations = _store.stations;
    if (stations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
          child: Semantics(
            header: true,
            child: Text(
              RadioShelf.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
          ),
        ),
        SizedBox(
          height: RadioShelf.tileHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              final width = RadioShelf.tileWidthFor(box.maxWidth);
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                // Como los demás carruseles del Inicio: las fichas pasan por
                // debajo del margen de la página en vez de cortarse en seco.
                clipBehavior: Clip.none,
                itemCount: stations.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: RadioShelf.gap),
                itemBuilder: (context, i) => _RadioTile(
                  key: ValueKey('radio:${stations[i].id}'),
                  station: stations[i],
                  width: width,
                  onTap: () => _tune(stations[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    super.key,
    required this.station,
    required this.width,
    required this.onTap,
  });

  final RadioStation station;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    // Sobre un fondo claro (ROVR, amarillo) el texto va oscuro; si no, blanco.
    final light = Color(station.colors.first).computeLuminance() > .5;
    final ink = light ? const Color(0xFF161616) : Colors.white;
    return Semantics(
      button: true,
      label: '${station.name}, ${station.label}',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          width: width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [for (final c in station.colors) Color(c)],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          station.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.titleSmall?.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          station.label,
                          maxLines: 1,
                          style: theme.bodySmall?.copyWith(
                            color: ink.withValues(alpha: .85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // El logo de la emisora, a la derecha.
                  if (station.logo != null) ...[
                    const SizedBox(width: 6),
                    RadioLogo(logo: station.logo!, size: 64),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
