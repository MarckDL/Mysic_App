import 'package:flutter/material.dart';
import '../domain/playlist.dart';

class PlaylistFormResult {
  const PlaylistFormResult({
    required this.name,
    required this.description,
    required this.visibility,
  });
  final String name;
  final String? description;
  final PlaylistVisibility visibility;
}

Future<PlaylistFormResult?> showPlaylistFormDialog(
  BuildContext context, {
  PlaylistSummary? initial,
}) => showDialog<PlaylistFormResult>(
  context: context,
  builder: (context) => _PlaylistFormDialog(initial: initial),
);

class _PlaylistFormDialog extends StatefulWidget {
  const _PlaylistFormDialog({this.initial});
  final PlaylistSummary? initial;

  @override
  State<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends State<_PlaylistFormDialog> {
  final key = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
    text: widget.initial?.name,
  );
  late final TextEditingController description = TextEditingController(
    text: widget.initial?.description,
  );
  late PlaylistVisibility visibility =
      widget.initial?.visibility ?? PlaylistVisibility.private;

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Nueva playlist' : 'Editar playlist'),
    content: Form(
      key: key,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              autofocus: true,
              maxLength: 150,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe un nombre.'
                  : null,
            ),
            TextFormField(
              controller: description,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
              ),
            ),
            DropdownButtonFormField<PlaylistVisibility>(
              initialValue: visibility,
              decoration: const InputDecoration(labelText: 'Privacidad'),
              items: const [
                DropdownMenuItem(
                  value: PlaylistVisibility.private,
                  child: Text('Privada'),
                ),
                DropdownMenuItem(
                  value: PlaylistVisibility.public,
                  child: Text('Pública'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => visibility = value);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!key.currentState!.validate()) return;
          final cleanDescription = description.text.trim();
          Navigator.pop(
            context,
            PlaylistFormResult(
              name: name.text.trim(),
              description: cleanDescription.isEmpty ? null : cleanDescription,
              visibility: visibility,
            ),
          );
        },
        child: Text(widget.initial == null ? 'Crear' : 'Guardar'),
      ),
    ],
  );
}
