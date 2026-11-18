import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';

import '../domain/takeout_playlist.dart';

class TakeoutParser {
  static const maximumFileBytes = 25 * 1024 * 1024;
  static const maximumCsvBytes = 8 * 1024 * 1024;
  static const maximumRows = 50000;

  List<TakeoutPlaylist> parse(String name, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumFileBytes) {
      throw const TakeoutFailure('Elige un archivo de hasta 25 MB.');
    }
    try {
      final lists = name.toLowerCase().endsWith('.zip')
          ? _zip(bytes)
          : name.toLowerCase().endsWith('.csv')
          ? [_csv(name, bytes)]
          : throw const TakeoutFailure('Elige un ZIP o CSV de Google Takeout.');
      final parts = <TakeoutPlaylist>[];
      for (final list in lists) {
        if (list.sourceIds.isEmpty) continue;
        final count = (list.sourceIds.length / 500).ceil();
        for (var part = 0; part < count; part++) {
          final end = (part + 1) * 500;
          final suffix = count > 1 ? ' (parte ${part + 1} de $count)' : '';
          final base = String.fromCharCodes(
            list.name.runes.take(150 - suffix.length),
          );
          parts.add(
            TakeoutPlaylist(
              name: '$base$suffix',
              sourceIds: list.sourceIds.sublist(
                part * 500,
                end > list.sourceIds.length ? list.sourceIds.length : end,
              ),
              invalidRows: part == 0 ? list.invalidRows : 0,
            ),
          );
        }
      }
      if (parts.isEmpty) {
        throw const TakeoutFailure(
          'No se encontraron playlists ni canciones guardadas compatibles. '
          'Exporta playlists y biblioteca de YouTube y YouTube Music.',
        );
      }
      if (parts.fold(0, (sum, list) => sum + list.sourceIds.length) >
          maximumRows) {
        throw const TakeoutFailure(
          'Importa hasta 50 000 canciones por archivo.',
        );
      }
      return parts;
    } on TakeoutFailure {
      rethrow;
    } catch (_) {
      throw const TakeoutFailure(
        'No se pudo leer el archivo. Comprueba que sea un ZIP o CSV de Takeout válido.',
      );
    }
  }

  List<TakeoutPlaylist> _zip(Uint8List bytes) {
    // Inspect metadata before decoding. No archive entry is written to disk.
    final directory = ZipDirectory()
      ..read(InputMemoryStream(bytes), verify: true);
    if (directory.fileHeaders.length > 2000) {
      throw const TakeoutFailure(
        'El ZIP contiene demasiados archivos. Exporta solo playlists y biblioteca.',
      );
    }
    for (final header in directory.fileHeaders) {
      if ((header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
        throw const TakeoutFailure(
          'El ZIP contiene enlaces de archivo incompatibles.',
        );
      }
    }
    final archive = ZipDecoder().decodeBytes(
      bytes,
      verify: true,
      throwOnError: true,
    );
    final lists = <TakeoutPlaylist>[];
    var total = 0;
    for (final file in archive.files) {
      final path = file.name.replaceAll('\\', '/').toLowerCase();
      final relevant =
          path.endsWith('.csv') &&
          (path.contains('/playlists/') ||
              path.startsWith('playlists/') ||
              path.contains('music-library-songs') ||
              path.contains('music library songs') ||
              path.contains('canciones de la biblioteca'));
      if (!file.isFile || !relevant) continue;
      total += file.size;
      if (file.size > maximumCsvBytes || total > 32 * 1024 * 1024) {
        throw const TakeoutFailure(
          'Los CSV superan el límite de lectura. Selecciona archivos CSV por separado.',
        );
      }
      final list = _csv(file.name, file.content);
      if (list.sourceIds.isNotEmpty) lists.add(list);
    }
    return lists;
  }

  TakeoutPlaylist _csv(String path, List<int> bytes) {
    if (bytes.length > maximumCsvBytes) {
      throw const TakeoutFailure('Cada CSV debe ocupar hasta 8 MB.');
    }
    final rows = Csv(
      dynamicTyping: false,
    ).decode(utf8.decode(bytes).replaceFirst('\uFEFF', ''));
    if (rows.length > maximumRows + 10) {
      throw const TakeoutFailure('Importa hasta 50 000 canciones por CSV.');
    }
    var name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.csv$', caseSensitive: false), '');
    if (name.toLowerCase().contains('music-library-songs') ||
        name.toLowerCase().contains('music library songs') ||
        name.toLowerCase().contains('canciones de la biblioteca')) {
      name = 'Guardadas de YouTube Music';
    }
    var idColumn = -1;
    var invalid = 0;
    final ids = <String>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index].map((cell) => cell.toString().trim()).toList();
      if (row.every((cell) => cell.isEmpty)) continue;
      final headers = row.map(_header).toList();
      final column = headers.indexWhere(
        (value) => value == 'videoid' || value == 'songurl',
      );
      if (column >= 0) {
        idColumn = column;
        if (headers.contains('songtitle') || headers.contains('albumtitle')) {
          name = 'Guardadas de YouTube Music';
        }
        continue;
      }
      // Older Takeout CSVs include playlist metadata above the video table.
      if (headers.contains('playlistid') &&
          headers.contains('title') &&
          index + 1 < rows.length) {
        final titleColumn = headers.indexOf('title');
        if (titleColumn < rows[index + 1].length) {
          final title = rows[index + 1][titleColumn].toString().trim();
          if (title.isNotEmpty) name = title;
        }
      }
      if (idColumn < 0) continue;
      final id = idColumn < row.length ? _sourceId(row[idColumn]) : null;
      if (id == null) {
        invalid++;
      } else {
        ids.add(id);
      }
    }
    name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), ' ').trim();
    return TakeoutPlaylist(
      name: name.isEmpty ? 'Playlist de YouTube Music' : name,
      sourceIds: ids,
      invalidRows: invalid,
    );
  }

  String _header(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  String? _sourceId(String value) {
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return null;
    }
    final id = switch (uri.host.toLowerCase()) {
      'youtube.com' ||
      'www.youtube.com' ||
      'music.youtube.com' => uri.queryParameters['v'],
      'youtu.be' => uri.pathSegments.firstOrNull,
      _ => null,
    };
    return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
        ? id
        : null;
  }
}
