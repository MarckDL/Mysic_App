import 'package:audio_service/audio_service.dart';
import 'features/playback/data/mysic_audio_handler.dart';
import 'features/playback/application/playback_providers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/mysic_app.dart';
import 'core/auth/firebase_client_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      FirebaseClientConfig.isConfigured) {
    try {
      await Firebase.initializeApp(options: FirebaseClientConfig.options);
      firebaseReady = true;
    } catch (_) {
      // Sin configuración válida no se permite entrar con una identidad local.
      firebaseReady = false;
    }
  }
  MysicAudioHandler? handler;
  if (firebaseReady) {
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
  runApp(
    ProviderScope(
      overrides: [mediaHandlerProvider.overrideWithValue(handler)],
      child: MysicApp(firebaseReady: firebaseReady),
    ),
  );
}
