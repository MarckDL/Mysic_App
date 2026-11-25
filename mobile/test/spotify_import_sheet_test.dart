import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';
import 'package:mysic/features/spotify_import/application/spotify_import_controller.dart';
import 'package:mysic/features/spotify_import/domain/spotify_link.dart';
import 'package:mysic/features/spotify_import/presentation/spotify_import_sheet.dart';

SpotifyImportController _controller({List<List<String>>? created}) =>
    SpotifyImportController(
      retryDelay: Duration.zero,
      fetch: (id) async => const SpotifyPlaylist(
        name: 'Mi lista',
        owner: 'Yo',
        tracks: [
          SpotifyTrack('Uno', ['Banda Uno']),
          SpotifyTrack('Dos', ['Banda Dos']),
        ],
      ),
      search: (query) async {
        final name = query.split(' ').first;
        return [
          MusicTrack(
            name == 'Uno' ? 'aaaaaaaaaaa' : 'bbbbbbbbbbb',
            name,
            'Banda $name',
            200,
            false,
            null,
          ),
        ];
      },
      create: (title, description, ids) async {
        created?.add([title, ...ids]);
        return 'PLabcdefgh12345';
      },
    );

/// Abre la hoja como la app: desde un botón, sobre el navegador raíz.
Future<void> _open(
  WidgetTester tester,
  SpotifyImportController controller,
  List<(String, String)> opened,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              builder: (_) => SpotifyImportBody(
                controller: controller,
                onOpenPlaylist: (id, name) => opened.add((id, name)),
              ),
            ),
            child: const Text('abrir hoja'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir hoja'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pegar el enlace, leer, importar y abrir la playlist', (
    tester,
  ) async {
    final created = <List<String>>[];
    final opened = <(String, String)>[];
    final controller = _controller(created: created);
    addTearDown(controller.dispose);
    await _open(tester, controller, opened);

    expect(find.text('Importar de Spotify'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'https://open.spotify.com/playlist/4s99vnXwu8gsXZzIpLbGLh?si=abc',
    );
    await tester.tap(find.text('Leer playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lista'), findsOneWidget);
    expect(find.text('2 canciones'), findsOneWidget);

    await tester.tap(find.text('Importar a YouTube Music'));
    await tester.pumpAndSettle();
    expect(find.textContaining('creada: 2 de 2'), findsOneWidget);
    expect(created.single.first, 'Mi lista');

    // El botón que fallaba en el teléfono: cierra la hoja y abre la playlist.
    await tester.tap(find.text('Abrir playlist'));
    await tester.pumpAndSettle();
    expect(opened, [('PLabcdefgh12345', 'Mi lista')]);
    expect(find.text('Importar de Spotify'), findsNothing);
  });

  testWidgets('«Listo» cierra la hoja sin abrir nada', (tester) async {
    final opened = <(String, String)>[];
    final controller = _controller();
    addTearDown(controller.dispose);
    await _open(tester, controller, opened);
    await tester.enterText(
      find.byType(TextField),
      'spotify:playlist:0TnOYISbd1XYRBk9myaseg',
    );
    await tester.tap(find.text('Leer playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar a YouTube Music'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Importar de Spotify'), findsNothing);
  });

  testWidgets('un enlace que no es de Spotify avisa y deja corregirlo', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _open(tester, controller, []);
    await tester.enterText(find.byType(TextField), 'https://example.com/x');
    await tester.tap(find.text('Leer playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Ese no es un enlace de Spotify.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
