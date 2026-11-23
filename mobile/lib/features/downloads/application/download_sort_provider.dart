import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/download_sort.dart';

/// El orden de las descargas (Limusic: `setDownloadSort`), guardado en un
/// archivo pequeño para que sobreviva al cierre de la app.
final downloadSortProvider =
    NotifierProvider<DownloadSortSetting, DownloadSort>(
      DownloadSortSetting.new,
    );

class DownloadSortSetting extends Notifier<DownloadSort> {
  static const _fileName = 'download_sort.txt';

  @override
  DownloadSort build() {
    unawaited(_load());
    return DownloadSort.initial;
  }

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } on Object {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final saved = DownloadSort.decode(await file.readAsString());
      if (ref.mounted) state = saved;
    } on Object {
      // Sin archivo legible se queda el orden predeterminado.
    }
  }

  void set(DownloadSort sort) {
    state = sort;
    unawaited(() async {
      try {
        await (await _file())?.writeAsString(sort.encode());
      } on Object {
        // El orden vale para esta sesión aunque no se pueda guardar.
      }
    }());
  }
}
