import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../downloads/data/download_store.dart';
import '../../search/domain/catalog_track.dart';
import '../application/track_playback_controller.dart';
import 'player_widgets.dart' show audioTime;

Future<void> _showSheet(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .5),
      elevation: 0,
      builder: builder,
    );

/// El marco de las hojas del reproductor: tarjeta con esquinas de 20 dp,
/// tirador, título y contenido, sobre el teclado si lo hay.
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Casilla del temporizador (Limusic `SleepChip`): 48 dp de alto, radio 14.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Expanded(
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .16)
            : colors.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? colors.primary : colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El temporizador de apagado (Limusic `SleepTimerBottomSheet`). Apagado, es
/// una cuadrícula de duraciones: un toque lo inicia y cierra («Personalizado»
/// pide antes los minutos). En marcha, cuenta atrás, con +10 min y Apagar.
Future<void> showSleepTimerSheet(
  BuildContext context,
  TrackPlaybackController controller,
) => _showSheet(context, (context) => _SleepTimer(controller: controller));

class _SleepTimer extends StatefulWidget {
  const _SleepTimer({required this.controller});

  final TrackPlaybackController controller;

  @override
  State<_SleepTimer> createState() => _SleepTimerState();
}

class _SleepTimerState extends State<_SleepTimer> {
  var _custom = false;
  final _minutes = TextEditingController();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // La cuenta atrás se repinta cada pocos segundos mientras la hoja está
    // abierta.
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.controller.removeListener(_changed);
    _minutes.dispose();
    super.dispose();
  }

  void _start(int minutes) {
    widget.controller.setSleepTimer(minutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final player = widget.controller;
    if (player.sleepActive) {
      final at = player.sleepAt;
      return _Frame(
        title: 'Temporizador de apagado',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  at == null
                      ? 'Al acabar la canción'
                      : player.sleepMinutesLeft == 1
                      ? 'Queda 1 min'
                      : 'Quedan ${player.sleepMinutesLeft} min',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (at != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Se pausa hacia las '
                      '${at.hour.toString().padLeft(2, '0')}:'
                      '${at.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              if (at != null) ...[
                _Chip(
                  label: '+10 min',
                  onTap: () =>
                      player.setSleepTimer(player.sleepMinutesLeft + 10),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    player.cancelSleepTimer();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apagar'),
                ),
              ),
            ],
          ),
        ],
      );
    }
    final value = int.tryParse(_minutes.text) ?? 0;
    return _Frame(
      title: 'Temporizador de apagado',
      children: [
        Text(
          'La música se pausa sola cuando pase el tiempo.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final row in const [
          [5, 10, 15],
          [30, 45, 60],
        ]) ...[
          Row(
            children: [
              for (final (index, minutes) in row.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                _Chip(
                  label: minutes == 60 ? '1 hora' : '$minutes min',
                  onTap: () => _start(minutes),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            _Chip(
              label: 'Fin de la canción',
              onTap: () {
                player.sleepAfterTrack();
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Personalizado',
              selected: _custom,
              onTap: () => setState(() => _custom = true),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !_custom
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _minutes,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(labelText: 'Minutos'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: value > 0 ? () => _start(value) : null,
                        child: const Text('Iniciar'),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Velocidad y tono (Limusic `PlaybackSpeedPitchBottomSheet`): dos filas con
/// menos, valor y más. La velocidad va de x0,2 a x2 en pasos de 0,1; el tono,
/// de -12 a 12 semitonos.
Future<void> showTuningSheet(
  BuildContext context,
  TrackPlaybackController controller,
) => _showSheet(
  context,
  (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context), colors = theme.colorScheme;
      Widget row({
        required IconData icon,
        required String label,
        required String value,
        required VoidCallback? less,
        required VoidCallback? more,
      }) => Row(
        children: [
          Icon(icon, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          IconButton(
            tooltip: 'Menos',
            icon: const Icon(Icons.remove_rounded),
            onPressed: less,
          ),
          SizedBox(
            width: 60,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Más',
            icon: const Icon(Icons.add_rounded),
            onPressed: more,
          ),
        ],
      );
      final speed = controller.speed, pitch = controller.pitch;
      return _Frame(
        title: 'Velocidad y tono',
        children: [
          row(
            icon: Icons.speed_rounded,
            label: 'Velocidad',
            value: 'x${speed.toStringAsFixed(1)}',
            less: speed <= .2
                ? null
                : () => unawaited(controller.setTuning(speed: speed - .1)),
            more: speed >= 2
                ? null
                : () => unawaited(controller.setTuning(speed: speed + .1)),
          ),
          const SizedBox(height: 4),
          row(
            icon: Icons.tune_rounded,
            label: 'Tono',
            value: pitch > 0 ? '+$pitch' : '$pitch',
            less: pitch <= -12
                ? null
                : () => unawaited(controller.setTuning(pitch: pitch - 1)),
            more: pitch >= 12
                ? null
                : () => unawaited(controller.setTuning(pitch: pitch + 1)),
          ),
          // Su hueco está siempre: si apareciera al cambiar un valor, la hoja
          // crecería y los botones se moverían bajo el dedo.
          Visibility(
            visible: speed != 1 || pitch != 0,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    unawaited(controller.setTuning(speed: 1, pitch: 0)),
                child: const Text('Restablecer'),
              ),
            ),
          ),
        ],
      );
    },
  ),
);

/// Información de la canción que suena: lo que Mysic sabe de ella.
Future<void> showSongInfoSheet(
  BuildContext context,
  CatalogTrack track,
  TrackPlaybackController controller,
) => _showSheet(context, (context) {
  final theme = Theme.of(context), colors = theme.colorScheme;
  final id = track.id.startsWith('youtube:') ? track.id.substring(8) : null;
  final store = DownloadStore.instance;
  final saved = id == null
      ? null
      : store.tracks.where((item) => item.id == id).firstOrNull;
  final length = controller.duration;
  final rows = <(String, String)>[
    ('Título', track.title),
    ('Artista', track.artistName),
    if (track.albumName != null) ('Álbum', track.albumName!),
    if (length != null && length > Duration.zero)
      ('Duración', audioTime(length))
    else if ((track.durationSeconds ?? 0) > 0)
      ('Duración', audioTime(Duration(seconds: track.durationSeconds!))),
    if (controller.speed != 1)
      ('Velocidad', 'x${controller.speed.toStringAsFixed(1)}'),
    if (controller.pitch != 0) ('Tono', '${controller.pitch} semitonos'),
    if (saved != null)
      (
        'Descargada',
        '${(saved.bytes / (1024 * 1024)).toStringAsFixed(1)} MB en este '
            'teléfono',
      ),
    if (id != null) ('Identificador', id),
  ];
  return _Frame(
    title: 'Información de la canción',
    children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(value, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
    ],
  );
});
