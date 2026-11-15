import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<HistoryScreen> {
  late final AuthenticatedApiClient _api;
  final List<Map<String, dynamic>> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _api = AuthenticatedApiClient(
      ref.read(authRepositoryProvider),
      baseUrl: ApiConfig.baseUrl,
    );
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await _api.get(
        '/api/v1/history',
        query: {'limit': 20, if (!reset && _cursor != null) 'cursor': _cursor},
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(
          (data['items'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        _cursor = data['nextCursor'] as String?;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mi historial'),
      actions: [
        IconButton(
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      children: [
        if (_items.isEmpty && !_loading && !_failed)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Tus canciones escuchadas aparecerán aquí.'),
          ),
        for (final item in _items)
          Builder(
            builder: (context) {
              final track = item['track'] as Map;
              final date = DateTime.parse(
                item['startedAt'] as String,
              ).toLocal();
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(track['title'] as String),
                subtitle: Text(
                  '${track['artistName']} · ${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                ),
                onTap: () => context.push(
                  '/tracks/${Uri.encodeComponent(track['id'] as String)}',
                ),
              );
            },
          ),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_failed)
          TextButton(
            onPressed: () => _load(reset: _items.isEmpty),
            child: const Text('No se pudo cargar. Reintentar'),
          ),
        if (_cursor != null && !_loading && !_failed)
          TextButton(onPressed: _load, child: const Text('Cargar más')),
      ],
    ),
  );
}
