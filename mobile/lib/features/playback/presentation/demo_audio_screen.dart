import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/demo_controller.dart';
import '../application/playback_providers.dart';
import '../domain/demo_audio_engine.dart';

class DemoAudioScreen extends ConsumerStatefulWidget {
  const DemoAudioScreen({super.key});
  @override
  ConsumerState<DemoAudioScreen> createState() => _DemoAudioScreenState();
}

class _DemoAudioScreenState extends ConsumerState<DemoAudioScreen>
    with WidgetsBindingObserver {
  DemoController? _controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final controller = _controller;
      if (controller != null) unawaited(controller.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(demoControllerProvider);
    _controller = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba de audio')),
      body: SafeArea(
        child: StreamBuilder<DemoState>(
          stream: controller.states,
          initialData: controller.state,
          builder: (context, snapshot) {
            final state = snapshot.data ?? controller.state;
            final loading = state.phase == DemoPhase.loading;
            final canPlay = [
              DemoPhase.ready,
              DemoPhase.paused,
              DemoPhase.completed,
            ].contains(state.phase);
            final label = switch (state.phase) {
              DemoPhase.idle => 'Carga el audio para comenzar.',
              DemoPhase.loading => 'Preparando audio…',
              DemoPhase.ready => 'Audio listo.',
              DemoPhase.playing => 'Reproduciendo.',
              DemoPhase.paused => 'En pausa. Pulsa Reproducir para continuar.',
              DemoPhase.completed =>
                'Prueba terminada. Puedes escucharla otra vez.',
              DemoPhase.error =>
                state.message ?? 'No se pudo reproducir el audio.',
            };
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.graphic_eq, size: 72),
                const SizedBox(height: 20),
                Text(
                  'Demostración Mysic',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Secuencia de tonos creada para Mysic · 8 segundos'),
                const SizedBox(height: 8),
                const Text('Usa un volumen moderado.'),
                const SizedBox(height: 24),
                Text(label, key: const Key('demo-status')),
                if (loading) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: loading ? null : controller.load,
                  child: const Text('Cargar audio de prueba'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canPlay ? controller.play : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    state.phase == DemoPhase.completed
                        ? 'Escuchar otra vez'
                        : 'Reproducir',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.phase == DemoPhase.playing
                      ? controller.pause
                      : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pausar'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
