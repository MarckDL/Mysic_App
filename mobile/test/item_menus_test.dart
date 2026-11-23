import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/connected_library/domain/shortcut.dart';
import 'package:mysic/features/connected_library/presentation/library_screen.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_host.dart';
import 'package:mysic/features/connected_library/presentation/music_mode_screen.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

import 'support/ytm_test_client.dart';

const _artist = 'UCaaaaaaaaaaaaaaaaaaaaaa';

class _Account extends MusicModeClient {
  _Account() : super(ytm: ytmTestClient(), ytmAccount: () => null);

  final prefs = <String, Map<String, dynamic>>{};

  /// La playlist es de la cuenta.
  var own = true;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) async =>
      const MusicConnection(
        status: MusicLinkStatus.linked,
        generation: 'menus',
        account: MusicAccount('channel', 'Cuenta A', false),
        provider: 'youtubeOAuth',
        personalization: 'full',
        capabilities: {'playlists', 'liked', 'artists', 'playback'},
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
  }) async => switch (surface) {
    MusicSurface.playlists => const MusicPage(
      [MusicPlaylist('PLaaaaaaaaaa', 'Para correr', true)],
      null,
      null,
      0,
    ),
    MusicSurface.playlist => MusicPage(const [], null, null, 0, null, own),
    MusicSurface.liked => const MusicPage(
      [
        MusicTrack(
          'aaaaaaaaaaa',
          'Around the World',
          'Daft Punk',
          430,
          false,
          null,
          nativePlayback: true,
        ),
      ],
      null,
      null,
      0,
    ),
    MusicSurface.artists => const MusicPage(
      [MusicArtist(_artist, 'Daft Punk')],
      null,
      null,
      0,
    ),
    _ => const MusicPage([], null, null, 0),
  };

  @override
  Future<Map<String, dynamic>?> rememberedPrefs(String key) async => prefs[key];

  @override
  void rememberPrefs(String key, Map<String, dynamic> value) =>
      prefs[key] = value;
}

Future<(_Account, MusicModeController)> _pump(WidgetTester tester) async {
  final client = _Account();
  final controller = MusicModeController(client, () => true, () async {});
  addTearDown(controller.dispose);
  // Alto de teléfono: las hojas caben enteras.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MusicModeHost(
          controller: controller,
          child: const MusicModeSurface(surface: MusicSurface.songs),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (client, controller);
}

void main() {
  setUpAll(() => NowPlayingBars.animationsEnabled = false);

  testWidgets('la hoja de una playlist propia lleva todas las filas', (
    tester,
  ) async {
    final (_, controller) = await _pump(tester);
    await tester.longPress(find.text('Para correr'));
    await tester.pumpAndSettle();
    for (final label in [
      'Reproducir',
      'A continuación',
      'Añadir a la cola',
      'Iniciar radio',
      'Guardar en playlist',
      'Compartir',
      'Añadir a atajos',
      // Solo en una playlist de la cuenta, cuando se sabe que lo es.
      'Editar playlist',
      'Eliminar playlist',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byTooltip('Aleatorio'), findsOneWidget);

    await tester.tap(find.text('Añadir a atajos'));
    await tester.pumpAndSettle();
    expect(
      controller.isShortcut(
        const Shortcut(ShortcutKind.playlist, 'PLaaaaaaaaaa', 'Para correr'),
      ),
      isTrue,
    );
    // Al volver a abrirla, la fila ofrece quitarlo.
    await tester.longPress(find.text('Para correr'));
    await tester.pumpAndSettle();
    expect(find.text('Quitar de atajos'), findsOneWidget);
    expect(find.text('Añadir a atajos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una playlist ajena no se puede editar ni eliminar', (
    tester,
  ) async {
    final (client, _) = await _pump(tester);
    client.own = false;
    await tester.longPress(find.text('Para correr'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar en playlist'), findsOneWidget);
    expect(find.text('Editar playlist'), findsNothing);
    expect(find.text('Eliminar playlist'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la hoja de una canción lleva sus acciones y su lista', (
    tester,
  ) async {
    await _pump(tester);
    await tester.longPress(find.text('Around the World'));
    await tester.pumpAndSettle();
    for (final label in [
      'A continuación',
      'Añadir a la cola',
      'Guardar en playlist',
      'Descargar',
      'Iniciar radio',
      'No me gusta',
      'Compartir',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // «Guardar en playlist» abre el selector, con crear una nueva lo primero.
    await tester.tap(find.text('Guardar en playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva playlist'), findsOneWidget);
    expect(find.text('«Around the World»'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Para correr'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la hoja de un artista ofrece radio, dejar de seguir y compartir',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(LibraryChip, 'Artistas'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Daft Punk'));
      await tester.pumpAndSettle();
      expect(find.text('Iniciar radio'), findsOneWidget);
      // Está en la lista de la Biblioteca: ya se le sigue.
      expect(find.text('Dejar de seguir'), findsOneWidget);
      expect(find.text('Compartir'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'los atajos se fijan, se quitan, se guardan y no pasan de ocho',
    () async {
      final client = _Account();
      final controller = MusicModeController(client, () => true, () async {});
      addTearDown(controller.dispose);
      Shortcut playlist(int n) =>
          Shortcut(ShortcutKind.playlist, 'PL$n', 'Lista $n');

      // Sin tocar nada valen los de fábrica.
      controller.defaultShortcuts = [playlist(0)];
      expect(controller.effectiveShortcuts.single.id, 'PL0');
      expect(controller.shortcuts.value, isNull);

      // El primer cambio parte de los de fábrica y ya se guarda.
      controller.toggleShortcut(playlist(1));
      expect(controller.effectiveShortcuts.map((s) => s.id), ['PL0', 'PL1']);
      expect((client.prefs['shortcuts']!['items'] as List).length, 2);

      controller.toggleShortcut(playlist(0));
      expect(controller.effectiveShortcuts.map((s) => s.id), ['PL1']);

      for (var n = 2; n < 12; n++) {
        controller.toggleShortcut(playlist(n));
      }
      expect(controller.effectiveShortcuts, hasLength(Shortcut.max));
      expect(controller.shortcutsFull, isTrue);

      // Otra sesión de la misma cuenta los recupera.
      final later = MusicModeController(client, () => true, () async {});
      addTearDown(later.dispose);
      await later.restoreHome();
      expect(later.effectiveShortcuts, hasLength(Shortcut.max));
      expect(later.effectiveShortcuts.first.id, 'PL1');
    },
  );

  test('la disposición de Inicio se guarda por cuenta', () async {
    final client = _Account();
    final controller = MusicModeController(client, () => true, () async {});
    addTearDown(controller.dispose);
    expect(controller.homeLayout.value.chips, isTrue);
    controller.setHomeLayout(
      controller.homeLayout.value.copyWith(chips: false, dial: false),
    );
    final later = MusicModeController(client, () => true, () async {});
    addTearDown(later.dispose);
    await later.restoreHome();
    expect(later.homeLayout.value.chips, isFalse);
    expect(later.homeLayout.value.dial, isFalse);
    expect(later.homeLayout.value.shortcuts, isTrue);
  });
}
