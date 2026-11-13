import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/app/mysic_theme.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';
import 'package:mysic/features/home/presentation/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('el tema visual mantiene fondo, acento y controles táctiles', (
    tester,
  ) async {
    final theme = buildMysicTheme();
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF8F7FB));
    expect(theme.colorScheme.primary, isNot(equals(Colors.black)));
    expect(
      theme.iconButtonTheme.style?.minimumSize?.resolve({}),
      const Size(44, 44),
    );
  });

  for (final size in [const Size(320, 568), const Size(430, 932)]) {
    testWidgets('Inicio se adapta a ${size.width.toInt()} px', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildMysicTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.3),
              ),
              child: const HomeScreen(
                profile: MysicProfile(
                  id: '00000000-0000-4000-8000-000000000001',
                  firebaseUid: 'visual-test',
                  displayName: 'Dino',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hola, Dino 👋'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
