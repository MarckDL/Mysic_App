import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/radio_station.dart';

/// Las emisoras del bloque de radio del Inicio, guardadas en el teléfono
/// (`radio_stations.json`). Sin archivo, o con uno ilegible, salen las de
/// fábrica.
class RadioStore extends ChangeNotifier {
  RadioStore._() : _dir = null;

  @visibleForTesting
  RadioStore.forTest(Directory directory) : _dir = Future.value(directory);

  static final instance = RadioStore._();

  Future<Directory?>? _dir;
  Future<void>? _loading;
  Future<void> _io = Future<void>.value();
  var _stations = List<RadioStation>.of(RadioStation.defaults);

  /// Las emisoras, en el orden en que se ven.
  List<RadioStation> get stations => List.unmodifiable(_stations);

  Future<Directory?> _directory() => _dir ??= () async {
    try {
      return await getApplicationSupportDirectory();
    } on Object {
      return null;
    }
  }();

  File _file(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}radio_stations.json');

  /// Lee la lista guardada. Se puede llamar varias veces: solo trabaja la
  /// primera.
  Future<void> load() => _loading ??= () async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      final file = _file(dir);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return;
      final read = <RadioStation>[];
      for (final entry in data) {
        final station = RadioStation.fromJson(entry);
        if (station != null && read.every((s) => s.id != station.id)) {
          read.add(station);
        }
      }
      // Una lista guardada vacía es la del usuario (quitó todas): se respeta.
      _stations = read;
      notifyListeners();
    } on Object {
      // Archivo ilegible: se quedan las de fábrica.
    }
  }();

  Future<void> add(RadioStation station) async {
    await load();
    if (_stations.any((s) => s.id == station.id)) return;
    _stations = [..._stations, station];
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    await load();
    final next = _stations.where((s) => s.id != id).toList();
    if (next.length == _stations.length) return;
    _stations = next;
    notifyListeners();
    await _save();
  }

  /// Escrituras de una en una, con un temporal propio y renombrado.
  Future<void> _save() {
    final run = _io.then((_) async {
      final dir = await _directory();
      if (dir == null) return;
      try {
        final target = _file(dir);
        final temp = File('${target.path}.tmp');
        await temp.writeAsString(
          jsonEncode([for (final s in _stations) s.toJson()]),
          flush: true,
        );
        await temp.rename(target.path);
      } on Object {
        // Vale para esta sesión; se guarda en el próximo cambio.
      }
    });
    _io = run.then((_) {}, onError: (_) {});
    return run;
  }
}
