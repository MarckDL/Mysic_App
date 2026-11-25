import 'package:flutter/material.dart';

/// El logo de una emisora: un recurso de la app o una imagen `https`.
class RadioLogo extends StatelessWidget {
  const RadioLogo({super.key, required this.logo, required this.size});

  final String logo;
  final double size;

  @override
  Widget build(BuildContext context) => logo.startsWith('assets/')
      ? Image.asset(
          logo,
          width: size,
          height: size,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
        )
      : Image.network(
          logo,
          width: size,
          height: size,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
        );
}

/// La «portada» de una radio en directo: el degradado de sus dos colores con su
/// logo; sin logo, el icono de radio.
class LiveCover extends StatelessWidget {
  const LiveCover({
    super.key,
    required this.size,
    required this.colors,
    this.logo,
  });

  final double size;
  final List<int>? colors;
  final String? logo;

  static const _fallback = [0xFF3B4A6B, 0xFF1B2236];

  @override
  Widget build(BuildContext context) {
    final pair = colors != null && colors!.length == 2 ? colors! : _fallback;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(pair[0]), Color(pair[1])],
          ),
        ),
        child: Center(
          child: logo != null
              ? RadioLogo(logo: logo!, size: size * .78)
              : Icon(
                  Icons.radio_rounded,
                  size: size * .42,
                  color: Colors.white.withValues(alpha: .9),
                ),
        ),
      ),
    );
  }
}
