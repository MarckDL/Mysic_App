import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_dio.dart';

class PlaybackSource {
  const PlaybackSource(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;
}

abstract interface class PlaybackSourceResolver {
  Future<void> warmUp();
  Future<PlaybackSource> resolve(String sourceId, String token);
  Future<void> prefetch(String sourceId, String token);
  void cancelPrefetch();
  Future<void> clear();
  Future<void> dispose();
}

PlaybackSourceResolver createPlaybackSourceResolver(String baseUrl) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidPlaybackSourceResolver();
  }
  return BackendPlaybackSourceResolver(baseUrl);
}

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
  Future<PlaybackSource> resolve(String sourceId, String token) async {
    _validate(sourceId, token);
    if (_disposed) throw StateError('Resolvedor cerrado');
    final response = await _channel
        .invokeMapMethod<String, Object?>('resolve', {'sourceId': sourceId})
        .timeout(const Duration(seconds: 35));
    final rawUrl = response?['url'];
    if (rawUrl is! String) throw StateError('Fuente nativa inválida');
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'googlevideo.com' ||
            uri.host.endsWith('.googlevideo.com'))) {
      throw StateError('Destino de audio no permitido');
    }
    return PlaybackSource(uri);
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

class BackendPlaybackSourceResolver implements PlaybackSourceResolver {
  BackendPlaybackSourceResolver(String baseUrl)
    : _base = validatedApiUri(baseUrl);

  final Uri _base;
  final Dio _client = Dio();
  CancelToken? _prefetchCancel;

  @override
  Future<void> warmUp() async {}

  @override
  Future<PlaybackSource> resolve(String sourceId, String token) async {
    _validate(sourceId, token);
    return PlaybackSource(
      _base.resolve('/api/v1/playback/audio/$sourceId'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<void> prefetch(String sourceId, String token) async {
    _validate(sourceId, token);
    cancelPrefetch();
    final cancel = CancelToken();
    _prefetchCancel = cancel;
    try {
      await _client.post<void>(
        _base.resolve('/api/v1/playback/prefetch/$sourceId').toString(),
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        cancelToken: cancel,
      );
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error)) rethrow;
    } finally {
      if (identical(_prefetchCancel, cancel)) _prefetchCancel = null;
    }
  }

  @override
  void cancelPrefetch() {
    _prefetchCancel?.cancel();
    _prefetchCancel = null;
  }

  @override
  Future<void> clear() async => cancelPrefetch();

  @override
  Future<void> dispose() async {
    cancelPrefetch();
    _client.close(force: true);
  }

  void _validate(String sourceId, String token) {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(sourceId) || token.isEmpty) {
      throw StateError('Fuente inválida');
    }
  }
}
