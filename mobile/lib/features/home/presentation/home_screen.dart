import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mysic')),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu espacio musical. Próximamente podrás iniciar sesión con Google.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
