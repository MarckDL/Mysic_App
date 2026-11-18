import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../domain/takeout_playlist.dart';
import 'takeout_parser.dart';

class TakeoutFilePicker {
  Future<List<TakeoutPlaylist>?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip', 'csv'],
    );
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > TakeoutParser.maximumFileBytes) {
      throw const TakeoutFailure('Elige un archivo de hasta 25 MB.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (builder.length + chunk.length > TakeoutParser.maximumFileBytes) {
        throw const TakeoutFailure('Elige un archivo de hasta 25 MB.');
      }
      builder.add(chunk);
    }
    final input = (file.name, builder.takeBytes());
    return compute(_parse, input);
  }
}

List<TakeoutPlaylist> _parse((String, Uint8List) input) =>
    TakeoutParser().parse(input.$1, input.$2);
