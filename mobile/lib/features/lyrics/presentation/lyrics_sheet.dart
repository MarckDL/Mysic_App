import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/application/track_playback_controller.dart';
import '../../playback/domain/track_audio_engine.dart' show TrackAudioPhase;
import '../../search/domain/catalog_track.dart';
import '../../search/presentation/music_tiles.dart' show Skeleton;
import '../data/lyrics_repository.dart';
import '../domain/lyrics_provider.dart';

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.controller});

  final TrackPlaybackController controller;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  CatalogTrack? _track;

  @override
  void initState() {
    super.initState();
    _track = widget.controller.current;
    widget.controller.addListener(_updateTrack);
  }

  void _updateTrack() {
    final next = widget.controller.current;
    if (identical(next, _track)) return;
    setState(() => _track = next);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateTrack);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return SafeArea(
      top: false,
      child: track == null || widget.controller.isDemoTrack
          ? const Center(child: Text('No hay letra para este audio.'))
          : _LyricsForTrack(
              key: ValueKey(track.id),
              track: track,
              controller: widget.controller,
            ),
    );
  }
}

class _LyricsForTrack extends ConsumerWidget {
  const _LyricsForTrack({
    super.key,
    required this.track,
    required this.controller,
  });

  final CatalogTrack track;
  final TrackPlaybackController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = trackLyricsProvider(track);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: ref
              .watch(provider)
              .when(
                skipLoadingOnRefresh: false,
                loading: () => const _LyricsSkeleton(),
                error: (_, _) => Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('No se pudo cargar la letra.'),
                        TextButton(
                          onPressed: () => ref.invalidate(provider),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (lyrics) {
                  if (lyrics != null && lyrics.isSynced) {
                    return _TimedLyrics(
                      key: ObjectKey(lyrics),
                      lyrics: lyrics,
                      controller: controller,
                    );
                  }
                  final plain = lyrics?.plain;
                  if (plain == null) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                      children: [
                        Text(
                          'No encontramos letra para esta canción.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  }
                  return _PlainLyrics(
                    key: ValueKey(plain),
                    text: plain,
                    source: lyrics?.source,
                  );
                },
              ),
        ),
      ],
    );
  }
}

/// Letra sin tiempos: cada línea aparece con un fundido y un leve ascenso,
/// una tras otra (las primeras 18; el resto entra junto a la última). Con las
/// animaciones del sistema desactivadas se muestra de golpe.
class _PlainLyrics extends StatefulWidget {
  const _PlainLyrics({super.key, required this.text, this.source});

  final String text;
  final String? source;

  @override
  State<_PlainLyrics> createState() => _PlainLyricsState();
}

class _PlainLyricsState extends State<_PlainLyrics>
    with SingleTickerProviderStateMixin {
  static const _staggered = 18;
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final List<String> _lines = widget.text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trimRight())
      .toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else if (!_enter.isAnimating && _enter.value == 0) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium?.copyWith(
      height: 1.5,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: .9),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      children: [
        for (var i = 0; i < _lines.length; i++)
          _line(_lines[i], style, i.clamp(0, _staggered)),
        if (widget.source != null) _Attribution(source: widget.source),
      ],
    );
  }

  Widget _line(String text, TextStyle? style, int order) {
    if (text.isEmpty) return const SizedBox(height: 18);
    // Cada línea ocupa un tramo de 0,35 del recorrido, escalonado hasta 1.
    final start = order / _staggered * .65;
    final fade = CurvedAnimation(
      parent: _enter,
      curve: Interval(start, start + .35, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .35),
          end: Offset.zero,
        ).animate(fade),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: SelectableText(text, style: style),
        ),
      ),
    );
  }
}

