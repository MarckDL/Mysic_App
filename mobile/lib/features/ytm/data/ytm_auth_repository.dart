import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/offline_mode.dart';
import '../../authentication/domain/auth_repository.dart';
import 'ytm_client.dart';
import 'ytm_session.dart';

/// Nombre y foto de la cuenta, guardados junto a la sesión para abrir la app
/// sin esperar a la red.
class YtmAccountCache {
  const YtmAccountCache({this.path});

  /// Para las pruebas: un archivo concreto en vez del directorio de la app.
  final String? path;

  Future<File> _file() async => File(
    path ?? '${(await getApplicationSupportDirectory()).path}/ytm_account.json',
  );

  Future<YtmAccount?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> || data['name'] is! String) return null;
      return YtmAccount(
        name: data['name'] as String,
        handle: data['handle'] as String?,
        photoUrl: data['photoUrl'] as String?,
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(YtmAccount account) async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({
          'name': account.name,
          'handle': account.handle,
          'photoUrl': account.photoUrl,
        }),
      );
    } on Object {
      // Sin disco: la próxima vez se vuelve a pedir a la red.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object {
      // Nada que borrar.
    }
  }
}

/// La identidad de la app es la sesión de YouTube Music del teléfono: no hay
/// otra cuenta ni servidor de por medio.
class YtmAuthRepository implements AuthRepository {
  YtmAuthRepository({
    Future<YtmSession?> Function()? load,
    Future<YtmSession?> Function()? login,
    Future<void> Function()? clear,
    YtmClient Function(YtmSession)? clientFor,
    this.cache = const YtmAccountCache(),
  }) : _load = load ?? YtmSession.load,
       _login = login ?? YtmSession.login,
       _clear = clear ?? YtmSession.clear,
       _clientFor = clientFor ?? YtmClient.new;

  final Future<YtmSession?> Function() _load;
  final Future<YtmSession?> Function() _login;
  final Future<void> Function() _clear;
  final YtmClient Function(YtmSession) _clientFor;
  final YtmAccountCache cache;

  final _changes = StreamController<AuthUser?>.broadcast();
  YtmSession? _session;
  YtmAccount? _account;
  AuthUser? _user;
  Future<void>? _restored;

  /// La sesión con la que se hablan YouTube Music; null sin iniciar sesión.
  YtmSession? get session => _session;
  YtmAccount? get account => _account;

  /// Identificador estable de la cuenta: sale del nombre del canal, no de la
  /// cookie, que YouTube renueva al volver a iniciar sesión.
  static String uidFor(YtmAccount account) => sha256
      .convert(utf8.encode('ytm:${account.handle ?? account.name}'))
      .toString()
      .substring(0, 24);

  Future<void> _restore() => _restored ??= () async {
    final session = await _load();
    final cached = session == null ? null : await cache.read();
    _session = session;
    _account = cached;
    // Con una sesión pero sin datos guardados, la cuenta se completa en la
    // verificación; mientras tanto el identificador sale de la cookie.
    _user = session == null
        ? null
        : AuthUser(
            uid: cached == null ? session.uid : uidFor(cached),
            displayName: cached?.name,
          );
  }();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    await _restore();
    yield _user;
    yield* _changes.stream;
  }

  /// Comprueba la sesión con YouTube Music y renueva la cuenta guardada. Un
  /// rechazo cierra la sesión; un fallo de red solo se informa.
  Future<YtmAccount> verify() async {
    await _restore();
    final session = _session;
    if (session == null) {
      throw const AuthFailure('Inicia sesión en YouTube Music.');
    }
    // Con «solo canciones descargadas» no sale ninguna petición: no es un
    // rechazo de YouTube, así que no se toca la sesión; la app entra con lo que
    // sabe de la cuenta.
    if (OfflineMode.instance.active) {
      throw const AuthFailure(
        'Está activado «Solo canciones descargadas».',
        unreachable: true,
      );
    }
    final client = _clientFor(session);
    try {
      final account = await client.account();
      _account = account;
      await cache.write(account);
      final user = AuthUser(uid: uidFor(account), displayName: account.name);
      if (user.uid != _user?.uid) {
        _user = user;
        _changes.add(user);
      }
      return account;
    } on ApiFailure catch (error) {
      debugPrint('ytm_verify_failed code=${error.code}');
      if (error.code == 'MUSIC_ACCESS_DENIED') {
        await signOut();
        throw const AuthFailure('Tu sesión de YouTube Music terminó.');
      }
      throw const AuthFailure(
        'No se pudo comprobar tu sesión de YouTube Music.',
        unreachable: true,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<void> signIn() async {
    await _restore();
    final session = await _login();
    if (session == null) {
      throw const AuthFailure('Inicio de sesión cancelado.', cancelled: true);
    }
    _session = session;
    _account = null;
    await cache.clear();
    // El nombre del canal da el identificador estable; si la red falla, la
    // verificación que sigue al entrar lo completa.
    final client = _clientFor(session);
    try {
      final account = await client.account();
      _account = account;
      await cache.write(account);
    } on Object catch (error) {
      debugPrint('ytm_signin_account_failed $error');
      // Se sigue con el identificador provisional de la cookie.
    } finally {
      client.close();
    }
    final account = _account;
    _user = AuthUser(
      uid: account == null ? session.uid : uidFor(account),
      displayName: account?.name,
    );
    _changes.add(_user);
  }

  @override
  Future<void> signOut() async {
    // Si aún se está restaurando la sesión guardada, esperar: de lo contrario
    // la restauración volvería a ponerla justo después de cerrarla.
    await _restore();
    _session = null;
    _account = null;
    _user = null;
    await _clear();
    await cache.clear();
    _changes.add(null);
  }

  /// Ya no hay servidor propio que pida un token.
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  void dispose() => _changes.close();
}
