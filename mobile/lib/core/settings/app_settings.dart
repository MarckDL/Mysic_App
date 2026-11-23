import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../network/offline_mode.dart';

/// Un ajuste de sí o no guardado en un archivo pequeño, para que sobreviva al
/// cierre de la app. Arranca con [initial] y se corrige en cuanto se lee.
abstract class FileFlag extends Notifier<bool> {
  String get fileName;
  bool get initial;

  @override
  bool build() {
    unawaited(_load());
    return initial;
  }

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}$fileName');
    } on Object {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final text = (await file.readAsString()).trim();
      if (ref.mounted && (text == '0' || text == '1')) state = text == '1';
    } on Object {
      // Sin archivo legible se queda el valor por defecto.
    }
  }

  void set(bool value) {
    state = value;
    unawaited(() async {
      try {
        await (await _file())?.writeAsString(value ? '1' : '0');
      } on Object {
        // El cambio vale para esta sesión aunque no se pueda guardar.
      }
    }());
  }
}

/// "Adaptar colores a la carátula" (Limusic: activado por defecto).
final adaptCoverColorProvider = NotifierProvider<AdaptCoverColor, bool>(
  AdaptCoverColor.new,
);

class AdaptCoverColor extends FileFlag {
  @override
  String get fileName => 'cover_color.txt';
  @override
  bool get initial => true;
}

/// "Reducir efectos": sin desenfoques ni fondos de carátula, para teléfonos
/// modestos o para ahorrar batería. Desactivado por defecto.
final reduceEffectsProvider = NotifierProvider<ReduceEffects, bool>(
  ReduceEffects.new,
);

class ReduceEffects extends FileFlag {
  @override
  String get fileName => 'reduce_effects.txt';
  @override
  bool get initial => false;
}

/// "Guardar el audio escuchado": repetir una canción no vuelve a descargarla.
/// Desactivado por defecto: ocupa espacio en el teléfono.
final keepAudioProvider = NotifierProvider<KeepAudio, bool>(KeepAudio.new);

class KeepAudio extends FileFlag {
  @override
  String get fileName => 'keep_audio.txt';
  @override
  bool get initial => false;
}

/// "Solo canciones descargadas": la app no usa internet ni datos y reproduce
/// únicamente lo descargado. Desactivado por defecto. El valor se copia a
/// [OfflineMode], que consultan los clientes de red.
final offlineOnlyProvider = NotifierProvider<OfflineOnly, bool>(
  OfflineOnly.new,
);

class OfflineOnly extends FileFlag {
  @override
  String get fileName => 'offline_only.txt';
  @override
  bool get initial => false;

  @override
  bool build() {
    final value = super.build();
    // main() ya restauró el valor guardado en OfflineMode; esto lo mantiene al
    // día cuando el usuario lo cambia.
    listenSelf((_, next) => OfflineMode.instance.manual = next);
    return value;
  }
}

/// "Resolver directo con YouTube": una sola petición `player` desde el teléfono
/// (el motor lo lee del archivo). Experimental; NewPipe queda de respaldo.
final fastResolveProvider = NotifierProvider<FastResolve, bool>(
  FastResolve.new,
);

class FastResolve extends FileFlag {
  @override
  String get fileName => 'fast_resolve.txt';
  @override
  bool get initial => true;
}

/// "Primer tramo en memoria": servidor local que responde el inicio de la
/// canción sin red. Experimental.
final headProxyProvider = NotifierProvider<HeadProxy, bool>(HeadProxy.new);

class HeadProxy extends FileFlag {
  @override
  String get fileName => 'head_proxy.txt';
  @override
  bool get initial => true;
}

/// Lleva "Reducir efectos" por el árbol para los widgets de dibujo que no
/// leen proveedores. Sin este ancestro (pruebas, vistas sueltas) los efectos
/// se muestran completos.
class EffectsScope extends InheritedWidget {
  const EffectsScope({super.key, required this.reduced, required super.child});

  final bool reduced;

  static bool reducedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EffectsScope>()?.reduced ??
      false;

  @override
  bool updateShouldNotify(EffectsScope oldWidget) =>
      reduced != oldWidget.reduced;
}
