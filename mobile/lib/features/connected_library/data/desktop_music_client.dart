import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../domain/music_mode.dart';
import '../../playback/domain/track_audio_engine.dart';
import 'original_music_catalog.dart';

class DesktopSessionStore {
  const DesktopSessionStore(this.uid);
  final String uid;
  static const _channel = MethodChannel('com.mysic/desktop_session');
  Future<String?> read() => _channel.invokeMethod<String>('read', {'uid': uid});
  Future<void> write(String? value) =>
      _channel.invokeMethod<void>('write', {'uid': uid, 'value': value});
}

class _DesktopSession {
  _DesktopSession(this.id, this.name, this.value, this.generation);
  final String id, name, value, generation;

  static final _safeValue = RegExp(r'^[A-Za-z0-9_.-]{1,4096}$');
  static _DesktopSession? from(Map json) {
    final id = json['id'],
        name = json['name'],
        value = json['session'],
        generation = json['generation'];
    if (id is! String ||
        !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 200 ||
        value is! String ||
        !_safeValue.hasMatch(value) ||
        generation is! String ||
        !RegExp(r'^desktop-[A-Za-z0-9_-]{24}$').hasMatch(generation)) {
      return null;
    }
    return _DesktopSession(id, name.trim(), value, generation);
  }

  String encode({bool useChannel = false}) => jsonEncode({
    if (useChannel) 'useChannel': true,
    'id': id,
    'name': name,
    'session': value,
    'generation': generation,
  });
  MusicConnection connection([
    MusicLinkStatus status = MusicLinkStatus.linked,
  ]) => MusicConnection(
    status: status,
    provider: 'mysicDesktop',
    personalization: status == MusicLinkStatus.linked
        ? 'verified'
        : 'unverified',
    account: MusicAccount(id, name, false),
    generation: generation,
    capabilities: status == MusicLinkStatus.linked
        ? const {
            'home',
            'liked',
            'albums',
            'album',
            'playlists',
            'playlist',
            'artists',
            'artist',
            'search',
            'playback',
          }
        : const {},
  );
}

