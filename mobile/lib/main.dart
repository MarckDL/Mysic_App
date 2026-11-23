import 'package:audio_service/audio_service.dart';
import 'features/playback/data/mysic_audio_handler.dart';
import 'features/playback/application/playback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/mysic_app.dart';
import 'core/network/offline_mode.dart';
import 'features/downloads/data/download_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portadas decodificadas en memoria: 160 MB (el valor por defecto es 100 MB).
  // Las descargas viven además en la caché de disco.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 << 20;
  // «Solo canciones descargadas» y el índice de descargas se leen antes de
  // abrir nada: así ninguna conexión sale con el modo activo. Corre a la vez
  // que el servicio de audio.
  final restored = Future.wait([
    OfflineMode.instance.restoreManual(),
    DownloadStore.instance.load(),
  ]);
  MysicAudioHandler? handler;
  {
    try {
      handler = MysicAudioHandler();
      await AudioService.init(
        builder: () => handler!,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.mysic.mysic.playback',
          androidNotificationChannelName: 'Reproducción de Mysic',
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_stat_music',
        ),
      );
    } catch (_) {
      debugPrint('audio_service_start_failed');
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'No se pudo iniciar el servicio de audio. Cierra y vuelve a abrir Mysic.',
              ),
            ),
          ),
        ),
      );
      return;
    }
  }
  await restored;
  runApp(
    ProviderScope(
      overrides: [mediaHandlerProvider.overrideWithValue(handler)],
      child: const MysicApp(),
    ),
  );
}
