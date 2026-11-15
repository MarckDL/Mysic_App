import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../search/presentation/catalog_widgets.dart';
import '../data/history_client.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<HistoryScreen> {
  final List<ListeningEntry> _items = [];
  String? _cursor;
  bool _loading = false;
  bool? _retryReset;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _retryReset = null;
    });
    try {
      final page = await ref
          .read(historyClientProvider)
          .list(limit: 20, cursor: reset ? null : _cursor);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
      });
    } catch (_) {
      if (mounted) setState(() => _retryReset = reset);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(historyClientProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi historial'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(reset: true),
            tooltip: 'Actualizar historial',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (_items.isEmpty && !_loading && _retryReset == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Tus canciones escuchadas aparecerán aquí.'),
            ),
          for (final item in _items)
            Builder(
              builder: (context) {
                final (:track, startedAt: date) = item;
                return ListTile(
                  leading: TrackArtwork(url: track.thumbnailUrl),
                  title: Text(track.title),
                  subtitle: Text(
                    '${track.artistName} · ${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () =>
                      context.push('/tracks/${Uri.encodeComponent(track.id)}'),
                );
              },
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_retryReset case final reset?)
            TextButton(
              onPressed: () => _load(reset: reset),
              child: const Text('No se pudo cargar. Reintentar'),
            ),
          if (_cursor != null && !_loading && _retryReset == null)
            TextButton(onPressed: _load, child: const Text('Cargar más')),
        ],
      ),
    );
  }
}
