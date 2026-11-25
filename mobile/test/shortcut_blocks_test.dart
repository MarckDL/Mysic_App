import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/domain/shortcut.dart';
import 'package:mysic/features/connected_library/presentation/home_sheets.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

import 'support/ytm_test_client.dart';

class _Account extends MusicModeClient {
  _Account() : super(ytm: ytmTestClient(), ytmAccount: () => null);

  final prefs = <String, Map<String, dynamic>>{};

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      const MusicConnection(
        status: MusicLinkStatus.linked,
        generation: 'blocks',
        account: MusicAccount('channel', 'Cuenta A', false),
        provider: 'youtubeOAuth',
        personalization: 'full',
        capabilities: {'playlists', 'playback'},
      );

  @override
  Future<MusicPage> page(
    String generation,
    MusicSurface surface, {
    String? playlistId,
    String? query,
    String? cursor,
    CancelToken? cancelToken,
    bool remember = false,
  }) async => const MusicPage([], null, null, 0);

  @override
  Future<Map<String, dynamic>?> rememberedPrefs(String key) async => prefs[key];

  @override
  void rememberPrefs(String key, Map<String, dynamic> value) =>
      prefs[key] = value;
}

Shortcut _list(int n) =>
    Shortcut(ShortcutKind.playlist, 'PL$n', 'Lista $n', subtitle: 'Playlist');

({
  String title,
  String subtitle,
  String? url,
  IconData? icon,
  VoidCallback onTap,
  VoidCallback? onLongPress,
})
_item(int n) => (
  title: 'Lista $n',
  subtitle: 'Playlist',
  url: null,
  icon: Icons.queue_music,
  onTap: () {},
  onLongPress: null,
);

