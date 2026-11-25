/// Qué es un atajo de Inicio (Limusic `Shortcut.Kind`): una colección de la
/// Biblioteca, una playlist o un álbum. Mysic añade la canción suelta, que al
/// tocarla suena con su radio.
enum ShortcutKind { collection, playlist, album, track }

/// Un atajo fijado en Inicio: lo que su tarjeta sabía al fijarlo.
class Shortcut {
  const Shortcut(
    this.kind,
    this.id,
    this.title, {
    this.subtitle,
    this.thumbnail,
  });

  /// Cuántos caben en Inicio (dos por fila, cuatro filas), como en Limusic.
  static const max = 8;

  // Las colecciones de la Biblioteca que se pueden fijar.
  static const liked = 'liked';
  static const downloads = 'downloads';
  static const mostPlayed = 'mostPlayed';
  static const artists = 'artists';
  static const recents = 'recents';

  final ShortcutKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? thumbnail;

  bool sameAs(Shortcut other) => kind == other.kind && id == other.id;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': ?subtitle,
    'thumbnail': ?thumbnail,
  };

  /// El atajo de un JSON guardado, o null si no se entiende.
  static Shortcut? fromJson(Object? data) {
    if (data is! Map || data['id'] is! String || data['title'] is! String) {
      return null;
    }
    final kind = ShortcutKind.values
        .where((kind) => kind.name == data['kind'])
        .firstOrNull;
    if (kind == null || (data['id'] as String).isEmpty) return null;
    return Shortcut(
      kind,
      data['id'] as String,
      data['title'] as String,
      subtitle: data['subtitle'] is String ? data['subtitle'] as String : null,
      thumbnail: data['thumbnail'] is String
          ? data['thumbnail'] as String
          : null,
    );
  }
}

/// Cómo quiere el usuario su Inicio (Limusic `HomeLayout`, lo que Mysic
/// tiene): qué partes se ven.
class HomeLayout {
  const HomeLayout({
    this.chips = true,
    this.backdrop = true,
    this.shortcuts = true,
    this.dial = true,
    this.radio = true,
  });

  /// El bloque de radios en directo, bajo el carrusel.
  final bool radio;

  /// La fila de ambientes (Relax, Dormir…).
  final bool chips;

  /// La carátula que suena, desenfocada, tras la cabecera.
  final bool backdrop;

  /// La sección de atajos.
  final bool shortcuts;

  /// El collage «Accesos directos».
  final bool dial;

  HomeLayout copyWith({
    bool? chips,
    bool? backdrop,
    bool? shortcuts,
    bool? dial,
    bool? radio,
  }) => HomeLayout(
    radio: radio ?? this.radio,
    chips: chips ?? this.chips,
    backdrop: backdrop ?? this.backdrop,
    shortcuts: shortcuts ?? this.shortcuts,
    dial: dial ?? this.dial,
  );

  Map<String, dynamic> toJson() => {
    'chips': chips,
    'backdrop': backdrop,
    'shortcuts': shortcuts,
    'dial': dial,
    'radio': radio,
  };

  factory HomeLayout.fromJson(Map<String, dynamic>? data) => HomeLayout(
    chips: data?['chips'] != false,
    backdrop: data?['backdrop'] != false,
    shortcuts: data?['shortcuts'] != false,
    dial: data?['dial'] != false,
    radio: data?['radio'] != false,
  );
}
