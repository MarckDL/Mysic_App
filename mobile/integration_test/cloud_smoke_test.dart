import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mysic/main.dart' as app;

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    if (finder.evaluate().isNotEmpty) return;
  }
  final visibleText = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .join(' | ');
  throw TestFailure(
    'No apareció el widget esperado en $timeout. Textos visibles: $visibleText',
  );
}

Future<void> waitRealTime(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sesión, catálogo, playlist y audio funcionan en la nube', (
    tester,
  ) async {
    await app.main();
    await pumpUntil(tester, find.text('Buscar música'));

    const playlistName = 'Validación cloud Sprint 7';
    await tester.tap(find.text('Mis playlists'));
    await pumpUntil(tester, find.text('Nueva'));
    if (find.text(playlistName).evaluate().isEmpty) {
      await tester.tap(find.text('Nueva'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, playlistName);
      await tester.tap(find.text('Crear'));
      await pumpUntil(tester, find.text(playlistName));
    }

    await tester.pageBack();
    await pumpUntil(tester, find.text('Buscar música'));
    await tester.tap(find.text('Buscar música'));
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Coldplay');
    await pumpUntil(tester, find.text('Reproducir resultados'));

    final results = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(ListTile),
    );
    expect(results, findsWidgets);
    await tester.ensureVisible(results.first);
    await tester.tap(results.first);
    await pumpUntil(tester, find.text('Detalle de canción'));
    await pumpUntil(tester, find.text('Añadir a playlist'));

    await tester.tap(find.text('Añadir a playlist'));
    await pumpUntil(tester, find.text(playlistName));
    await tester.tap(find.text(playlistName).first);
    await pumpUntil(tester, find.text('Reproducir audio'));

    await tester.tap(find.text('Reproducir audio'));
    await pumpUntil(tester, find.text('Pausar'));
    await waitRealTime(tester, const Duration(seconds: 75));
    expect(find.text('Pausar'), findsOneWidget);
    await tester.tap(find.text('Pausar'));

    await tester.pageBack();
    await pumpUntil(tester, find.text('Reproducir resultados'));
    await tester.pageBack();
    await pumpUntil(tester, find.text('Mis playlists'));
    await tester.tap(find.text('Mis playlists'));
    await pumpUntil(tester, find.text(playlistName));
    await tester.tap(find.text(playlistName).first);
    await pumpUntil(tester, find.textContaining('1 canción'));
  }, timeout: const Timeout(Duration(minutes: 8)));
}
