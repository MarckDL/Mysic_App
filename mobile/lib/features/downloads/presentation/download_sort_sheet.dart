import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/download_sort_provider.dart';
import '../domain/download_sort.dart';

/// El botón de ordenar de las descargas (Limusic: el de la `ActionsPill`):
/// con un orden distinto del predeterminado se pinta del acento.
class DownloadSortButton extends ConsumerWidget {
  const DownloadSortButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(downloadSortProvider);
    return IconButton(
      tooltip: 'Ordenar: ${sort.key.label}',
      color: sort.isDefault ? null : Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.sort_rounded),
      onPressed: () => showDownloadSortSheet(context),
    );
  }
}

/// «Ordenar por» (Limusic: `PlaylistSortSheet`): elegir un orden lo aplica y
/// cierra la hoja; «Invertir» lo aplica y la deja abierta.
Future<void> showDownloadSortSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final sort = ref.watch(downloadSortProvider);
          final setting = ref.read(downloadSortProvider.notifier);
          final theme = Theme.of(context);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Ordenar por', style: theme.textTheme.titleLarge),
                ),
                RadioGroup<DownloadSortKey>(
                  groupValue: sort.key,
                  onChanged: (key) {
                    if (key == null) return;
                    setting.set(sort.copyWith(key: key));
                    Navigator.of(context).pop();
                  },
                  child: Column(
                    children: [
                      for (final key in DownloadSortKey.values)
                        RadioListTile<DownloadSortKey>(
                          value: key,
                          title: Text(key.label),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.swap_vert_rounded),
                  title: const Text('Invertir'),
                  value: sort.desc,
                  onChanged: (desc) => setting.set(sort.copyWith(desc: desc)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
