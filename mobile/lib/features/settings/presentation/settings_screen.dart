import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/images/disk_cached_image.dart';
import '../../../core/settings/app_settings.dart';
import '../../downloads/data/download_store.dart';
import '../../lyrics/data/lyrics_repository.dart';
import '../../playback/data/audio_disk_cache.dart';

/// Ajustes de la app, agrupados como en Limusic (estilo Apple Music): título
/// de grupo en mayúsculas, tarjeta con filas y una nota de ayuda al pie.
/// Solo aparecen opciones que de verdad cambian algo en Mysic.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapt = ref.watch(adaptCoverColorProvider);
    final reduced = ref.watch(reduceEffectsProvider);
    final keepAudio = ref.watch(keepAudioProvider);
    final offlineOnly = ref.watch(offlineOnlyProvider);
    final fastResolve = ref.watch(fastResolveProvider);
    final headProxy = ref.watch(headProxyProvider);
    final offset = ref.watch(lyricsOffsetProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingGroup(
              title: 'Apariencia',
              footer:
                  'Los colores tiñen los fondos y el acento con la portada de '
                  'la canción que suena. Reducir efectos quita los '
                  'desenfoques y los fondos de carátula: la app va más '
                  'fluida en teléfonos modestos.',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('Colores de la carátula'),
                  value: adapt,
                  onChanged: ref.read(adaptCoverColorProvider.notifier).set,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.speed),
                  title: const Text('Reducir efectos'),
                  value: reduced,
                  onChanged: ref.read(reduceEffectsProvider.notifier).set,
                ),
              ],
            ),
            SettingGroup(
              title: 'Letras',
              footer:
                  'Si la letra va adelantada o atrasada (por ejemplo con '
                  'auriculares Bluetooth), ajústala en pasos de 0,1 s.',
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Desfase de la letra'),
                  subtitle: Text(
                    '${offset >= 0 ? '+' : '−'}'
                    '${(offset.abs() / 1000).toStringAsFixed(1)} s',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Menos 0,1 s',
                        icon: const Icon(Icons.remove),
                        onPressed: () => ref
                            .read(lyricsOffsetProvider.notifier)
                            .change(-LyricsOffset.step),
                      ),
                      IconButton(
                        tooltip: 'Más 0,1 s',
                        icon: const Icon(Icons.add),
                        onPressed: () => ref
                            .read(lyricsOffsetProvider.notifier)
                            .change(LyricsOffset.step),
                      ),
                      IconButton(
                        tooltip: 'Restablecer',
                        icon: const Icon(Icons.restart_alt),
                        onPressed: offset == 0
                            ? null
                            : ref.read(lyricsOffsetProvider.notifier).reset,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SettingGroup(
              title: 'Almacenamiento',
              footer:
                  'Las portadas se guardan en el teléfono para abrir la app '
                  'más rápido y gastar menos datos. Borrarlas no quita nada '
                  'de tu biblioteca.',
              children: [_CoverCacheTile()],
            ),
            SettingGroup(
              title: 'Descargas',
              footer:
                  'Las canciones descargadas (menú de cada canción → '
                  'Descargar) suenan sin internet y no se borran solas. '
                  '«Solo canciones descargadas» no usa internet ni datos: '
                  'la app no abre ninguna conexión y reproduce únicamente '
                  'lo descargado. Si arrancas sin internet, se activa sola '
                  'esa sesión. Los vídeos de más de 20 minutos no se '
                  'descargan.',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.wifi_off),
                  title: const Text('Solo canciones descargadas'),
                  value: offlineOnly,
                  onChanged: ref.read(offlineOnlyProvider.notifier).set,
                ),
                const _DownloadsTile(),
              ],
            ),
            SettingGroup(
              title: 'Audio guardado',
              footer:
                  'Guarda en el teléfono las canciones que escuchas enteras '
                  'para repetirlas sin esperar ni gastar datos. Ocupa hasta '
                  '512 MB; al llenarse se borran las menos recientes. No se '
                  'guardan los vídeos de más de 20 minutos.',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.download_done_outlined),
                  title: const Text('Guardar el audio escuchado'),
                  value: keepAudio,
                  onChanged: ref.read(keepAudioProvider.notifier).set,
                ),
                const _AudioCacheTile(),
              ],
            ),
            SettingGroup(
              title: 'Reproducción rápida (experimental)',
              footer:
                  'Resolver directo pide el audio a YouTube en una sola '
                  'petición (NewPipe queda de respaldo). Primer tramo en '
                  'memoria guarda el inicio de las próximas canciones para que '
                  'empiecen al instante. Si algo falla, desactívalos.',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_outlined),
                  title: const Text('Resolver directo con YouTube'),
                  value: fastResolve,
                  onChanged: ref.read(fastResolveProvider.notifier).set,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.memory_outlined),
                  title: const Text('Primer tramo en memoria'),
                  value: headProxy,
                  onChanged: ref.read(headProxyProvider.notifier).set,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Grupo de filas: encabezado pequeño en mayúsculas, tarjeta redondeada con
