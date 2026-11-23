import 'dart:async';

import 'package:flutter/material.dart';

import '../core/images/cover_color.dart';
import '../features/playback/application/track_playback_controller.dart';
import '../features/search/presentation/catalog_widgets.dart';
import 'mysic_theme.dart';

/// Tiñe el tema con el color de la carátula de la canción que suena, como la
/// opción "Adaptar colores a la carátula" de Limusic (activada por defecto).
///
/// Sin canción, o si la portada no tiene un tono utilizable, vuelve al tema
/// base. El cambio se aplica de una vez: animarlo reconstruía toda la app
/// durante medio segundo, justo mientras se abre el reproductor y carga el
/// audio. Las pantallas que quieren suavizarlo animan su propio fondo.
class AdaptiveTheme extends StatefulWidget {
  const AdaptiveTheme({
    super.key,
    required this.player,
    required this.child,
    this.enabled = true,
  });

  final TrackPlaybackController player;
  final bool enabled;
  final Widget child;

  @override
  State<AdaptiveTheme> createState() => _AdaptiveThemeState();
}

class _AdaptiveThemeState extends State<AdaptiveTheme> {
  ThemeData _data = mysicDarkTheme();
  String? _url;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(AdaptiveTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_check);
      widget.player.addListener(_check);
      _url = null;
      _check();
    } else if (oldWidget.enabled != widget.enabled) {
      _url = null;
      _check();
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final player = widget.player;
    // La pista de prueba empaquetada no tiene portada de red.
    final url = !widget.enabled || player.isBundledTrack
        ? null
        : player.current?.thumbnailUrl;
    if (url == _url) return;
    _url = url;
    final request = ++_request;
    if (url == null) {
      _apply(null);
      return;
    }
    unawaited(
      CoverColor.of(_sample(url)).then((color) {
        // Una pista nueva puede haber llegado mientras se calculaba.
        if (mounted && request == _request) _apply(color);
      }),
    );
    // Se adelanta el color de las pistas vecinas (como Limusic): al saltar o
    // deslizar la carátula, el tema cambia sin esperar a calcularlo.
    final queue = player.queue, index = player.index;
    for (final neighbor in [index + 1, index - 1, index + 2]) {
      if (neighbor < 0 || neighbor >= queue.length) continue;
      final next = queue[neighbor].thumbnailUrl;
      if (next != null && next != url) {
        unawaited(CoverColor.of(_sample(next)));
      }
    }
  }

  // El color se lee del mismo archivo pequeño que pintan las filas y el
  // fondo del reproductor: ya está en disco, no se descarga otra copia.
  static String _sample(String url) => TrackArtwork.sizedUrl(url, 160);

  Color? _cover;

  void _apply(Color? cover) {
    // Dos pistas del mismo álbum dan el mismo color: no hay nada que rehacer.
    if (cover == _cover) return;
    _cover = cover;
    setState(() => _data = mysicDarkTheme(cover: cover));
  }

  @override
  Widget build(BuildContext context) => Theme(data: _data, child: widget.child);
}