void main() {
  test('el tope son dos bloques de seis', () {
    expect(Shortcut.perBlock, 6);
    expect(Shortcut.max, 12);
  });

  group('mover atajos', () {
    test('cambia el orden, se guarda y otra sesión lo recupera', () async {
      final client = _Account();
      final controller = MusicModeController(client, () => true, () async {});
      addTearDown(controller.dispose);
      controller.defaultShortcuts = [for (var n = 0; n < 4; n++) _list(n)];

      // Sin haber tocado nada también se puede ordenar (parte de los de fábrica).
      expect(controller.moveShortcut(0, 2), isTrue);
      expect(controller.effectiveShortcuts.map((s) => s.id), [
        'PL1',
        'PL2',
        'PL0',
        'PL3',
      ]);
      expect((client.prefs['shortcuts']!['items'] as List).length, 4);

      final later = MusicModeController(client, () => true, () async {});
      addTearDown(later.dispose);
      await later.restoreHome();
      expect(later.effectiveShortcuts.map((s) => s.id), [
        'PL1',
        'PL2',
        'PL0',
        'PL3',
      ]);
    });

    test('lo imposible no cambia nada', () {
      final client = _Account();
      final controller = MusicModeController(client, () => true, () async {});
      addTearDown(controller.dispose);
      controller.defaultShortcuts = [for (var n = 0; n < 3; n++) _list(n)];
      expect(controller.moveShortcut(1, 1), isFalse);
      expect(controller.moveShortcut(-1, 0), isFalse);
      expect(controller.moveShortcut(0, 3), isFalse);
      expect(controller.moveShortcut(5, 0), isFalse);
      // Nada se guardó.
      expect(client.prefs, isEmpty);
      expect(controller.shortcuts.value, isNull);
    });

    test('un atajo pasa de un bloque al otro al moverlo', () {
      final client = _Account();
      final controller = MusicModeController(client, () => true, () async {});
      addTearDown(controller.dispose);
      controller.defaultShortcuts = [for (var n = 0; n < 12; n++) _list(n)];
      // El primero del bloque 1 pasa al último del bloque 2.
      controller.moveShortcut(0, 11);
      expect(controller.effectiveShortcuts.last.id, 'PL0');
      expect(controller.effectiveShortcuts.first.id, 'PL1');
      expect(controller.effectiveShortcuts, hasLength(12));
    });
  });

  group('«De one pe» en bloques', () {
    Future<void> pump(
      WidgetTester tester,
      int count, {
      VoidCallback? onReorder,
    }) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnePeShortcuts(
                items: [for (var n = 0; n < count; n++) _item(n)],
                onReorder: onReorder,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('doce atajos: seis y seis, con un hueco entre bloques', (
      tester,
    ) async {
      await pump(tester, 12);
      for (var n = 0; n < 12; n++) {
        expect(find.text('Lista $n'), findsOneWidget, reason: 'Lista $n');
      }
      // Los seis primeros en dos columnas y tres filas…
      final firstBlock = [
        for (var n = 0; n < 6; n++) tester.getTopLeft(find.text('Lista $n')),
      ];
      expect(firstBlock.map((p) => p.dx).toSet(), hasLength(2));
      expect(firstBlock.map((p) => p.dy).toSet(), hasLength(3));
      // …y el séptimo empieza más abajo que el sexto con un hueco mayor que
      // el normal entre filas.
      final rowStep =
          tester.getTopLeft(find.text('Lista 2')).dy -
          tester.getTopLeft(find.text('Lista 0')).dy;
      final blockStep =
          tester.getTopLeft(find.text('Lista 6')).dy -
          tester.getTopLeft(find.text('Lista 4')).dy;
      expect(blockStep, greaterThan(rowStep));
      expect(tester.takeException(), isNull);
    });

    testWidgets('con ocho se ven los ocho (seis y dos)', (tester) async {
      await pump(tester, 8);
      for (var n = 0; n < 8; n++) {
        expect(find.text('Lista $n'), findsOneWidget);
      }
    });

    testWidgets('la tuerca solo sale si hay con qué ordenar', (tester) async {
      await pump(tester, 3);
      expect(find.byTooltip('Ordenar atajos'), findsNothing);
      var taps = 0;
      await pump(tester, 3, onReorder: () => taps++);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('Ordenar atajos'));
      expect(taps, 1);
    });
  });

  group('la hoja «Ordenar atajos»', () {
    Future<(_Account, MusicModeController)> open(WidgetTester tester) async {
      final client = _Account();
      final controller = MusicModeController(client, () => true, () async {});
      addTearDown(controller.dispose);
      controller.defaultShortcuts = [for (var n = 0; n < 8; n++) _list(n)];
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext context;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MusicModeHost(
              controller: controller,
              child: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(showShortcutOrder(context, controller));
      await tester.pumpAndSettle();
      return (client, controller);
    }

    testWidgets('lista los atajos con su bloque y sin botón de aceptar', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Ordenar atajos'), findsOneWidget);
      for (var n = 0; n < 8; n++) {
        expect(find.text('Lista $n'), findsOneWidget, reason: 'Lista $n');
      }
      // Seis en el Bloque 1 y dos en el Bloque 2.
      expect(find.text('Bloque 1'), findsNWidgets(6));
      expect(find.text('Bloque 2'), findsNWidgets(2));
      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(8));
      expect(find.text('Aceptar'), findsNothing);
      expect(find.text('Guardar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('arrastrar por el asa cambia el orden y lo guarda', (
      tester,
    ) async {
      final (client, controller) = await open(tester);
      // «Lista 0» al final (tras la octava).
      final handle = find.byIcon(Icons.drag_handle_rounded).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, 8 * 70));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.effectiveShortcuts.first.id, isNot('PL0'));
      expect(controller.effectiveShortcuts.last.id, 'PL0');
      expect(controller.effectiveShortcuts, hasLength(8));
      expect((client.prefs['shortcuts']!['items'] as List).length, 8);
      // Y el bloque que dice cada fila sigue el nuevo orden: seis y dos.
      expect(find.text('Bloque 1'), findsNWidgets(6));
      expect(find.text('Bloque 2'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}