/// Uses the same first-party service and normal Mysic login as the released desktop client.
class DesktopMusicClient {
  DesktopMusicClient(this._store, this._owns, {Dio? dio})
    : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: 'https://myslc.duckdns.org/api/',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: false,
      validateStatus: (status) => status != null,
      headers: {'Accept': 'application/json'},
    );
  }
  final DesktopSessionStore _store;
  final bool Function() _owns;
  final Dio _dio;
  _DesktopSession? _session;
  MusicPage? _firstHome;
  ({_DesktopSession session, bool remember})? _pending;
  bool _remembered = false, _useChannel = false;
  bool get hasPendingLink => _pending != null;
  String? get accountName => _session?.name;
  void cancelPending() => _pending = null;
  CancelToken _audioRequests = CancelToken();
  DateTime? _verified;
  bool _restored = false, _closed = false;
  bool get hasSession => _session != null;
  bool get _active => !_closed && _owns();
  void _checkOwner() {
    if (!_active) throw const ApiFailure('Cambió la cuenta de Mysic.');
  }

  Future<Response<dynamic>> _request(
    String path, {
    String? session,
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    _checkOwner();
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(
          method: data == null ? 'GET' : 'POST',
          headers: {
            if (session != null)
              HttpHeaders.cookieHeader: 'mysic_session=$session',
          },
        ),
      );
      _checkOwner();
      final status = response.statusCode!;
      if (status == 401 && path == 'auth/login') {
        throw const ApiFailure(
          'Mysic de escritorio rechazó el correo o la contraseña.',
          code: 'DESKTOP_LOGIN',
        );
      }
      if (status == 401) {
        throw const ApiFailure(
          'La sesión de Mysic de escritorio venció. Vuelve a iniciar sesión.',
          code: 'DESKTOP_EXPIRED',
        );
      }
      if (status == 409) {
        throw const ApiFailure(
          'Abre Mysic de escritorio con esa cuenta y comprueba su vínculo de YouTube Music.',
          code: 'DESKTOP_MUSIC_LINK',
        );
      }
      if (status == 410) {
        throw const ApiFailure(
          'Actualiza la lista para seguir.',
          code: 'CURSOR_EXPIRED',
        );
      }
      if (status == 404 || status == 405) {
        throw ApiFailure(
          'Mysic de escritorio no ofrece esta sección.',
          statusCode: status,
          code: 'DESKTOP_ROUTE',
        );
      }
      if (status == 429) {
        throw const ApiFailure(
          'Mysic de escritorio recibió demasiadas consultas. Reintenta más tarde.',
          code: 'TOO_MANY_REQUESTS',
        );
      }
      if (status < 200 ||
          status >= 300 ||
          response.data is! Map<String, dynamic>) {
        throw const ApiFailure(
          'Mysic de escritorio no pudo entregar los datos. Reintenta en unos momentos.',
          code: 'DESKTOP_SERVICE',
        );
      }
      return response;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const ApiFailure(
        'No se pudo conectar con el servidor de Mysic de escritorio.',
        code: 'DESKTOP_NETWORK',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    _DesktopSession session,
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async =>
      (await _request(
            'youtube/$path',
            session: session.value,
            query: query,
            cancelToken: cancelToken,
          )).data
          as Map<String, dynamic>;

  Future<MusicPage> _verify(_DesktopSession session) async {
    final account = await _get(session, 'account');
    if (account['connected'] != true ||
        account['personalized'] != true ||
        account['health'] == 'expired') {
      throw const ApiFailure(
        'Esta cuenta de Mysic de escritorio aún necesita vincular YouTube Music. Comprueba el Inicio musical en escritorio.',
        code: 'DESKTOP_MUSIC_LINK',
      );
    }
    final home = OriginalMusicCatalog.homePage(
      await _get(session, 'home'),
      first: true,
    );
    return home;
  }

  Future<MusicConnection> login(
    String email,
    String password, {
    required bool remember,
  }) async {
    _pending = null;
    final response = await _request(
      'auth/login',
      data: {'email': email.trim(), 'password': password, 'remember': remember},
    );
    final user = response.data['user'];
    String? value;
    for (final header
        in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      try {
        final cookie = Cookie.fromSetCookieValue(header);
        if (cookie.name == 'mysic_session' &&
            cookie.httpOnly &&
            cookie.secure &&
            (cookie.domain == null || cookie.domain == 'myslc.duckdns.org') &&
            cookie.path == '/') {
          value = cookie.value;
        }
      } on FormatException {
        continue;
      } on HttpException {
        continue;
      }
    }
    final random = Random.secure();
    final generation =
        'desktop-${base64Url.encode(List<int>.generate(18, (_) => random.nextInt(256)))}';
    final session = user is Map
        ? _DesktopSession.from({
            'id': user['id'],
            'name': user['username'],
            'session': value,
            'generation': generation,
          })
        : null;
    if (session == null) {
      throw const ApiFailure(
        'Mysic de escritorio no pudo establecer una sesión segura.',
        code: 'DESKTOP_SESSION',
      );
    }
    _pending = (session: session, remember: remember);
    return finishLink();
  }

  Future<MusicConnection> finishLink() async {
    final pending = _pending;
    if (pending == null) {
      throw const ApiFailure('Vuelve a iniciar la vinculación.');
    }
    final (:session, :remember) = pending;
    late final MusicPage home;
    try {
      home = await _verify(session);
    } on ApiFailure catch (error) {
      if (error.code == 'DESKTOP_EXPIRED' &&
          identical(_pending?.session, session)) {
        cancelPending();
      }
      rethrow;
    }
    if (!identical(_pending?.session, session)) {
      throw const ApiFailure('Cambió la vinculación.');
    }
    _checkOwner();
    try {
      await _store.write(remember ? session.encode() : null);
    } on PlatformException {
      throw const ApiFailure(
        'Android no pudo guardar la sesión en este dispositivo.',
      );
    }
    _checkOwner();
    _cancelAudio();
    _session = session;
    _pending = null;
    _remembered = remember;
    _useChannel = false;
    _firstHome = home;
    _restored = true;
    _verified = DateTime.now();
    return session.connection();
  }

  Future<void> preferChannel(bool enabled) async {
    _checkOwner();
    final session = _session;
    if (session == null || _useChannel == enabled) return;
    if (_remembered) await _store.write(session.encode(useChannel: enabled));
    _checkOwner();
    _useChannel = enabled;
    _cancelAudio();
  }

  Future<MusicConnection?> connection({bool includeInactive = false}) async {
    if (!_restored) {
      final stored = await _store.read();
      _checkOwner();
      if (stored != null) {
        try {
          final data = jsonDecode(stored);
          if (data is Map) {
            _session = _DesktopSession.from(data);
            _remembered = _session != null;
            _useChannel = _remembered && data['useChannel'] == true;
          }
        } on FormatException {
          _session = null;
        }
      }
      _restored = true;
    }
    final session = _session;
    if (session == null || (_useChannel && !includeInactive)) return null;
    if (_verified != null &&
        DateTime.now().difference(_verified!) < const Duration(minutes: 2)) {
      return session.connection();
    }
    try {
      final home = await _verify(session);
      _checkOwner();
      if (!identical(_session, session)) {
        throw const ApiFailure('Cambió la conexión.');
      }
      _firstHome = home;
      _verified = DateTime.now();
      return session.connection();
    } on ApiFailure catch (e) {
      if (e.code == 'DESKTOP_EXPIRED') {
        return session.connection(MusicLinkStatus.expired);
      }
      if (e.code == 'DESKTOP_MUSIC_LINK') {
        return session.connection(MusicLinkStatus.unavailable);
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _checkOwner();
    await _store.write(null);
    cancelPending();
    _remembered = false;
    _useChannel = false;
    _cancelAudio();
    _session = null;
    _verified = null;
    _firstHome = null;
    _restored = true;
  }

  /// Anonymous, song-only catalog. This endpoint never receives an account credential.
  Future<MusicPage> publicSongs(String query, CancelToken? cancelToken) async {
    final response = await _request(
      'youtube/search',
      query: {'q': query, 'type': 'song'},
      cancelToken: cancelToken,
    );
    final data = response.data as Map<String, dynamic>;
    if (data['type'] != 'song' || data['items'] is! List) {
      throw const ApiFailure(
        'El catálogo musical no está disponible.',
        code: 'MUSIC_SEARCH_UNAVAILABLE',
      );
    }
    return MusicPage(
      OriginalMusicCatalog.rows(data['items'], 'song'),
      null,
      null,
      0,
    );
  }

  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final session = _session;
    if (session == null || _useChannel || session.generation != generation) {
      throw const ApiFailure('Cambió la cuenta de escritorio.');
    }
    if (playlistId != null && !OriginalMusicCatalog.validId(playlistId)) {
      throw const ApiFailure('El identificador musical no es válido.');
    }
    Future<Map<String, dynamic>> get(
      String path, [
      Map<String, dynamic>? params,
    ]) => _get(session, path, query: params, cancelToken: cancelToken);
    try {
      if (surface == MusicSurface.home) {
        if (cursor == null && _firstHome != null) {
          final first = _firstHome!;
          _firstHome = null;
          return first;
        }
        return OriginalMusicCatalog.homePage(
          await get(cursor == null ? 'home' : 'home/more', {
            if (cursor != null) 'token': cursor,
          }),
          first: cursor == null,
        );
      }
      final (path, field, kind) = switch (surface) {
        MusicSurface.liked => ('library/liked-songs', 'items', 'song'),
        MusicSurface.playlists => ('library/playlists', 'items', 'playlist'),
        MusicSurface.albums => ('library/albums', 'items', 'album'),
        MusicSurface.artists => ('library/subscriptions', 'items', 'artist'),
        MusicSurface.search => ('search', 'items', 'song'),
        MusicSurface.playlist when playlistId != null => (
          'playlist/$playlistId',
          'songs',
          'song',
        ),
        MusicSurface.album when playlistId != null => (
          'album/$playlistId',
          'tracks',
          'song',
        ),
        MusicSurface.artist when playlistId != null => (
          'artist/$playlistId/songs',
          'songs',
          'song',
        ),
        _ => throw const ApiFailure(
          'Esta sección no está disponible en Mysic de escritorio.',
        ),
      };
      late final Map<String, dynamic> response;
      try {
        response = await get(path, {
          if (cursor != null) 'cursor': cursor,
          if (surface == MusicSurface.search) ...{'q': query, 'type': 'song'},
        });
      } on ApiFailure catch (error) {
        final legacyField = switch (surface) {
          MusicSurface.liked => 'likedSongs',
          MusicSurface.albums => 'albums',
          MusicSurface.artists => 'subscriptions',
          MusicSurface.playlists => 'playlists',
          _ => null,
        };
        if (error.code != 'DESKTOP_ROUTE' ||
            legacyField == null ||
            cursor != null) {
          rethrow;
        }
        final library = await get('library', {
          if (surface == MusicSurface.playlists) 'fresh': '1',
        });
        return MusicPage(
          OriginalMusicCatalog.rows(library[legacyField], kind),
          null,
          null,
          0,
        );
      }
      final title = response['title'] ?? response['name'];
      return MusicPage(
        OriginalMusicCatalog.rows(response[field], kind),
        OriginalMusicCatalog.cursor(response),
        null,
        0,
        title is String ? title : null,
      );
    } on ApiFailure catch (e) {
      if (e.code == 'DESKTOP_EXPIRED' || e.code == 'DESKTOP_MUSIC_LINK') {
        _verified = null;
        _firstHome = null;
        _cancelAudio();
      }
      rethrow;
    }
  }

  void _cancelAudio() {
    _audioRequests.cancel();
    _audioRequests = CancelToken();
  }

  // The native decoder receives audio bytes. Only this HTTPS client sees the desktop session.
  TrackAudioReader audioReader(String generation, String id) =>
      (start, end) async {
        final session = _session;
        _checkOwner();
        if (session == null ||
            _useChannel ||
            generation != session.generation ||
            !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
            (start != null && start < 0) ||
            (end != null && end <= (start ?? 0))) {
          throw const PlaybackSourceFailure();
        }
        final partial = (start ?? 0) > 0 || end != null;
        late final Response<ResponseBody> response;
        try {
          response = await _dio.get<ResponseBody>(
            'youtube/stream/$id',
            cancelToken: _audioRequests,
            options: Options(
              responseType: ResponseType.stream,
              headers: {
                'Accept': 'audio/*',
                'Cookie': 'mysic_session=${session.value}',
                if (partial)
                  'Range': 'bytes=${start ?? 0}-${end == null ? '' : end - 1}',
              },
            ),
          );
        } on DioException {
          throw const PlaybackSourceFailure();
        }
        final body = response.data;
        final status = response.statusCode;
        final mime =
            response.headers
                .value('content-type')
                ?.split(';')
                .first
                .trim()
                .toLowerCase() ??
            '';
        final headerLength = int.tryParse(
          response.headers.value('content-length') ?? '',
        );
        final range = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+|\*)$',
        ).firstMatch(response.headers.value('content-range') ?? '');
        final offset = range == null ? null : int.tryParse(range[1]!);
        final last = range == null ? null : int.tryParse(range[2]!);
        final rangedLength = offset != null && last != null
            ? last - offset + 1
            : null;
        final length = headerLength ?? rangedLength;
        if (!_active ||
            _useChannel ||
            !identical(_session, session) ||
            body == null ||
            (status != 200 && status != 206) ||
            !(mime.startsWith('audio/') ||
                mime == 'video/mp4' ||
                mime == 'video/webm' ||
                mime == 'application/octet-stream') ||
            (status == 206 &&
                (range == null ||
                    offset != (start ?? 0) ||
                    rangedLength == null ||
                    rangedLength <= 0 ||
                    rangedLength != length)) ||
            (partial && (start ?? 0) > 0 && status != 206)) {
          if (body != null) await body.stream.listen(null).cancel();
          throw const PlaybackSourceFailure();
        }
        return TrackAudioRange(
          body.stream,
          mime,
          length: length,
          total: range == null ? length : int.tryParse(range[3]!),
          offset: offset,
          acceptsRanges:
              status == 206 ||
              response.headers.value('accept-ranges') == 'bytes',
        );
      };

  void close() {
    _cancelAudio();
    _closed = true;
    cancelPending();
    _session = null;
    _firstHome = null;
    _dio.close(force: true);
  }
}
