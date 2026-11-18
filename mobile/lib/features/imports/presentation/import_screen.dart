import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/import_controller.dart';
import '../application/import_providers.dart';

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  Future<void> _openTakeout(BuildContext context) async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://takeout.google.com/'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // Show a usable address if Android has no external browser.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abre takeout.google.com en tu navegador.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(importControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Importar de YouTube Music')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Descarga tu copia de Google Takeout. Desmarca los demás '
                'productos y elige playlists y canciones de la biblioteca '
                'en YouTube y YouTube Music, en formato CSV y archivo ZIP.',
              ),
              TextButton.icon(
                onPressed: () => _openTakeout(context),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir Google Takeout'),
              ),
              const Text(
                'Cuando tengas el archivo, selecciona qué quieres copiar. '
                'Las playlists se guardan como privadas. Las listas de más '
                'de 500 canciones se dividen en partes. Las canciones guardadas '
                'se agrupan en “Guardadas de YouTube Music”.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.pick,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Elegir ZIP o CSV'),
              ),
              if (controller.error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: controller.busy ? null : controller.load,
                  child: const Text('Recuperar borradores pendientes'),
                ),
              ],
              if (controller.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  controller.progress.isEmpty
                      ? 'Leyendo archivo…'
                      : controller.progress,
                ),
                TextButton(
                  onPressed: controller.pause,
                  child: const Text('Pausar después del lote actual'),
                ),
              ],
              const SizedBox(height: 12),
              for (final entry in controller.entries)
                _ImportCard(entry: entry, controller: controller),
              if (controller.entries.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: controller.busy || controller.selected.isEmpty
                      ? null
                      : controller.review,
                  child: const Text('Revisar canciones seleccionadas'),
                ),
                if (controller.canRetry)
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => controller.review(retry: true),
                    child: const Text('Reintentar fallos temporales'),
                  ),
                if (controller.canConfirm) ...[
                  const Text(
                    'Se guardarán las listas revisadas que contienen canciones reconocidas. Las que figuran '
                    'como no disponibles o con un fallo temporal se omitirán.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: controller.busy ? null : controller.confirm,
                    child: const Text('Guardar copia privada'),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              const Text(
                'Puedes retomar los borradores durante 24 horas desde esta '
                'pantalla. Cada nueva importación crea una copia independiente.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.entry, required this.controller});
  final ImportEntry entry;
  final ImportController controller;

  @override
  Widget build(BuildContext context) {
    final draft = entry.draft;
    final saved = draft?.confirmed == true;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saved)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(entry.name),
              subtitle: Text(
                '${draft!.savedCount} guardadas · ${draft.skippedCount} omitidas',
              ),
              trailing: draft.playlistId == null
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: draft.playlistId == null
                  ? null
                  : () => context.push('/playlists/${draft.playlistId}'),
            )
          else
            CheckboxListTile(
              value: entry.selected,
              onChanged: controller.busy
                  ? null
                  : (value) => controller.select(entry, value ?? false),
              title: Text(entry.name),
              subtitle: Text('${entry.total} canciones'),
            ),
          if ((entry.source?.invalidRows ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${entry.source!.invalidRows} filas sin un ID válido se omitieron al leer el archivo.',
              ),
            ),
          if (draft != null && !saved) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${draft.count('ready')} reconocidas · '
                '${draft.count('unavailable')} no disponibles · '
                '${draft.count('retry')} con fallo temporal · '
                '${draft.count('pending')} pendientes',
              ),
            ),
            ExpansionTile(
              title: const Text('Ver canciones'),
              children: [
                for (var index = 0; index < draft.items.length; index++)
                  ListTile(
                    dense: true,
                    title: Text(
                      draft.items[index].title ?? 'Canción ${index + 1}',
                    ),
                    subtitle: Text(switch (draft.items[index].status) {
                      'ready' => 'Reconocida',
                      'unavailable' => 'No disponible',
                      'retry' => 'Fallo temporal. Puedes reintentar.',
                      _ => 'Pendiente de revisión',
                    }),
                  ),
              ],
            ),
          ],
          if (!saved)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => controller.discard(entry),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Descartar borrador'),
              ),
            ),
        ],
      ),
    );
  }
}