/// separadores finos y una nota opcional debajo.
class SettingGroup extends StatelessWidget {
  const SettingGroup({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                letterSpacing: .8,
              ),
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                footer!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila que abre la lista de descargas y dice cuántas hay.
class _DownloadsTile extends StatefulWidget {
  const _DownloadsTile();

  @override
  State<_DownloadsTile> createState() => _DownloadsTileState();
}

class _DownloadsTileState extends State<_DownloadsTile> {
  final _store = DownloadStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final tracks = _store.tracks;
      final bytes = tracks.fold<int>(0, (sum, track) => sum + track.bytes);
      return ListTile(
        leading: const Icon(Icons.download_for_offline_outlined),
        title: const Text('Canciones descargadas'),
        subtitle: Text(
          tracks.isEmpty
              ? 'Ninguna'
              : '${tracks.length} · ${_CacheTileState._format(bytes)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/downloads'),
      );
    },
  );
}

/// Muestra cuánto ocupan las portadas guardadas y deja vaciarlas tras
/// confirmar.
class _CoverCacheTile extends StatelessWidget {
  const _CoverCacheTile();

  @override
  Widget build(BuildContext context) => _CacheTile(
    icon: Icons.image_outlined,
    title: 'Caché de portadas',
    question: '¿Borrar la caché de portadas?',
    detail: 'Las portadas se volverán a descargar cuando las necesites.',
    size: DiskImageCache.instance.size,
    clear: () async {
      PaintingBinding.instance.imageCache.clear();
      await DiskImageCache.instance.clear();
    },
  );
}

/// Lo mismo para el audio guardado.
class _AudioCacheTile extends StatelessWidget {
  const _AudioCacheTile();

  @override
  Widget build(BuildContext context) => _CacheTile(
    icon: Icons.music_note_outlined,
    title: 'Audio en el teléfono',
    question: '¿Borrar el audio guardado?',
    detail: 'Las canciones se volverán a descargar al reproducirlas.',
    size: AudioDiskCache.instance.size,
    clear: AudioDiskCache.instance.clear,
  );
}

/// Fila con el tamaño de una caché y su borrado tras confirmar.
class _CacheTile extends StatefulWidget {
  const _CacheTile({
    required this.icon,
    required this.title,
    required this.question,
    required this.detail,
    required this.size,
    required this.clear,
  });

  final IconData icon;
  final String title;
  final String question;
  final String detail;
  final Future<int> Function() size;
  final Future<void> Function() clear;

  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    final bytes = await widget.size();
    if (mounted) setState(() => _bytes = bytes);
  }

  static String _format(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.question),
        content: Text(widget.detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.clear();
    await _measure();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(widget.icon),
    title: Text(widget.title),
    subtitle: Text(_bytes == null ? 'Calculando…' : _format(_bytes!)),
    trailing: const Icon(Icons.delete_outline),
    onTap: _bytes == 0 ? null : _clear,
  );
}
