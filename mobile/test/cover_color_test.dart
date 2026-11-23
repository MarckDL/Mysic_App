import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:mysic/app/mysic_theme.dart';
import 'package:mysic/core/images/cover_color.dart';
import 'package:mysic/core/images/disk_cached_image.dart';

ByteData pixels(List<(int, int, int)> colors, {int repeat = 100}) {
  final data = Uint8List(colors.length * repeat * 4);
  var i = 0;
  for (final (r, g, b) in colors) {
    for (var n = 0; n < repeat; n++) {
      data
        ..[i++] = r
        ..[i++] = g
        ..[i++] = b
        ..[i++] = 255;
    }
  }
  return ByteData.sublistView(data);
}

double hueOf(Color color) => Hct.fromInt(color.toARGB32()).hue;

/// Imagen de 8 × [rows] filas; cada fila es de un solo color.
ByteData rowsOf(List<(int, int, int)> rows) => pixels(rows, repeat: 8);

void main() {
  group('franjas negras', () {
    const black = (0, 0, 0), art = (200, 120, 40);

    test('un vídeo apaisado con el arte en el centro tiene franjas', () {
      // 12 filas: 4 negras, 4 de arte, 4 negras.
      final image = rowsOf([
        for (var i = 0; i < 4; i++) black,
        for (var i = 0; i < 4; i++) art,
        for (var i = 0; i < 4; i++) black,
      ]);
      expect(CoverColor.barsIn(image, 8, 12), isTrue);
    });

    test('las franjas finas de una miniatura normal no cuentan', () {
      // 12 filas: 1 negra arriba y abajo (≈8 %), el resto arte.
      final image = rowsOf([black, for (var i = 0; i < 10; i++) art, black]);
      expect(CoverColor.barsIn(image, 8, 12), isFalse);
    });

    test('una portada oscura solo por un lado no se descarta', () {
      final image = rowsOf([
        for (var i = 0; i < 6; i++) black,
        for (var i = 0; i < 6; i++) art,
      ]);
      expect(CoverColor.barsIn(image, 8, 12), isFalse);
    });
  });

  group('color de la carátula', () {
    test('elige el tono con más peso, no el fondo', () {
      // Mucho blanco y negro (fondo) y algo de azul: gana el azul.
      final color = CoverColor.fromRgba(
        pixels([(255, 255, 255), (0, 0, 0)], repeat: 400) // ignora los extremos
            .buffer
            .asByteData(),
      );
      expect(color, isNull);

      final blue = CoverColor.fromRgba(
        pixels([(240, 240, 240), (20, 20, 20), (30, 80, 220)]),
      );
      expect(blue, isNotNull);
      expect(hueOf(blue!), inInclusiveRange(240, 280));
    });

    test('una portada gris o transparente no tiñe el tema', () {
      expect(CoverColor.fromRgba(pixels([(128, 128, 128)])), isNull);
      final transparent = Uint8List(400)
        ..fillRange(0, 400, 0); // alfa 0 en todos los píxeles
      expect(CoverColor.fromRgba(ByteData.sublistView(transparent)), isNull);
    });

    test('con dos colores gana el más saturado y presente', () {
      final color = CoverColor.fromRgba(
        pixels([(210, 40, 40)], repeat: 300) // rojo vivo
          ..buffer.asUint8List(),
      );
      expect(hueOf(color!), anyOf(inInclusiveRange(0, 40), greaterThan(340)));
    });
  });

  group('tema teñido por la carátula', () {
    const red = Color(0xFFD22828);

    test('el acento toma el tono de la carátula y los textos no cambian', () {
      final base = mysicDarkTheme();
      final tinted = mysicDarkTheme(cover: red);
      final accent = tinted.colorScheme.primary;
      expect(hueOf(accent), anyOf(inInclusiveRange(0, 40), greaterThan(340)));
      // Acento en tono 70, como Limusic.
      expect(Hct.fromInt(accent.toARGB32()).tone, closeTo(70, 2));
      expect(tinted.colorScheme.onSurface, base.colorScheme.onSurface);
      expect(
        tinted.colorScheme.onSurfaceVariant,
        base.colorScheme.onSurfaceVariant,
      );
      expect(
        tinted.colorScheme.outlineVariant,
        base.colorScheme.outlineVariant,
      );
      expect(tinted.brightness, Brightness.dark);
    });

    test(
      'los fondos mantienen su tono y ganan croma 10 con el tono del color',
      () {
        final base = mysicDarkTheme();
        final tinted = mysicDarkTheme(cover: red);
        final baseTone = Hct.fromInt(
          base.scaffoldBackgroundColor.toARGB32(),
        ).tone;
        final background = Hct.fromInt(
          tinted.scaffoldBackgroundColor.toARGB32(),
        );
        expect(background.tone, closeTo(baseTone, 3));
        expect(background.chroma, lessThan(14));
        expect(
          hueOf(tinted.scaffoldBackgroundColor),
          isNot(closeTo(hueOf(base.scaffoldBackgroundColor), 1)),
        );
      },
    );

    test('sin color de carátula se mantiene el tema base', () {
      expect(
        mysicDarkTheme().colorScheme.primary,
        mysicDarkTheme(cover: null).colorScheme.primary,
      );
    });
  });

  group('caché de portadas', () {
    test('solo acepta direcciones https sin credenciales', () async {
      final cache = DiskImageCache.instance;
      await expectLater(
        cache.bytes('http://example.test/a.jpg'),
        throwsArgumentError,
      );
      await expectLater(cache.bytes('file:///etc/passwd'), throwsArgumentError);
      await expectLater(
        cache.bytes('https://usuario:clave@example.test/a.jpg'),
        throwsArgumentError,
      );
    });

    test('dos proveedores de la misma dirección son iguales', () {
      expect(
        const DiskCachedImage('https://example.test/a.jpg'),
        const DiskCachedImage('https://example.test/a.jpg'),
      );
      expect(
        const DiskCachedImage('https://example.test/a.jpg'),
        isNot(const DiskCachedImage('https://example.test/b.jpg')),
      );
    });
  });
}
