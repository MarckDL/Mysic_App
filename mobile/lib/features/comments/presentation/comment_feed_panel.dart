import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../application/comment_providers.dart';
import '../domain/comments.dart';

class CommentFeedPanel extends ConsumerStatefulWidget {
  const CommentFeedPanel({super.key, required String this.trackId});
  const CommentFeedPanel.moderation({super.key}) : trackId = null;

  final String? trackId;

  @override
  ConsumerState<CommentFeedPanel> createState() => _CommentFeedPanelState();
}

class _CommentFeedPanelState extends ConsumerState<CommentFeedPanel> {
  bool _busy = false;
  String? _error;

  bool get _moderation => widget.trackId == null;
  CommentFeed get _feed =>
      ref.read(commentFeedProvider(widget.trackId).notifier);

  Future<void> _run(
    Future<void> Function() operation, {
    bool refresh = true,
  }) async {
    if (_busy) return;
    final provider = commentFeedProvider(widget.trackId);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (mounted && refresh) ref.invalidate(provider);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiFailure && error.statusCode == 409 && _moderation) {
        ref.invalidate(provider);
        _error = 'Otra sesión ya resolvió estos reportes.';
      } else if (error is ApiFailure &&
          error.statusCode == 403 &&
          _moderation) {
        ref.invalidate(provider);
      } else {
        _error = 'No se pudo completar la acción. Inténtalo de nuevo.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([SongComment? item]) async {
    final body = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => _CommentEditor(initialBody: item?.body),
    );
    if (!mounted || body == null) return;
    await _run(
      () => item == null ? _feed.publish(body) : _feed.edit(item.id, body),
    );
  }

  Future<bool> _confirm(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _remove(SongComment item) async {
    if (await _confirm('¿Eliminar tu comentario?', 'Eliminar') && mounted) {
      await _run(() => _feed.remove(item.id));
    }
  }

  Future<void> _report(SongComment item) async {
    final reason = await showDialog<ReportReason>(
      context: context,
      useRootNavigator: false,
      builder: (context) => SimpleDialog(
        title: const Text('Motivo del reporte'),
        children: [
          for (final reason in ReportReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason),
              child: Text(reason.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (!mounted || reason == null) return;
    await _run(() async {
      await _feed.report(item.id, reason);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reporte registrado.')));
      }
    }, refresh: false);
  }

  Future<void> _hide(SongComment item) async {
    if (await _confirm('¿Ocultar este comentario?', 'Ocultar') && mounted) {
      await _run(() => _feed.resolve(item.id, ModerationAction.hide));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = commentFeedProvider(widget.trackId);
    final feed = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_moderation) ...[
          Text('Comentarios', style: Theme.of(context).textTheme.titleLarge),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: _busy || feed.isLoading ? null : () => _edit(),
              child: const Text('Escribir comentario'),
            ),
          ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_error case final message?) Text(message),
        feed.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Column(
            children: [
              Text(
                error is ApiFailure && error.statusCode == 403
                    ? 'No tienes permiso para moderar comentarios.'
                    : 'No se pudieron cargar los comentarios.',
              ),
              TextButton(
                onPressed: _busy ? null : () => ref.invalidate(provider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.items.isEmpty)
                Text(
                  _moderation
                      ? 'No hay reportes pendientes.'
                      : 'Aún no hay comentarios.',
                ),
              for (final item in page.items) _card(item),
              if (page.nextCursor != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _feed.loadMore(), refresh: false),
                  child: const Text('Cargar más'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(SongComment item) => Card(
    key: ValueKey(item.id),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.authorName, style: Theme.of(context).textTheme.titleSmall),
          Text(item.body),
          if (_moderation)
            Text(item.reasons.map((reason) => reason.label).join(' · ')),
          Wrap(
            children: [
              if (_moderation) ...[
                TextButton(
                  onPressed: _busy ? null : () => _hide(item),
                  child: const Text('Ocultar'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () =>
                              _feed.resolve(item.id, ModerationAction.dismiss),
                        ),
                  child: const Text('Desestimar'),
                ),
              ] else if (item.isMine) ...[
                TextButton(
                  onPressed: _busy ? null : () => _edit(item),
                  child: const Text('Editar'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _remove(item),
                  child: const Text('Eliminar'),
                ),
              ] else
                TextButton(
                  onPressed: _busy ? null : () => _report(item),
                  child: const Text('Reportar'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CommentEditor extends StatefulWidget {
  const _CommentEditor({this.initialBody});

  final String? initialBody;

  @override
  State<_CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<_CommentEditor> {
  final _form = GlobalKey<FormState>();
  late String _body = widget.initialBody ?? '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialBody == null ? 'Nuevo comentario' : 'Editar comentario',
    ),
    content: Form(
      key: _form,
      child: TextFormField(
        initialValue: _body,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Comentario',
          helperText: 'Máximo 500 caracteres',
        ),
        onChanged: (text) => _body = text,
        validator: (text) {
          final length = text?.trim().runes.length ?? 0;
          if (length == 0) return 'Escribe un comentario.';
          if (length > 500) return 'Reduce el texto a 500 caracteres.';
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _body.trim());
          }
        },
        child: Text(widget.initialBody == null ? 'Publicar' : 'Guardar'),
      ),
    ],
  );
}
