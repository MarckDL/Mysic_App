import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

void main() {
  testWidgets('el contacto avisa al instante y no impide el toque', (
    tester,
  ) async {
    var touches = 0, taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TouchWarm(
              onTouch: () => touches++,
              child: InkWell(
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 60, child: Text('x')),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.text('x')));
    // En cuanto el dedo toca, antes de levantarlo.
    expect(touches, 1);
    expect(taps, 0);
    await gesture.up();
    await tester.pump();
    // El toque sigue funcionando.
    expect(taps, 1);
    expect(touches, 1);
  });

  testWidgets('una fila que se queda a la vista avisa una sola vez', (
    tester,
  ) async {
    var lingers = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TouchWarm(
          onTouch: null,
          onLinger: () => lingers++,
          child: const Text('z'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 399));
    expect(lingers, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(lingers, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(lingers, 1);
  });

  testWidgets('una fila que sale antes de tiempo no avisa', (tester) async {
    var lingers = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TouchWarm(
          onTouch: null,
          onLinger: () => lingers++,
          child: const Text('z'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 2));
    expect(lingers, 0);
  });

  testWidgets(
    'en una lista solo calientan las filas visibles y con la lista quieta',
    (tester) async {
      final lingered = <int>{};
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: controller,
              // Filas altas: solo unas pocas caben; el resto queda en la zona de
              // reserva o fuera de la lista.
              itemExtent: 100,
              itemCount: 200,
              itemBuilder: (context, i) => TouchWarm(
                key: ValueKey(i),
                onTouch: null,
                onLinger: () => lingered.add(i),
                child: Text('fila $i'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));
      expect(lingered, isNotEmpty);
      // Ninguna de las que solo están en la zona de reserva fuera de pantalla.
      expect(lingered.every((i) => i < 8), isTrue);
      lingered.clear();
      // Durante el desplazamiento no se calienta nada; al detenerse, las
      // visibles de la zona nueva.
      controller.jumpTo(5000);
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(100, 300));
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 450));
      expect(lingered, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));
      expect(lingered.any((i) => i >= 45), isTrue);
    },
  );

  testWidgets('sin función, TouchWarm no añade nada', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TouchWarm(onTouch: null, child: Text('y'))),
    );
    expect(
      find.descendant(
        of: find.byType(TouchWarm),
        matching: find.byType(Listener),
      ),
      findsNothing,
    );
    expect(find.text('y'), findsOneWidget);
  });
}
