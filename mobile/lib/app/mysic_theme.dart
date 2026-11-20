import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MysicBrandMark extends StatelessWidget {
  const MysicBrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/mysic.png',
    width: size,
    height: size,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}

ThemeData mysicLightTheme() {
  const canvas = Color(0xFFFBF8F5);
  const ink = Color(0xFF241F1D);
  const secondaryInk = Color(0xFF61534D);
  const coral = Color(0xFFA03820);
  const peach = Color(0xFFFFDFD3);
  const line = Color(0xFFE2D8D2);
  const soft = Color(0xFFF2ECE7);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: coral,
        brightness: Brightness.light,
      ).copyWith(
        primary: coral,
        onPrimary: Colors.white,
        primaryContainer: peach,
        onPrimaryContainer: Color(0xFF4D1B0E),
        secondary: Color(0xFF6F4A39),
        secondaryContainer: peach,
        onSecondaryContainer: Color(0xFF572A1A),
        surface: canvas,
        onSurface: ink,
        onSurfaceVariant: secondaryInk,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFF8F2ED),
        surfaceContainer: Colors.white,
        surfaceContainerHigh: soft,
        surfaceContainerHighest: soft,
        outline: Color(0xFF88776E),
        outlineVariant: line,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
  );
  final type = base.textTheme;
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: line),
  );
  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    textTheme: type.copyWith(
      headlineSmall: type.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.65,
      ),
      titleLarge: type.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.45,
      ),
      titleMedium: type.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarThemeData(
      backgroundColor: canvas,
      foregroundColor: ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: ink,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: line),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: const BorderSide(color: coral, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      iconColor: secondaryInk,
      titleTextStyle: type.titleMedium?.copyWith(
        color: ink,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: type.bodyMedium?.copyWith(color: secondaryInk),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: peach,
      checkmarkColor: coral,
      shape: const StadiumBorder(),
      side: const BorderSide(color: line),
      labelStyle: type.labelLarge?.copyWith(color: ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: peach,
      elevation: 0,
      height: 74,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (state) => type.labelMedium!.copyWith(
          color: state.contains(WidgetState.selected) ? coral : secondaryInk,
          fontWeight: state.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0xFFB7A69E),
      showDragHandle: true,
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1),
  );
}
