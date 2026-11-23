import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/search/presentation/item_sheet.dart';

Widget _host(void Function(BuildContext) open) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => open(context),
          child: const Text('abrir'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('la hoja muestra cabecera, acciones rápidas y filas', (
    tester,
  ) async {
    var next = 0, dismissedRow = 0;
    await tester.pumpWidget(
      _host(
        (context) => showItemSheet(
          context,
          header: const SheetHeader(
            title: 'blackout',
            subtitle: 'dusky • blackout',
          ),
          tiles: () => [
            SheetTile(
              icon: Icons.play_circle_outline,
              label: 'A continuación',
              onTap: () => next++,
            ),
            const SheetTile(
              icon: Icons.queue_music,
              label: 'Añadir a la cola',
              onTap: null,
            ),
            SheetTile(icon: Icons.link, label: 'Copiar enlace', onTap: () {}),
          ],
          rows: () => [
            SheetRow(
              icon: Icons.album,
              label: 'Ir al álbum',
              onTap: () => dismissedRow++,
            ),
            SheetRow(
              icon: Icons.delete_outline,
              label: 'Quitar descarga',
              destructive: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('blackout'), findsOneWidget);
    expect(find.text('dusky • blackout'), findsOneWidget);
    expect(find.text('A continuación'), findsOneWidget);
    expect(find.text('Ir al álbum'), findsOneWidget);

    // Una acción rápida cierra la hoja y se ejecuta.
    await tester.tap(find.text('A continuación'));
    await tester.pumpAndSettle();
    expect(next, 1);
    expect(find.text('Ir al álbum'), findsNothing);

    // Una fila también.
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ir al álbum'));
    await tester.pumpAndSettle();
    expect(dismissedRow, 1);
    expect(find.text('Quitar descarga'), findsNothing);
  });

  testWidgets('una acción sin función no hace nada y la hoja sigue abierta', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        (context) => showItemSheet(
          context,
          tiles: () => const [
            SheetTile(
              icon: Icons.queue_music,
              label: 'Añadir a la cola',
              onTap: null,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a la cola'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir a la cola'), findsOneWidget);
  });

  testWidgets('«Descargar» deja la hoja abierta y refleja el avance', (
    tester,
  ) async {
    final refresh = ValueNotifier<double?>(null);
    var taps = 0;
    await tester.pumpWidget(
      _host(
        (context) => showItemSheet(
          context,
          refresh: refresh,
          tiles: () => [
            SheetTile(
              icon: Icons.download_for_offline_outlined,
              label: refresh.value == null ? 'Descargar' : 'Descargando',
              progress: refresh.value,
              closes: false,
              onTap: refresh.value == null ? () => taps++ : null,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    // Sigue abierta.
    expect(find.text('Descargar'), findsOneWidget);
    refresh.value = .4;
    await tester.pump();
    expect(find.text('Descargando'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('con «Reproducir» y aleatorio ambos cierran la hoja', (
    tester,
  ) async {
    var play = 0, shuffle = 0;
    await tester.pumpWidget(
      _host(
        (context) => showItemSheet(
          context,
          onPlay: () => play++,
          onShuffle: () => shuffle++,
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aleatorio'));
    await tester.pumpAndSettle();
    expect((play, shuffle), (0, 1));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reproducir'));
    await tester.pumpAndSettle();
    expect((play, shuffle), (1, 1));
  });
}
