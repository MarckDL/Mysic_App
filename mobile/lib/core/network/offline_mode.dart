import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Se intentó usar la red con el modo «solo canciones descargadas» activo.
class OfflineFailure implements Exception {
  const OfflineFailure();

  @override
  String toString() => 'Modo sin conexión: solo canciones descargadas.';
}

/// Modo «solo canciones descargadas»: mientras está activo la app no abre
/// ninguna conexión (ni catálogo, ni portadas, ni letras, ni audio) y solo
/// reproduce lo que hay en el teléfono.
///
/// Se activa solo con el ajuste manual (que se guarda). Sin él, la app no se
/// encierra por falta de internet: lo descargado se ve y suena desde
/// Biblioteca → Descargas, con o sin conexión.
class OfflineMode extends ChangeNotifier {
  OfflineMode._();

  static final instance = OfflineMode._();

  bool _manual = false;

  /// El usuario eligió «solo canciones descargadas» en Ajustes.
  bool get manual => _manual;

  /// Si la app no debe usar la red ahora mismo.
  bool get active => _manual;

  set manual(bool value) {
    if (_manual == value) return;
    _manual = value;
    notifyListeners();
  }

  /// Lee el ajuste guardado antes de arrancar la app, para que ninguna
  /// conexión se abra mientras «solo canciones descargadas» está activo.
  Future<void> restoreManual() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}offline_only.txt');
      if (await file.exists()) {
        manual = (await file.readAsString()).trim() == '1';
      }
    } on Object {
      // Sin archivo legible el modo queda apagado.
    }
  }

  /// Si hay internet de verdad: resuelve un nombre y abre una conexión TCP al
  /// puerto 443 (un wifi sin salida a veces resuelve desde la caché del
  /// sistema, pero no conecta). Cualquier fallo cuenta como sin internet.
  static Future<bool> hasInternet({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // Las pruebas no deben salir a la red real.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      final addresses = await InternetAddress.lookup(
        'music.youtube.com',
      ).timeout(timeout);
      if (addresses.isEmpty) return false;
      final socket = await Socket.connect(
        addresses.first,
        443,
        timeout: timeout,
      );
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  /// Lanza [OfflineFailure] si no se puede usar la red.
  static void ensureOnline() {
    if (instance.active) throw const OfflineFailure();
  }

  /// Interceptor de Dio: con el modo activo la petición ni sale.
  static final dioGuard = InterceptorsWrapper(
    onRequest: (options, handler) {
      if (instance.active) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const OfflineFailure(),
            message: 'Modo sin conexión',
          ),
          true,
        );
      } else {
        handler.next(options);
      }
    },
  );

  @visibleForTesting
  void reset() {
    _manual = false;
    notifyListeners();
  }
}
