import 'package:flutter/material.dart';

import 'mysic_theme.dart';
import '../features/authentication/presentation/auth_gate.dart';

class MysicApp extends StatelessWidget {
  const MysicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mysic',
      // Oscuro siempre, como Limusic; el claro queda disponible en el código.
      themeMode: ThemeMode.dark,
      theme: mysicLightTheme(),
      darkTheme: mysicDarkTheme(),
      home: const AuthGate(),
    );
  }
}
