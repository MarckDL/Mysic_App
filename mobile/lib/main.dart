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
  runApp(ProviderScope(child: MysicApp(firebaseReady: firebaseReady)));
}
