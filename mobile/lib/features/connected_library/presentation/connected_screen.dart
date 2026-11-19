import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../application/connected_controller.dart';
import '../application/connected_host.dart';
import '../data/connected_client.dart';

class ConnectedTile extends StatelessWidget {
  const ConnectedTile({super.key, this.account = false});
  final bool account;
  @override
  Widget build(BuildContext context) {
    final model = ConnectedScope.of(context);
    if (model == null) return const SizedBox.shrink();
    final connection = model.connection;
    final initial = connection?.status == 'unlinked' && model.pending == null;
    return ListTile(
      leading: const Icon(Icons.subscriptions_outlined),
      title: Text(initial ? 'Vincular YouTube' : 'Biblioteca de YouTube'),
      subtitle: Text(
        connection?.channel?.title ??
            (model.pending != null
                ? 'Vinculación en curso'
                : 'Playlists de tu canal'),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        context.push('/library/youtube');
        if (initial && !account && !model.busy) unawaited(model.start());
      },
    );
  }
}

class ConnectedScreen extends StatelessWidget {
  const ConnectedScreen({super.key, this.playlistId, this.title});
  final String? playlistId, title;
  @override
  Widget build(BuildContext context) {
    final model = ConnectedScope.of(context);
    final connection = model?.connection;
    final listing =
        model != null && connection?.linked == true && model.pending == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          playlistId == null
              ? 'Biblioteca de YouTube'
              : title ?? 'Playlist de YouTube',
        ),
        actions: [
          if (listing && playlistId == null)
            PopupMenuButton<String>(
              tooltip: 'Opciones del vínculo',
              enabled: !model.busy,
              onSelected: (value) async {
                if (value == 'change') {
                  await model.start(restart: true);
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('¿Desvincular YouTube?'),
                    content: Text(
                      'Se retirará el acceso al canal ${connection?.channel?.title ?? ''}. Tu sesión de Mysic seguirá abierta.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Desvincular'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && model.alive) await model.unlink();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'change',
                  child: Text('Cambiar cuenta de YouTube'),
                ),
                PopupMenuItem(
                  value: 'unlink',
                  child: Text('Desvincular YouTube'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: model == null
            ? const Center(child: Text('El piloto está desactivado.'))
            : listing
            ? _LibraryList(
                key: ValueKey((model.uid, connection!.generation, playlistId)),
                model: model,
                playlistId: playlistId,
              )
            : _LinkPanel(model: model),
      ),
    );
  }
}

class _LinkPanel extends StatelessWidget {
  const _LinkPanel({required this.model});
  final ConnectedController model;
  @override
  Widget build(BuildContext context) {
    final pending = model.pending, channel = model.candidate;
    final connection = model.connection;
    final busy = model.busy;
    final revoked = connection?.status == 'revocation_pending';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy)
          const LinearProgressIndicator(semanticsLabel: 'Consultando YouTube'),
        if (channel != null) ...[
          Text(
            model.replaceRequired
                ? '¿Reemplazar el canal vinculado?'
                : 'Confirma tu canal',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (model.replaceRequired && connection?.channel != null)
            Text('Canal actual: ${connection!.channel!.title}'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(channel.title),
            subtitle: Text(channel.id),
          ),
          FilledButton(
            onPressed: busy ? null : model.confirmCandidate,
            child: Text(
              model.replaceRequired
                  ? 'Reemplazar por este canal'
                  : 'Confirmar este canal',
            ),
          ),
        ] else if (pending != null) ...[
          Text(
            'Esperando autorización',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Elige tu cuenta y canal en Google. Si ya terminaste, comprueba el resultado aquí.',
          ),
          FilledButton(
            onPressed: busy ? null : () => model.sync(),
            child: const Text('Comprobar vinculación'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => model.start(restart: pending.id != null),
            child: const Text('Volver a abrir Google'),
          ),
        ] else if (connection != null && !revoked) ...[
          Text(
            connection.status == 'reauthorization_required'
                ? 'Vuelve a autorizar tu canal'
                : 'Tus playlists de YouTube',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Elige la cuenta de YouTube cuyas playlists quieres consultar. Puede ser distinta de tu cuenta de Mysic.',
          ),
          FilledButton.icon(
            onPressed: busy ? null : () => model.start(),
            icon: const Icon(Icons.open_in_new),
            label: Text(
              model.forceConsent ? 'Volver a dar permiso' : 'Vincular YouTube',
            ),
          ),
        ] else if (revoked)
          const Text(
            'El acceso desde Mysic ya se retiró. La revocación en Google está pendiente.',
          ),
        if (pending != null)
          TextButton(
            onPressed: busy ? null : model.cancel,
            child: const Text('Cancelar vinculación'),
          ),
        if (model.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(model.message!, semanticsLabel: model.message),
          ),
        if (!busy &&
            pending == null &&
            (connection == null || revoked || model.message != null))
          OutlinedButton(
            onPressed: () => model.sync(),
            child: const Text('Reintentar'),
          ),
      ],
    );
  }
}

class _LibraryList extends StatefulWidget {
  const _LibraryList({
    super.key,
    required this.model,
    required this.playlistId,
  });
  final ConnectedController model;
  final String? playlistId;
  @override
  State<_LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<_LibraryList> {
  final _rows = <LibraryRow>[], _ids = <String>{};
  CancelToken? _request;
  String? _cursor, _error;
  bool _loading = true, _started = false, _restart = false;
  Timer? _cooldown;
  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _request?.cancel();
    _cooldown?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_cooldown?.isActive == true ||
        (!reset && (_loading || _cursor == null))) {
      return;
    }
    _request?.cancel();
    final request = CancelToken();
    _request = request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.model.client.page(
        widget.playlistId,
        reset ? null : _cursor,
        request,
      );
      if (!mounted || request.isCancelled) return;
      setState(() {
        if (reset) {
          _rows.clear();
          _ids.clear();
        }
        _started = true;
        _restart = false;
        _rows.addAll(page.items.where((row) => _ids.add(row.id)));
        _cursor = page.next;
      });
    } catch (e) {
      if (!mounted || request.isCancelled) return;
      final code = e is ApiFailure ? e.code : null;
      if (code == 'REAUTHORIZE_YOUTUBE' || code == 'YOUTUBE_LINK_CHANGED') {
        setState(() {
          _rows.clear();
          _ids.clear();
          _cursor = null;
        });
        unawaited(widget.model.sync());
      }
      setState(() {
        _error = libraryError(e);
        _restart =
            reset ||
            [
              'INVALID_CURSOR',
              'CURSOR_EXPIRED',
              'YOUTUBE_LINK_CHANGED',
            ].contains(code);
        if (_restart && !reset) {
          _rows.clear();
          _ids.clear();
          _cursor = null;
        }
      });
      if (e is ApiFailure && e.retryAfter != null) {
        _cooldown = Timer(e.retryAfter!, () {
          if (mounted) setState(() {});
        });
      }
    } finally {
      if (mounted && !request.isCancelled) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.playlistId != null;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _rows.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              subtitle: widget.model.message == null
                  ? null
                  : Text(widget.model.message!),
              title: Text(
                detail
                    ? 'Videos'
                    : 'Playlists de ${widget.model.connection?.channel?.title ?? 'YouTube'}',
              ),
              trailing: IconButton(
                tooltip: 'Actualizar',
                onPressed: _loading || _cooldown?.isActive == true
                    ? null
                    : () => _load(reset: true),
                icon: const Icon(Icons.refresh),
              ),
            );
          }
          if (i == _rows.length + 1) {
            return Column(
              children: [
                if (_loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Cargando biblioteca',
                  ),
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                    onPressed: _cooldown?.isActive == true
                        ? null
                        : () => _load(reset: _restart || !_started),
                    child: const Text('Reintentar'),
                  ),
                ] else if (!_loading && _cursor != null)
                  OutlinedButton(
                    onPressed: () => _load(),
                    child: const Text('Cargar más'),
                  )
                else if (!_loading && _rows.isEmpty)
                  Text(
                    detail
                        ? 'Esta playlist está vacía.'
                        : 'YouTube no devolvió playlists propias para este canal.',
                  ),
              ],
            );
          }
          final row = _rows[i - 1], image = row.thumbnail;
          final icon = Icon(
            detail ? Icons.play_circle_outline : Icons.queue_music,
          );
          return ListTile(
            key: ValueKey(row.id),
            leading: image == null
                ? icon
                : Image.network(
                    image,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => icon,
                  ),
            title: Text(row.title),
            subtitle: row.subtitle?.isNotEmpty == true
                ? Text(row.subtitle!)
                : null,
            trailing: detail
                ? (row.open == null ? null : const Icon(Icons.open_in_new))
                : const Icon(Icons.chevron_right),
            onTap: detail && row.open == null
                ? null
                : () async {
                    if (!detail) {
                      context.push(
                        '/library/youtube/playlist/${Uri.encodeComponent(row.id)}',
                        extra: row.title,
                      );
                      return;
                    }
                    var opened = false;
                    try {
                      opened = await widget.model.platform.open(row.open!);
                    } catch (_) {}
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No se pudo abrir el video en YouTube.',
                          ),
                        ),
                      );
                    }
                  },
          );
        },
      ),
    );
  }
}
