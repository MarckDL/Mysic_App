import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A waveform timeline that never pretends missing peaks are measured samples.
/// [peaks] must contain normalized amplitudes of the actual track in [0, 1].
class WaveformTimeline extends StatefulWidget {
  const WaveformTimeline({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.peaks = const [],
    this.activeColor = const Color(0xFFC6A5FF),
    this.inactiveColor = const Color(0xFF51475B),
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;
  final List<double> peaks;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<WaveformTimeline> createState() => _WaveformTimelineState();
}

class _WaveformTimelineState extends State<WaveformTimeline> {
  double? _dragProgress;

  double get _progress {
    final milliseconds = widget.duration?.inMilliseconds ?? 0;
    if (milliseconds <= 0) return 0;
    return (widget.position.inMilliseconds / milliseconds).clamp(0.0, 1.0);
  }

  void _update(Offset localPosition, double width) {
    if (width <= 0 || (widget.duration?.inMilliseconds ?? 0) <= 0) return;
    setState(() {
      _dragProgress = (localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  void _commit() {
    final progress = _dragProgress;
    final length = widget.duration?.inMilliseconds ?? 0;
    setState(() => _dragProgress = null);
    if (progress != null && length > 0) {
      widget.onSeek(Duration(milliseconds: (length * progress).round()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = (widget.duration?.inMilliseconds ?? 0) > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = _dragProgress ?? _progress;
        return Semantics(
          label: 'Progreso de reproducción',
          value: '${(progress * 100).round()} %',
          enabled: enabled,
          slider: true,
          onIncrease: enabled ? () => widget.onSeek(Duration(milliseconds: math.min(widget.position.inMilliseconds + 5000, widget.duration!.inMilliseconds))) : null,
          onDecrease: enabled ? () => widget.onSeek(Duration(milliseconds: math.max(widget.position.inMilliseconds - 5000, 0))) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (details) => _update(details.localPosition, width) : null,
            onTapUp: enabled ? (_) => _commit() : null,
            onHorizontalDragStart: enabled ? (details) => _update(details.localPosition, width) : null,
            onHorizontalDragUpdate: enabled ? (details) => _update(details.localPosition, width) : null,
            onHorizontalDragEnd: enabled ? (_) => _commit() : null,
            onHorizontalDragCancel: () => setState(() => _dragProgress = null),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(
                painter: _WaveformPainter(
                  peaks: widget.peaks,
                  progress: progress,
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.peaks, required this.progress, required this.activeColor, required this.inactiveColor});

  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.max(1, (size.width / 3).floor());
    const barWidth = 2.0;
    final step = size.width / count;
    // Unknown peak values are flat, not fabricated amplitudes.
    for (var index = 0; index < count; index++) {
      final peak = peaks.isEmpty ? 0.0 : peaks[math.min(peaks.length - 1, (index * peaks.length / count).floor())].clamp(0.0, 1.0);
      final height = 2.0 + peak * 16.0;
      final x = index * step + (step - barWidth) / 2;
      final y = (size.height - height) / 2;
      final paint = Paint()..color = (index + 0.5) / count <= progress ? activeColor : inactiveColor;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barWidth, height), const Radius.circular(1)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.peaks != peaks ||
      oldDelegate.activeColor != activeColor || oldDelegate.inactiveColor != inactiveColor;
}
