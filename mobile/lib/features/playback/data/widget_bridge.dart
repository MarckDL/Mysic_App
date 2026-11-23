import 'package:flutter/services.dart';

/// Lo que muestra el widget de la pantalla de inicio.
class WidgetState {
  const WidgetState({
    this.has = false,
    this.title,
    this.artist,
    this.art,
    this.playing = false,
    this.liked = false,
  });

  final bool has;
  final String? title;
  final String? artist;
  final String? art;
  final bool playing;
  final bool liked;

  Map<String, Object?> toMap() => {
    'has': has,
    'title': title,
    'artist': artist,
    'art': art,
    'playing': playing,
    'liked': liked,
  };

  @override
  bool operator ==(Object other) =>
      other is WidgetState &&
      other.has == has &&
      other.title == title &&
      other.artist == artist &&
      other.art == art &&
      other.playing == playing &&
      other.liked == liked;

  @override
  int get hashCode => Object.hash(has, title, artist, art, playing, liked);
}

/// Envía el estado al widget (lado nativo). Sin canal (pruebas, otras
/// plataformas) no hace nada.
class WidgetBridge {
  const WidgetBridge();

  static const _channel = MethodChannel('com.mysic/widget');

  Future<void> update(WidgetState state) async {
    try {
      await _channel.invokeMethod<void>('update', state.toMap());
    } on Object {
      // Sin widget en esta plataforma o sin motor (pruebas): el widget es un
      // complemento y nunca interrumpe la música.
    }
  }
}
