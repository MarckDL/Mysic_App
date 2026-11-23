import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/settings/app_settings.dart';
import 'package:mysic/features/lyrics/data/lyrics_repository.dart';
import 'package:mysic/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('los ajustes cambian el color de la carátula y el desfase', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('APARIENCIA'), findsOneWidget);
    expect(find.text('LETRAS'), findsOneWidget);
    expect(find.text('ALMACENAMIENTO'), findsOneWidget);
    expect(container.read(adaptCoverColorProvider), isTrue);

    await tester.tap(find.text('Colores de la carátula'));
    await tester.pump();
    expect(container.read(adaptCoverColorProvider), isFalse);

    await tester.tap(find.byTooltip('Más 0,1 s'));
    await tester.pump();
    expect(container.read(lyricsOffsetProvider), 100);
    expect(find.text('+0.1 s'), findsOneWidget);
  });
}
