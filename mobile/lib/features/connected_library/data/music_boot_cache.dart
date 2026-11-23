import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Lo último que el servidor respondió sobre la conexión musical y la primera
/// página de Inicio de una cuenta, tal como llegó (JSON). Sirve para pintar la
/// app al abrirla mientras se vuelve a preguntar al servidor; nunca sustituye
/// a su respuesta. Vive en el almacenamiento privado de la app, un archivo por
/// cuenta.
class MusicBootCache {
  MusicBootCache(this.uid);

  final String uid;
  Future<Map<String, dynamic>>? _loaded;
  Future<void> _writing = Future.value();

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final name = sha1.convert(utf8.encode(uid)).toString().substring(0, 16);
      return File('${dir.path}${Platform.pathSeparator}music_boot_$name.json');
    } on Object {
      // Sin plugin (pruebas) no hay caché.
      return null;
    }
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      // Un archivo de otra cuenta o ilegible se ignora.
      return data is Map<String, dynamic> && data['uid'] == uid ? data : {};
    } on Object {
      return {};
    }
  }

  Future<Map<String, dynamic>> get _data => _loaded ??= _read();

  /// El valor guardado bajo [key], o null.
  Future<Map<String, dynamic>?> read(String key) async {
    final value = (await _data)[key];
    return value is Map<String, dynamic> ? value : null;
  }

  /// Guarda [value] bajo [key]; con null lo quita.
  Future<void> write(String key, Map<String, dynamic>? value) async {
    final data = await _data;
    if (value == null) {
      if (data.remove(key) == null) return;
    } else {
      data[key] = value;
    }
    data['uid'] = uid;
    // Las escrituras van en fila: nunca dos a la vez sobre el mismo archivo.
    _writing = _writing.then((_) => _store(data));
    await _writing;
  }

  Future<void> _store(Map<String, dynamic> data) async {
    try {
      final file = await _file();
      if (file == null) return;
      // Temporal y renombrado: nunca queda un archivo a medias.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);
      await temp.rename(file.path);
    } on Object {
      // Sin caché la app solo abre más despacio.
    }
  }

  /// Máximo de primeras páginas guardadas; al pasarlo se borran las más
  /// antiguas.
  static const maxPages = 24;

  Future<Directory?> _pagesDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final name = sha1.convert(utf8.encode(uid)).toString().substring(0, 16);
      final pages = Directory(
        '${dir.path}${Platform.pathSeparator}music_pages_$name',
      );
      await pages.create(recursive: true);
      return pages;
    } on Object {
      return null;
    }
  }

  Future<File?> _pageFile(String key) async {
    final dir = await _pagesDir();
    return dir == null
        ? null
        : File(
            '${dir.path}${Platform.pathSeparator}'
            '${sha1.convert(utf8.encode(key))}.json',
          );
  }

  /// La página guardada bajo [key] (una playlist, Me gusta, Inicio…), o null.
  Future<Map<String, dynamic>?> readPage(String key) async {
    try {
      final file = await _pageFile(key);
      if (file == null || !await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic> ? data : null;
    } on Object {
      return null;
    }
  }

  /// Guarda una página en su propio archivo: verla no reescribe las demás.
  Future<void> writePage(String key, Map<String, dynamic> page) async {
    try {
      final file = await _pageFile(key);
      if (file == null) return;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(page), flush: true);
      await temp.rename(file.path);
      await _trimPages(file.parent);
    } on Object {
      // Sin esta copia la pantalla solo tarda lo que tarde el servidor.
    }
  }

  Future<void> _trimPages(Directory dir) async {
    final files = <(File, DateTime)>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        files.add((entity, (await entity.stat()).modified));
      }
    }
    if (files.length <= maxPages) return;
    files.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (file, _) in files.take(files.length - maxPages)) {
      await file.delete();
    }
  }

  Future<void> clear() async {
    try {
      final pages = await _pagesDir();
      if (pages != null && await pages.exists()) {
        await pages.delete(recursive: true);
      }
    } on Object {
      // Lo que quede no se lee con otra conexión: la clave lleva su generación.
    }
    (await _data).clear();
    _writing = _writing.then((_) async {
      try {
        final file = await _file();
        if (file != null && await file.exists()) await file.delete();
      } on Object {
        // Un archivo que no se pudo borrar se sobrescribe en la próxima visita.
      }
    });
    await _writing;
  }
}
