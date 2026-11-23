import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

const _titleFont = 'IBMPlexSans';

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

/// Los colores que cambian entre el tema claro y el oscuro. El resto del tema
/// (formas, tipografía, componentes) se deriva de ellos en [_mysicTheme].
class _Palette {
  const _Palette({
    required this.brightness,
    required this.canvas,
    required this.card,
    required this.raised,
    required this.ink,
    required this.secondaryInk,
    required this.accent,
    required this.onAccent,
    required this.tint,
    required this.onTint,
    required this.line,
    required this.outline,
    required this.handle,
  });

  final Brightness brightness;
  final Color canvas, card, raised, ink, secondaryInk;
  final Color accent, onAccent, tint, onTint, line, outline, handle;
}

ThemeData mysicLightTheme() => _mysicTheme(
  const _Palette(
    brightness: Brightness.light,
    canvas: Color(0xFFFBF8F5),
    card: Colors.white,
    raised: Color(0xFFF2ECE7),
    ink: Color(0xFF241F1D),
    secondaryInk: Color(0xFF61534D),
    accent: Color(0xFFA03820),
    onAccent: Colors.white,
    tint: Color(0xFFFFDFD3),
    onTint: Color(0xFF572A1A),
    line: Color(0xFFE2D8D2),
    outline: Color(0xFF88776E),
    handle: Color(0xFFB7A69E),
  ),
);

/// Tema oscuro por defecto, con la paleta de Limusic: negro con tinte magenta,
/// superficies que se distinguen por tono y un único acento carmesí.
/// Ver docs/19-analisis-limusic-android.md.
ThemeData mysicDarkTheme({Color? cover}) => _mysicTheme(
  cover == null ? _darkPalette : _tintedByCover(_darkPalette, cover),
);

const _darkPalette = _Palette(
  brightness: Brightness.dark,
  canvas: Color(0xFF0C090C),
  card: Color(0xFF1D161D),
  raised: Color(0xFF262126),
  ink: Color(0xFFFAFAFA),
  secondaryInk: Color(0xFFA89EA8),
  accent: Color(0xFFFF2056),
  onAccent: Colors.white,
  // El acento al 14 % sobre el fondo: indicador de pestaña y chips activos.
  tint: Color(0xFF2E0C16),
  onTint: Color(0xFFFFD9E0),
  line: Color(0xFF292629),
  outline: Color(0xFF7A697A),
  handle: Color(0xFF4A404A),
);

/// Paleta teñida con el color de la carátula, con las reglas de Limusic:
/// acento en tono 70 con croma de al menos 30; contenedor del acento en tono
/// 30 y fondos y superficies con croma 10 en su propio tono. El texto y los
/// bordes no cambian.
_Palette _tintedByCover(_Palette base, Color cover) {
  final seed = Hct.fromInt(cover.toARGB32());
  Color tone(double chroma, double tone) =>
      Color(Hct.from(seed.hue, chroma, tone).toInt());
  double toneOf(Color color) => Hct.fromInt(color.toARGB32()).tone;
  final accent = tone(math.max(seed.chroma, 30), 70);
  // Brillo percibido (HSP): sobre un acento claro, texto oscuro.
  final hsp = math.sqrt(
    .299 * accent.r * accent.r +
        .587 * accent.g * accent.g +
        .114 * accent.b * accent.b,
  );
  return _Palette(
    brightness: base.brightness,
    canvas: tone(10, toneOf(base.canvas)),
    card: tone(10, toneOf(base.card)),
    raised: tone(10, toneOf(base.raised)),
    ink: base.ink,
    secondaryInk: base.secondaryInk,
    accent: accent,
    onAccent: hsp > .6 ? const Color(0xFF171717) : const Color(0xFFFAFAFA),
    tint: tone(math.min(seed.chroma, 48), 30),
    onTint: tone(math.min(seed.chroma, 16), 90),
    line: base.line,
    outline: base.outline,
    handle: base.handle,
  );
}

ThemeData _mysicTheme(_Palette p) {
  final dark = p.brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: p.brightness,
      ).copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        primaryContainer: p.tint,
        onPrimaryContainer: p.onTint,
        secondary: dark ? const Color(0xFFE0B8A8) : const Color(0xFF6F4A39),
        secondaryContainer: p.tint,
        onSecondaryContainer: p.onTint,
        surface: p.canvas,
        onSurface: p.ink,
        onSurfaceVariant: p.secondaryInk,
        surfaceContainerLowest: p.card,
        surfaceContainerLow: dark
            ? const Color(0xFF161116)
            : const Color(0xFFF8F2ED),
        surfaceContainer: p.card,
        surfaceContainerHigh: p.raised,
        surfaceContainerHighest: p.raised,
        outline: p.outline,
        outlineVariant: p.line,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Las de Limusic: Oxanium para el texto y IBM Plex Sans para los títulos.
    fontFamily: 'Oxanium',
  );
  final type = base.textTheme;
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: p.line),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    textTheme: type.copyWith(
      headlineMedium: type.headlineMedium?.copyWith(fontFamily: _titleFont),
      headlineSmall: type.headlineSmall?.copyWith(
        fontFamily: _titleFont,
        fontWeight: FontWeight.w700,
        letterSpacing: -.65,
      ),
      titleLarge: type.titleLarge?.copyWith(
        fontFamily: _titleFont,
        fontWeight: FontWeight.w700,
        letterSpacing: -.45,
      ),
      titleMedium: type.titleMedium?.copyWith(
        fontFamily: _titleFont,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: p.canvas,
      foregroundColor: p.ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: p.brightness,
        systemNavigationBarColor: dark ? p.canvas : p.card,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        fontFamily: _titleFont,
        color: p.ink,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: BorderSide(color: p.accent, width: 2),
      ),
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      iconColor: p.secondaryInk,
      titleTextStyle: type.titleMedium?.copyWith(
        color: p.ink,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: type.bodyMedium?.copyWith(color: p.secondaryInk),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: dark ? Colors.transparent : p.card,
      selectedColor: dark ? p.accent : p.tint,
      showCheckmark: !dark,
      checkmarkColor: p.accent,
      shape: const StadiumBorder(),
      side: BorderSide(color: p.line),
      labelStyle: type.labelLarge?.copyWith(color: p.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      // Como en Limusic: la barra tiene el color del fondo, sin elevación.
      backgroundColor: dark ? p.canvas : p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.tint,
      elevation: 0,
      height: 74,
      iconTheme: WidgetStateProperty.resolveWith(
        (state) => IconThemeData(
          color: state.contains(WidgetState.selected)
              ? p.accent
              : p.secondaryInk,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (state) => type.labelMedium!.copyWith(
          color: state.contains(WidgetState.selected)
              ? p.accent
              : p.secondaryInk,
          fontWeight: state.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.raised,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.handle,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? p.raised : null,
      contentTextStyle: dark ? TextStyle(color: p.ink) : null,
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
  );
}
