import 'package:flutter/material.dart';

abstract final class MysicColors {
  static const background = Color(0xFFF8F7FB);
  static const surface = Colors.white;
  static const softSurface = Color(0xFFF0EDF7);
  static const primary = Color(0xFF7650C5);
  static const primaryDark = Color(0xFF56318F);
  static const player = Color(0xFF121214);
  static const playerSurface = Color(0xFF242428);
  static const outline = Color(0xFFE4E0EA);
}

ThemeData buildMysicTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MysicColors.primary,
    brightness: Brightness.light,
    surface: MysicColors.surface,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: MysicColors.background,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: MysicColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Color(0xFF17151B),
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: MysicColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: MysicColors.outline),
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: MysicColors.softSurface,
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: MysicColors.primary, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: MysicColors.softSurface,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? MysicColors.primary
              : const Color(0xFF5F5A68),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? MysicColors.primary
              : const Color(0xFF5F5A68),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    dividerTheme: const DividerThemeData(
      color: MysicColors.outline,
      thickness: 1,
      space: 1,
    ),
  );
}

ThemeData buildMysicPlayerTheme() => buildMysicTheme().copyWith(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: MysicColors.player,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF9A6AE5),
    brightness: Brightness.dark,
    surface: MysicColors.player,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: MysicColors.player,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    elevation: 0,
  ),
);
