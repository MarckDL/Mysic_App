import 'package:flutter/material.dart';

import '../features/authentication/presentation/auth_gate.dart';

class MysicApp extends StatelessWidget {
  const MysicApp({super.key, this.firebaseReady = false});
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mysic',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: firebaseReady ? const AuthGate() : const _SetupPendingScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    ),
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationThemeData(
      border: OutlineInputBorder(),
      filled: true,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

class _SetupPendingScreen extends StatelessWidget {
  const _SetupPendingScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mysic')),
    body: const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El inicio de sesión todavía no está disponible en esta instalación.',
          ),
        ),
      ),
    ),
  );
}
