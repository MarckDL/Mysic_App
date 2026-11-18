import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../data/import_client.dart';
import '../data/takeout_file_picker.dart';
import '../domain/music_import.dart';
import '../domain/takeout_playlist.dart';

class ImportEntry {
  ImportEntry({required this.id, this.source, this.draft});
  final String id;
  final TakeoutPlaylist? source;
  MusicImport? draft;
  bool selected = true;

  String get name => draft?.name ?? source!.name;
  int get total => draft?.confirmed == true
      ? draft!.savedCount + draft!.skippedCount
      : draft?.items.length ?? source!.sourceIds.length;
}

class ImportController extends ChangeNotifier {
  ImportController(this._client, this._picker, {required this.onSaved});
  final ImportClient _client;
  final TakeoutFilePicker _picker;
  final VoidCallback onSaved;
  final _cancel = CancelToken();
  bool _disposed = false;
  bool _pauseRequested = false;
  bool busy = false;
  String? error;
  String progress = '';
  List<ImportEntry> entries = [];

  List<ImportEntry> get selected => entries
      .where((entry) => entry.selected && entry.draft?.confirmed != true)
      .toList();

  bool _readyToSave(ImportEntry entry) =>
      entry.draft != null &&
      entry.draft!.count('pending') == 0 &&
      entry.draft!.count('ready') > 0;

  bool get canConfirm => selected.any(_readyToSave);

  bool get canRetry =>
      selected.any((entry) => (entry.draft?.count('retry') ?? 0) > 0);

  void select(ImportEntry entry, bool value) {
    if (busy) return;
    entry.selected = value;
    error = null;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _pauseRequested = false;
    notifyListeners();
    try {
      await action();
    } catch (failure) {
      if (!_disposed) {
        error = switch (failure) {
          TakeoutFailure(:final message) => message,
          ApiFailure(statusCode: 404) =>
            'El borrador caducó o ya no está disponible. Vuelve a seleccionar el archivo.',
          ApiFailure(statusCode: 409) =>
            'Revisa las canciones pendientes antes de guardar.',
          ApiFailure(statusCode: 429) =>
            'Guarda las listas ya revisadas. Si continúa el límite, espera un minuto y vuelve a revisar.',
          _ =>
            'No se pudo completar la importación. Comprueba tu conexión y vuelve a intentarlo.',
        };
      }
    } finally {
      if (!_disposed) {
        busy = false;
        progress = '';
        notifyListeners();
      }
    }
  }

  Future<void> load() => _run(() async {
    progress = 'Buscando importaciones pendientes…';
    final drafts = await _client.list(_cancel);
    if (_disposed) return;
    entries = drafts
        .map((draft) => ImportEntry(id: draft.id, draft: draft))
        .toList();
  });

  Future<void> pick() => _run(() async {
    final lists = await _picker.pick();
    if (lists == null || _disposed) return;
    entries = [
      ...entries.where((entry) => entry.draft != null),
      ...lists.map((list) => ImportEntry(id: newImportId(), source: list)),
    ];
  });

  void pause() {
    _pauseRequested = true;
    notifyListeners();
  }

  Future<void> discard(ImportEntry entry) => _run(() async {
    try {
      await _client.discard(entry.id, _cancel);
    } on ApiFailure catch (failure) {
      if (failure.statusCode != 404) rethrow;
    }
    if (!_disposed) entries.remove(entry);
  });

  Future<void> review({bool retry = false}) => _run(() async {
    final chosen = selected;
    for (final entry in chosen) {
      if (_pauseRequested || _disposed) break;
      progress = 'Preparando ${entry.name}…';
      notifyListeners();
      entry.draft ??= await _client.prepare(entry.id, entry.source!, _cancel);
      if (_disposed) return;
      final indices = <int>[
        for (var index = 0; index < entry.draft!.items.length; index++)
          if (entry.draft!.items[index].status == 'pending' ||
              (retry && entry.draft!.items[index].status == 'retry'))
            index,
      ];
      for (var start = 0; start < indices.length; start += 2) {
        if (_pauseRequested || _disposed) break;
        final end = start + 2 > indices.length ? indices.length : start + 2;
        entry.draft = await _client.resolve(
          entry.id,
          indices.sublist(start, end),
          _cancel,
        );
        if (_disposed) return;
        progress =
            'Revisando ${entry.name} · '
            '${entry.total - entry.draft!.count('pending')} de ${entry.total}';
        notifyListeners();
      }
    }
  });

  Future<void> confirm() async {
    if (!canConfirm) return;
    await _run(() async {
      for (final entry in selected.where(_readyToSave)) {
        progress = 'Guardando ${entry.name}…';
        notifyListeners();
        entry.draft = await _client.confirm(entry.id, _cancel);
        if (_disposed) return;
        entry.selected = false;
        onSaved();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel.cancel();
    super.dispose();
  }
}
