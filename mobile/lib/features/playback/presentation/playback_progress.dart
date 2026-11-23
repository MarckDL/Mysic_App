import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/track_playback_controller.dart';
import 'player_widgets.dart';

/// La barra de avance del reproductor: la forma de onda de la canción, con
/// lo ya sonado en el color de la portada y una aguja donde va.
class PlaybackProgress extends StatefulWidget {
  const PlaybackProgress({super.key, required this.controller});

  final TrackPlaybackController controller;

  /// Las pruebas pueden apagar las animaciones de la barra; la forma de onda
  /// es fija, así que hoy no cambia nada.
  static bool animationsEnabled = true;

  @override
  State<PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<PlaybackProgress> {
  double? _preview;

  // El avance de la pista solo redibuja esta barra, no el reproductor entero.
  @override
  void initState() {
    super.initState();
    widget.controller.positionListenable.addListener(_tick);
  }

  @override
  void didUpdateWidget(PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.positionListenable.removeListener(_tick);
      widget.controller.positionListenable.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.controller.positionListenable.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    // Mientras el usuario arrastra, manda su dedo.
    if (_preview == null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final length = controller.duration?.inMilliseconds ?? 0;
    final current = (_preview ?? controller.position.inMilliseconds.toDouble())
        .clamp(0, length)
        .toDouble();
    final slider = Semantics(
      label: 'Posición de reproducción',
      child: Slider(
        value: current,
        max: length > 0 ? length.toDouble() : 1,
        padding: EdgeInsets.zero,
        onChanged: controller.canSeek
            ? (value) => setState(() => _preview = value)
            : null,
        onChangeEnd: controller.canSeek
            ? (value) {
                setState(() => _preview = null);
                unawaited(
                  controller.seek(Duration(milliseconds: value.round())),
                );
              }
            : null,
        semanticFormatterCallback: (value) =>
            audioTime(Duration(milliseconds: value.round())),
      ),
    );
    final labels = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: RepaintBoundary(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: .32),
                disabledActiveTrackColor: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: .32),
                disabledInactiveTrackColor: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: .18),
                thumbColor: theme.colorScheme.primary,
                trackHeight: 34,
                trackShape: WaveformTrackShape(
                  seed: controller.current?.id.hashCode ?? 0,
                ),
                thumbShape: const _NeedleThumb(),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: slider,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                audioTime(Duration(milliseconds: current.round())),
                style: labels,
              ),
              Text(
                length > 0 ? audioTime(Duration(milliseconds: length)) : '—',
                style: labels,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pista del deslizador dibujada como forma de onda.
///
/// Las alturas salen de una función determinista de [seed] (la canción), sin
/// analizar el audio: cada pista tiene siempre la misma silueta y pintarla es
/// un bucle de líneas, sin reservas de memoria por fotograma.
class WaveformTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const WaveformTrackShape({required this.seed});

  final int seed;

  static const _pitch = 5.0;

  double _level(int bar) {
    final phase = (seed % 997) * .013;
    final slow = math.sin(bar * .19 + phase * 3);
    final fast = math.sin(bar * 1.37 + phase * 7) * math.sin(bar * .53 + phase);
    return (.22 + .5 * (slow * .5 + .5) * .7 + .36 * fast.abs()).clamp(.16, 1);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.width <= 0) return;
    final active = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color =
          (isEnabled
              ? sliderTheme.activeTrackColor
              : sliderTheme.disabledActiveTrackColor) ??
          const Color(0xFF000000);
    final inactive = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color =
          (isEnabled
              ? sliderTheme.inactiveTrackColor
              : sliderTheme.disabledInactiveTrackColor) ??
          const Color(0x55000000);
    final bars = (rect.width / _pitch).floor();
    final inset = (rect.width - (bars - 1) * _pitch) / 2;
    final middle = rect.center.dy;
    final canvas = context.canvas;
    for (var bar = 0; bar < bars; bar++) {
      final x = rect.left + inset + bar * _pitch;
      final half = rect.height * _level(bar) / 2;
      canvas.drawLine(
        Offset(x, middle - half),
        Offset(x, middle + half),
        x <= thumbCenter.dx ? active : inactive,
      );
    }
  }
}

/// La aguja que marca dónde va la canción sobre la forma de onda.
class _NeedleThumb extends SliderComponentShape {
  const _NeedleThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 44);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (enableAnimation.value == 0) return;
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? const Color(0xFF000000)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final canvas = context.canvas;
    canvas.drawLine(center.translate(0, -21), center.translate(0, 21), paint);
    canvas.drawCircle(center, 4.5 + activationAnimation.value * 2, paint);
  }
}
