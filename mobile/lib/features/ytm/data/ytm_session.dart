import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// La sesión de YouTube Music del teléfono: la cookie que dejó el inicio de
/// sesión, guardada cifrada por el lado nativo.
class YtmSession {
  const YtmSession(this.cookie);

  static const _channel = MethodChannel('com.mysic/ytm');

  final String cookie;

  /// Abre la ventana de inicio de sesión. Devuelve la sesión nueva, o null si
  /// se cerró sin entrar.
  static Future<YtmSession?> login() async {
    final cookie = await _channel.invokeMethod<String>('login');
    debugPrint(
      'ytm_login result=${cookie == null ? 'null' : 'len=${cookie.length} sapisid=${_hasSapisid(cookie)}'}',
    );
    return cookie == null || !_hasSapisid(cookie) ? null : YtmSession(cookie);
  }

  /// La sesión guardada, si la hay.
  static Future<YtmSession?> load() async {
    try {
      final cookie = await _channel.invokeMethod<String>('load');
      return cookie == null || !_hasSapisid(cookie) ? null : YtmSession(cookie);
    } on Object {
      return null;
    }
  }

  /// Pide al lado nativo las cookies que YouTube rotó para la misma cuenta
  /// (las guarda cifradas). Devuelve la sesión nueva o null si no hay nada más
  /// fresco.
  static Future<YtmSession?> refresh() async {
    try {
      final cookie = await _channel.invokeMethod<String>('refresh');
      return cookie == null || !_hasSapisid(cookie) ? null : YtmSession(cookie);
    } on Object {
      return null;
    }
  }

  /// Cierra la sesión: borra la cookie guardada y la del navegador.
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on Object {
      // Sin canal nativo (pruebas): no hay nada que borrar.
    }
  }

  static bool _hasSapisid(String cookie) => _cookie(cookie, 'SAPISID') != null;

  static String? _cookie(String cookie, String name) {
    for (final part in cookie.split(';')) {
      final index = part.indexOf('=');
      if (index > 0 && part.substring(0, index).trim() == name) {
        final value = part.substring(index + 1).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// El valor `SAPISID` (o su variante segura), que firma cada petición.
  String? get sapisid =>
      _cookie(cookie, 'SAPISID') ?? _cookie(cookie, '__Secure-3PAPISID');

  /// Identificador estable de la cuenta en este teléfono. Se deriva de la
  /// cookie de sesión sin guardarla en claro: el mismo inicio de sesión da
  /// siempre el mismo identificador, y otra cuenta da otro.
  String get uid => sha256
      .convert(utf8.encode(_cookie(cookie, 'SAPISID') ?? cookie))
      .toString()
      .substring(0, 24);

  /// `Authorization` de YouTube Music: SHA-1 de "tiempo SAPISID origen".
  String authorization(String origin, {DateTime? now}) {
    final seconds = ((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000)
        .toString();
    final hash = sha1.convert(utf8.encode('$seconds ${sapisid ?? ''} $origin'));
    return 'SAPISIDHASH ${seconds}_$hash';
  }
}
