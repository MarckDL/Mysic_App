import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

List<DialItem> _items(int count, List<String> taps) => [
  for (var i = 0; i < count; i++)
    (
      title: 'Casilla $i',
      subtitle: '',
      url: null,
      onTap: () => taps.add('$i'),
      onLongPress: null,
    ),
];

void main() {
  test('el collage solo se queda con páginas completas', () {
    List<int> n(int count) => List.generate(count, (i) => i);
    // Una sola página: filas completas de tres.
    expect(SpeedDialGrid.wholePages(n(0)), isEmpty);
    expect(SpeedDialGrid.wholePages(n(2)), n(2));
    expect(SpeedDialGrid.wholePages(n(7)), n(6));
    expect(SpeedDialGrid.wholePages(n(9)), n(9));
    // Varias: nunca una página con tres casillas y el resto vacío.
    expect(SpeedDialGrid.wholePages(n(12)), n(9));
    expect(SpeedDialGrid.wholePages(n(20)), n(18));
    expect(SpeedDialGrid.wholePages(n(27)), n(27));
    expect(SpeedDialGrid.wholePages(n(40)).length, 36);
  });

  testWidgets('con nueve casillas o menos el collage es una sola página', (
    tester,
  ) async {
    await tester.pumpWidget(_app(SpeedDialGrid(items: _items(9, []))));
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Casilla 8'), findsOneWidget);
  });

  testWidgets('con 27 casillas son tres páginas que se deslizan', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      _app(SpeedDialGrid(heading: 'Accesos directos', items: _items(27, taps))),
    );
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Casilla 0'), findsOneWidget);
    // La segunda página asoma, pero la tercera aún no está.
    expect(find.text('Casilla 18'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Casilla 18'), findsOneWidget);

    // Tocar una casilla de la tercera página toca la suya, no la de la
    // primera.
    await tester.tap(find.text('Casilla 20'));
    await tester.pump();
    expect(taps, ['20']);
    expect(tester.takeException(), isNull);
  });
}
