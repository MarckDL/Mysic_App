import 'package:flutter/services.dart';

class PlaybackSource {
  const PlaybackSource(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;
}

abstract interface class PlaybackSourceResolver {
  Future<void> warmUp();
  Future<PlaybackSource> resolve(
    String sourceId,
    String token, {
    bool refresh = false,
  });
  Future<void> prefetch(String sourceId, String token);
  void cancelPrefetch();

  /// Resuelve en segundo plano varias fuentes a la vista, sin prioridad sobre
  /// la reproducción.
  void warm(List<String> sourceIds);

  /// El dedo está sobre esta canción: se resuelve ya, con prioridad sobre el
  /// resto del trabajo en segundo plano y sin validar.
  void touch(String sourceId);

  Future<void> clear();
  Future<void> dispose();
}

/// El audio se resuelve en el teléfono (NewPipe Extractor): no hay servidor.
PlaybackSourceResolver createPlaybackSourceResolver() =>
    AndroidPlaybackSourceResolver();

class AndroidPlaybackSourceResolver implements PlaybackSourceResolver {
  AndroidPlaybackSourceResolver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.mysic.mysic/device_playback';
  final MethodChannel _channel;
  int _prefetchGeneration = 0;
  bool _disposed = false;

  @override
  Future<void> warmUp() async {
    if (_disposed) return;
    await _channel
        .invokeMethod<void>('warmUp')
        .timeout(const Duration(seconds: 10));
  }

  @override
  Future<PlaybackSource> resolve(
    String sourceId,
    String token, {
    bool refresh = false,
  }) async {
    _validate(sourceId, token);
    if (_disposed) throw StateError('Resolvedor cerrado');
    final response = await _channel
        .invokeMapMethod<String, Object?>('resolve', {
          'sourceId': sourceId,
          if (refresh) 'refresh': true,
        })
        .timeout(const Duration(seconds: 35));
    final rawUrl = response?['url'];
    if (rawUrl is! String) throw StateError('Fuente nativa inválida');
    final uri = Uri.tryParse(rawUrl);
    final isGoogleVideo =
        uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'googlevideo.com' ||
            uri.host.endsWith('.googlevideo.com'));
    // El servidor local del propio teléfono (solo bucle local y su ruta fija).
    final isLocalProxy =
        uri != null &&
        uri.scheme == 'http' &&
        uri.host == '127.0.0.1' &&
        uri.path.startsWith('/a/');
    if (uri == null || !(isGoogleVideo || isLocalProxy)) {
      throw StateError('Destino de audio no permitido');
    }
    final rawHeaders = response?['headers'];
    final headers = <String, String>{
      if (rawHeaders is Map)
        for (final entry in rawHeaders.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };
    return PlaybackSource(uri, headers: headers);
  }

  @override
  Future<void> prefetch(String sourceId, String token) async {
    _validate(sourceId, token);
    if (_disposed) return;
    final generation = ++_prefetchGeneration;
    await _channel
        .invokeMethod<void>('prefetch', {'sourceId': sourceId})
        .timeout(const Duration(seconds: 35));
    if (_disposed || generation != _prefetchGeneration) return;
  }

  @override
  void cancelPrefetch() {
    _prefetchGeneration++;
    if (!_disposed) {
      _channel.invokeMethod<void>('cancelPrefetch').catchError((Object _) {});
    }
  }

  @override
  void warm(List<String> sourceIds) {
    final ids = [
      for (final id in sourceIds)
        if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) id,
    ];
    if (_disposed || ids.isEmpty) return;
    _channel
        .invokeMethod<void>('warm', {'sourceIds': ids})
        .catchError((Object _) {});
  }

  @override
  void touch(String sourceId) {
    if (_disposed || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId)) return;
    _channel
        .invokeMethod<void>('touch', {'sourceId': sourceId})
        .catchError((Object _) {});
  }

  @override
  Future<void> clear() async {
    if (_disposed) return;
    cancelPrefetch();
    await _channel.invokeMethod<void>('clear');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    cancelPrefetch();
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // El motor nativo puede haber terminado antes que Flutter.
    } on MissingPluginException {
      // Los tests no registran el canal Android.
    }
  }

  void _validate(String sourceId, String token) {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId) || token.isEmpty) {
      throw StateError('Fuente inválida');
    }
  }
}
