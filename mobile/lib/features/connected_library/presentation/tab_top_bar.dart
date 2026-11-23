import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';

/// La cabecera de las pestañas (Inicio, Buscar, Biblioteca), la de Limusic
/// (`LimusicTabTopBar`): bajo la barra de estado, una fila de 64 dp con el
/// título a 16 dp del borde y las acciones al final; debajo, lo que la pestaña
/// añada ([bottom]: chips, campo de búsqueda). Va encima del contenido, que se
/// ve desenfocado a través de ella; con «Reducir efectos» es opaca.
///
/// Sin [scroll] el fondo desenfocado está siempre (la barra lleva chips o un
/// campo que necesitan respaldo); con él no hay desenfoque: arriba del todo se
/// ve lo que la pantalla pinta detrás y al desplazar baja un velo opaco.
class TabTopBar extends StatelessWidget {
  const TabTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.bottom,
    this.scroll,
  });

  /// Alto de la fila del título.
  static const height = 64.0;

  final String title;
  final List<Widget> actions;
  final Widget? bottom;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final reduced = EffectsScope.reducedOf(context);
    final content = Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
          ?bottom,
        ],
      ),
    );

    // Fondo fijo: el contenido desenfocado bajo un velo del color de la app.
    Widget frosted() {
      final veil = ColoredBox(
        color: colors.surface.withValues(alpha: reduced ? 1 : .62),
        child: const SizedBox.expand(),
      );
      if (reduced) return veil;
      return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: veil,
        ),
      );
    }

    // Fondo al desplazar: un velo opaco que baja y se desvanece por abajo, sin
    // desenfoque (sobre las pastillas de Inicio el desenfoque se veía como
    // una mancha). [shown] va de 0 a 1.
    Widget veil(double shown) => shown <= 0
        ? const SizedBox.shrink()
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.surface.withValues(alpha: shown),
                  colors.surface.withValues(alpha: shown),
                  colors.surface.withValues(alpha: 0),
                ],
                stops: const [0, .82, 1],
              ),
            ),
            child: const SizedBox.expand(),
          );
    final controller = scroll;
    return Stack(
      children: [
        Positioned.fill(
          child: controller == null
              ? frosted()
              : AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => veil(
                    ((controller.hasClients ? controller.offset : 0.0) / 32)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                  ),
                ),
        ),
        Material(type: MaterialType.transparency, child: content),
      ],
    );
  }
}
