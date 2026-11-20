import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Audio explicitly selected on this device. Paths never enter API requests.
class DeviceRecordings {
  DeviceRecordings(
    this.uid, {
    this.directory = getApplicationSupportDirectory,
    this.pick = _pickAudio,
  });
  final String uid;
  final Future<Directory> Function() directory;
  final Future<Stream<List<int>>?> Function() pick;
  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static Future<Stream<List<int>>?> _pickAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    return file?.readAsByteStream();
  }

  static String _key(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  Future<Directory> _owner() async =>
      Directory('${(await directory()).path}/connected_audio/${_key(uid)}');
  Future<Directory> _binding(String libraryId) async =>
      Directory('${(await _owner()).path}/${_key(libraryId)}');

  /// A verified replacement or unlink releases copies belonging to the previous binding.
  Future<Map<String, Uri>> open(
    String? libraryId,
    bool Function() stillCurrent,
  ) async {
    final user = await _owner();
    final result = <String, Uri>{};
    if (!await user.exists()) return result;
    final active = libraryId == null ? null : _key(libraryId);
    await for (final entity in user.list(followLinks: false)) {
      if (!stillCurrent()) return {};
      if (entity is! Directory) continue;
      if (entity.uri.pathSegments.where((s) => s.isNotEmpty).last != active) {
        await entity.delete(recursive: true);
        continue;
      }
      await for (final file in entity.list(followLinks: false)) {
        if (!stillCurrent()) return {};
        if (file is Directory &&
            file.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('import-')) {
          final stat = await file.stat();
          if (DateTime.now().difference(stat.modified) >
              const Duration(days: 1)) {
            if (stillCurrent()) await file.delete(recursive: true);
          }
          continue;
        }
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;
        if (name.endsWith('.media')) {
          final id = name.substring(0, name.length - 6);
          if (_id.hasMatch(id)) result[id] = file.uri;
        }
      }
    }
    return result;
  }

  Future<Uri?> attach(
    String libraryId,
    String id,
    bool Function() stillCurrent,
  ) async {
    if (!_id.hasMatch(id) || !stillCurrent()) return null;
    final bytes = await pick();
    if (bytes == null || !stillCurrent()) return null;
    final folder = await _binding(libraryId);
    await folder.create(recursive: true);
    if (!stillCurrent()) return null;
    final staging = await folder.createTemp('import-');
    final file = File('${staging.path}/audio');
    try {
      final writer = await file.open(mode: FileMode.write);
      var length = 0;
      try {
        await for (final chunk in bytes) {
          if (!stillCurrent()) return null;
          await writer.writeFrom(chunk);
          length += chunk.length;
        }
      } finally {
        await writer.close();
      }
      if (!stillCurrent()) return null;
      if (length == 0) {
        throw const FormatException('El archivo de audio está vacío.');
      }
      return (await file.rename('${folder.path}/$id.media')).uri;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> remove(String libraryId, String id) async {
    if (!_id.hasMatch(id)) return;
    final file = File('${(await _binding(libraryId)).path}/$id.media');
    if (await file.exists()) await file.delete();
  }
}
