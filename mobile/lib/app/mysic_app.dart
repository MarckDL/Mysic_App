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
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationThemeData(
          border: OutlineInputBorder(),
          filled: true,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
      home: firebaseReady ? const AuthGate() : const _SetupPendingScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF745096),
          brightness: brightness,
        ).copyWith(
          primary: const Color(0xFF745096),
          onPrimary: Colors.white,
          surface: const Color(0xFFF8F6FB),
          onSurface: const Color(0xFF100E24),
          onSurfaceVariant: const Color(0xFF57546C),
          secondaryContainer: const Color(0xFFEEE7F5),
          surfaceContainerHighest: const Color(0xFFEEE9F3),
          outlineVariant: const Color(0xFFE8E3EE),
        ),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF8F6FB),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF8F6FB),
      foregroundColor: Color(0xFF100E24),
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: Color(0xFF100E24),
        fontSize: 23,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFFF8F6FB),
      indicatorColor: Color(0xFFEEE7F5),
    ),
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