/// Barras que laten mientras se busca la letra (8 de 24 dp, como en Limusic).
class _LyricsSkeleton extends StatelessWidget {
  const _LyricsSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Buscando la letra',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 8; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Skeleton.block(
                  context,
                  width: 140.0 + (i * 47) % 150,
                  height: 24,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Letra sincronizada, con el estilo "Classic" de Limusic: 26 sp en negrita,
/// la línea cantada al 100 %, las que vienen al 70 % y las que ya pasaron al
/// 40 %; la activa crece un 4 % y se centra al cambiar. Si la fuente trae
/// tiempos por palabra, la línea activa se colorea palabra a palabra.
class _TimedLyrics extends ConsumerStatefulWidget {
  const _TimedLyrics({
    super.key,
    required this.lyrics,
    required this.controller,
  });

  final SongLyrics lyrics;
  final TrackPlaybackController controller;

  @override
  ConsumerState<_TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends ConsumerState<_TimedLyrics> {
  late final _lineKeys = List.generate(
    widget.lyrics.lines.length,
    (_) => GlobalKey(),
  );
  var _active = -1;

  // Referencia para extrapolar la posición entre dos avisos del reproductor.
  // Un cronómetro propio: el reloj de fotogramas no existe fuera de un
  // fotograma, y los avisos del reproductor llegan en cualquier momento.
  Duration _basePosition = Duration.zero;
  final _sinceBase = Stopwatch()..start();

  Duration get _offset =>
      Duration(milliseconds: ref.read(lyricsOffsetProvider));

  @override
  void initState() {
    super.initState();
    _rebase();
    _active = _lineFor(_basePosition);
    // Los saltos y cambios de estado llegan por el controlador; el avance
    // normal, por su aviso de posición.
    widget.controller.addListener(_positionChanged);
    widget.controller.positionListenable.addListener(_positionChanged);
    _followLine();
  }

  void _rebase() {
    _basePosition = widget.controller.position;
    _sinceBase.reset();
  }

  /// Posición de las letras ahora: la del reproductor, extrapolada si suena,
  /// menos el desfase del usuario.
  Duration _live() {
    var position = _basePosition;
    if (widget.controller.phase == TrackAudioPhase.playing) {
      final elapsed = _sinceBase.elapsed;
      // La referencia puede quedar rancia si no llegan avisos: máximo 1 s.
      if (elapsed < const Duration(seconds: 1)) {
        position += elapsed;
      }
    }
    return position - _offset;
  }

  int _lineFor(Duration position) => widget.lyrics.lineAt(position - _offset);

  void _positionChanged() {
    _rebase();
    final next = _lineFor(_basePosition);
    if (next == _active) return;
    setState(() => _active = next);
    _followLine();
  }

  void _followLine() {
    final index = _active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _active) return;
      final context = _lineKeys[index < 0 ? 0 : index].currentContext;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(
            context,
            alignment: index < 0 ? 0 : .4,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_positionChanged);
    widget.controller.positionListenable.removeListener(_positionChanged);
    super.dispose();
  }

