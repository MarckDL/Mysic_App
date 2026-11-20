import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class PlayerBackdrop extends StatefulWidget {
  const PlayerBackdrop({
    super.key,
    required this.artwork,
    required this.builder,
  });

  final ImageProvider<Object>? artwork;
  final Widget Function(BuildContext context, ThemeData theme, Widget backdrop)
  builder;

  @override
  State<PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<PlayerBackdrop> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider<Object>? _available;
  Color? _coverColor;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(PlayerBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artwork != widget.artwork) _resolveArtwork();
  }

  void _resolveArtwork() {
    final provider = widget.artwork;
    final stream = provider?.resolve(createLocalImageConfiguration(context));
    if (stream?.key == _stream?.key) return;
    _unsubscribe();
    final request = ++_request;
    _available = null;
    _coverColor = null;
    if (stream == null) return;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronous) {
        stream.removeListener(listener);
        if (synchronous) {
          _available = provider;
        } else {
          setState(() => _available = provider);
        }
        _readColor(info, request);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  Future<void> _readColor(ImageInfo info, int request) async {
    ui.Picture? picture;
    ui.Image? sample;
    try {
      const size = 24;
      final image = info.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 24, 24),
        Paint()..filterQuality = FilterQuality.low,
      );
      picture = recorder.endRecording();
      sample = await picture.toImage(size, size);
      final data = await sample.toByteData();
      if (!mounted || request != _request || data == null) return;
      final color = _representativeColor(data);
      setState(() => _coverColor = color);
    } catch (_) {
      // A missing or undecodable cover keeps the default palette.
    } finally {
      sample?.dispose();
      picture?.dispose();
      info.dispose();
    }
  }

  Color? _representativeColor(ByteData bytes) {
    final buckets = List.generate(12, (_) => <double>[0, 0, 0, 0]);
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) < 220) continue;
      final hsl = HSLColor.fromColor(
        Color.fromARGB(
          255,
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        ),
      );
      if (hsl.saturation < .22 || hsl.lightness < .13 || hsl.lightness > .87) {
        continue;
      }
      final bucket = buckets[(hsl.hue / 30).floor() % buckets.length];
      final weight = hsl.saturation * (1 - (hsl.lightness - .5).abs());
      bucket[0] += weight;
      bucket[1] += hsl.hue * weight;
      bucket[2] += hsl.saturation * weight;
      bucket[3] += hsl.lightness * weight;
    }
    final winner = buckets.reduce((a, b) => a[0] >= b[0] ? a : b);
    if (winner[0] <= 1) return null;
    return HSLColor.fromAHSL(
      1,
      winner[1] / winner[0],
      (winner[2] / winner[0]).clamp(.32, .66),
      (winner[3] / winner[0]).clamp(.37, .57),
    ).toColor();
  }

  void _unsubscribe() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coverColor = _coverColor;
    final theme = Theme.of(context);
    final paper = theme.colorScheme.surface;
    final tint = Color.lerp(
      paper,
      coverColor ?? theme.colorScheme.primary,
      .20,
    )!;
    final artwork = _available;
    final backdrop = IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tint),
            if (artwork != null)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Image(
                  image: artwork,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .43, .86],
                  colors: [
                    tint.withValues(alpha: .93),
                    Color.lerp(tint, paper, .72)!.withValues(alpha: .97),
                    paper,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.builder(context, theme, backdrop);
  }
}
