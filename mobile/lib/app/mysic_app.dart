import 'package:flutter/material.dart';

import '../features/authentication/presentation/auth_gate.dart';

class MysicApp extends StatelessWidget {
  const MysicApp({super.key, this.firebaseReady = false});
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mysic',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: firebaseReady ? const AuthGate() : const _SetupPendingScreen(),
    );
  }
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
                  'El inicio de sesión todavía no está disponible en esta instalación.'),
            ),
          ),
        ),
      );
}