  Duration _endOf(int index) {
    final lines = widget.lyrics.lines;
    if (index + 1 < lines.length) return lines[index + 1].start;
    return lines[index].start + const Duration(seconds: 6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    // Un cambio de desfase recalcula la línea activa.
    ref.listen(lyricsOffsetProvider, (_, _) {
      final next = _lineFor(widget.controller.position);
      if (next != _active) {
        setState(() => _active = next);
        _followLine();
      }
    });
    final style = theme.textTheme.titleLarge!.copyWith(
      fontSize: 26,
      height: 1.3,
      fontWeight: FontWeight.w700,
    );
    final lines = widget.lyrics.lines;
    return Column(
      children: [
        Expanded(
          // Bordes que se desvanecen, como la máscara de Limusic.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .06, .9, 1],
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
            ).createShader(rect),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                10,
                24,
                MediaQuery.sizeOf(context).height * .3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, line) in lines.indexed)
                    Padding(
                      key: _lineKeys[index],
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: line.text.isEmpty
                          ? const SizedBox(height: 4)
                          : _LyricLineView(
                              line: line,
                              end: _endOf(index),
                              style: style,
                              state: index == _active
                                  ? _LineState.active
                                  : index < _active
                                  ? _LineState.past
                                  : _LineState.upcoming,
                              position: _live,
                              ink: colors.onSurface,
                              onTap: () => unawaited(
                                // Al inicio de la línea más el desfase, +50 ms.
                                widget.controller.seek(
                                  line.start +
                                      _offset +
                                      const Duration(milliseconds: 50),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _LyricsFooter(source: widget.lyrics.source),
      ],
    );
  }
}

enum _LineState { past, active, upcoming }

class _LyricLineView extends StatelessWidget {
  const _LyricLineView({
    required this.line,
    required this.end,
    required this.style,
    required this.state,
    required this.position,
    required this.ink,
    required this.onTap,
  });

  final LyricLine line;
  final Duration end;
  final TextStyle style;
  final _LineState state;
  final Duration Function() position;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = state == _LineState.active;
    final alpha = switch (state) {
      _LineState.active => 1.0,
      _LineState.upcoming => .7,
      _LineState.past => .4,
    };
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedScale(
          scale: active ? 1.04 : 1,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 300),
          child: AnimatedOpacity(
            opacity: alpha,
            duration: const Duration(milliseconds: 300),
            child: active && line.hasWords
                ? _WordSweep(
                    line: line,
                    end: end,
                    style: style.copyWith(color: ink),
                    position: position,
                  )
                : Text(line.text, style: style.copyWith(color: ink)),
          ),
        ),
      ),
    );
  }
}

/// La línea activa con palabra a palabra: cada palabra pasa del color
/// pendiente (la tinta al 70 %) al cantado según su avance, a cada fotograma.
class _WordSweep extends StatefulWidget {
  const _WordSweep({
    required this.line,
    required this.end,
    required this.style,
    required this.position,
  });

  final LyricLine line;
  final Duration end;
  final TextStyle style;
  final Duration Function() position;

  @override
  State<_WordSweep> createState() => _WordSweepState();
}

class _WordSweepState extends State<_WordSweep>
    with SingleTickerProviderStateMixin {
  late final _now = ValueNotifier<Duration>(widget.position());
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _now.value = widget.position())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  double _progress(int index, Duration position) {
    final words = widget.line.words;
    final start = words[index].start;
    final end = index + 1 < words.length ? words[index + 1].start : widget.end;
    final span = (end - start).inMilliseconds;
    if (span <= 0) return position >= start ? 1 : 0;
    return ((position - start).inMilliseconds / span)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.style.color ?? Colors.white;
    final pending = ink.withValues(alpha: .7);
    return ValueListenableBuilder<Duration>(
      valueListenable: _now,
      builder: (context, position, _) => Text.rich(
        TextSpan(
          style: widget.style,
          children: [
            for (final (index, word) in widget.line.words.indexed)
              TextSpan(
                text: word.text,
                style: TextStyle(
                  color: Color.lerp(pending, ink, _progress(index, position)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pie con la fuente y el control de desfase `[−] valor [+] [↺]`.
class _LyricsFooter extends ConsumerWidget {
  const _LyricsFooter({required this.source});

  final String? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final offset = ref.watch(lyricsOffsetProvider);
    final notifier = ref.read(lyricsOffsetProvider.notifier);
    final label =
        '${offset >= 0 ? '+' : '−'}'
        '${(offset.abs() / 1000).toStringAsFixed(1)} s';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              source == null ? '' : 'Letras de $source',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Adelantar la letra 0,1 s',
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.change(-LyricsOffset.step),
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 64,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'Retrasar la letra 0,1 s',
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.change(LyricsOffset.step),
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'Restablecer el desfase',
            visualDensity: VisualDensity.compact,
            onPressed: offset == 0 ? null : notifier.reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({this.source});

  final String? source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Text(source == null ? 'Letras' : 'Letras de $source'),
  );
}
