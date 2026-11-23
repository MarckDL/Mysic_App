import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../connected_library/domain/music_mode.dart';
import 'ytm_client.dart';

/// Las canciones con Me gusta de la cuenta, para pintar el corazón sin pedir
/// nada a la red cada vez. Se guarda en el teléfono (el widget y el
/// reproductor abren con el corazón ya correcto) y se refresca desde YouTube
/// Music. Marcar o desmarcar cambia al instante y se confirma en segundo
/// plano; si falla, se deshace.
class LikedTracks extends ChangeNotifier {
  LikedTracks(this._client, {this.path});

  final YtmClient _client;

  /// Para las pruebas: un archivo concreto en vez del directorio de la app.
  final String? path;

  final _ids = <String>{};
  bool _loading = false;
  bool _disposed = false;

  bool isLiked(String videoId) => _ids.contains(videoId);

  Future<File> _file() async => File(
    path ?? '${(await getApplicationSupportDirectory()).path}/liked_ids.json',
  );

  /// Cuánto vale lo guardado antes de volver a pedirlo a YouTube Music.
  static const freshFor = Duration(minutes: 30);

  /// Lee lo guardado y, si tiene más de [freshFor], lo refresca desde YouTube
  /// Music (hasta 1000 canciones: diez páginas). Así abrir la app no repite
  /// diez peticiones cada vez.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      var recent = false;
      try {
        final file = await _file();
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString());
          if (data is List && !_disposed) {
            _ids.addAll(data.whereType<String>());
            notifyListeners();
            recent =
                DateTime.now().difference((await file.stat()).modified) <
                freshFor;
          }
        }
      } on Object {
        // Sin lo guardado se espera a la red.
      }
      if (recent) return;
      final fresh = <String>{};
      String? cursor;
      for (var round = 0; round < 10; round++) {
        final page = await _client.pageJson(MusicSurface.liked, cursor: cursor);
        for (final item in (page['items'] as List).cast<Map>()) {
          if (item['kind'] == 'track' && item['id'] is String) {
            fresh.add(item['id'] as String);
          }
        }
        cursor = page['nextCursor'] as String?;
        if (cursor == null) break;
      }
      if (_disposed) return;
      _ids
        ..clear()
        ..addAll(fresh);
      notifyListeners();
      await _save();
    } on Object {
      // Sin red se sigue con lo guardado.
    } finally {
      _loading = false;
    }
  }

  Future<void> _save() async {
    try {
      await (await _file()).writeAsString(jsonEncode(_ids.toList()));
    } on Object {
      // La próxima vez se vuelve a pedir.
    }
  }

  /// Cambia el Me gusta de [videoId]. Devuelve el estado final.
  Future<bool> toggle(String videoId) async {
    final liked = !_ids.contains(videoId);
    liked ? _ids.add(videoId) : _ids.remove(videoId);
    notifyListeners();
    try {
      await _client.rate(videoId, liked: liked);
      unawaited(_save());
      return liked;
    } on Object {
      // No quedó guardado en YouTube: se deshace.
      liked ? _ids.remove(videoId) : _ids.add(videoId);
      if (!_disposed) notifyListeners();
      return !liked;
    }
  }

  /// Un No me gusta quita el Me gusta en YouTube: se refleja aquí.
  void forget(String videoId) {
    if (_ids.remove(videoId)) {
      if (!_disposed) notifyListeners();
      unawaited(_save());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
