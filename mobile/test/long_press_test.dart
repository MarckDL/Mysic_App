import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'mantener pulsado abre la opción en filas, tarjetas, collage y accesos',
    (tester) async {
      // Una pantalla alta: los seis componentes caben a la vez.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final held = <String>[];
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              SongRow(
                title: 'Fila',
                subtitle: 'a',
                onTap: () => taps++,
                onLongPress: () => held.add('fila'),
              ),
              TopSongCard(
                title: 'Top',
                artist: 'a',
                onTap: () => taps++,
                onLongPress: () => held.add('top'),
              ),
              RankedSongRow(
                rank: 2,
                title: 'Ranking',
                artist: 'a',
                onTap: () => taps++,
                onLongPress: () => held.add('ranking'),
              ),
              AlbumDiscCard(
                title: 'Disco',
                onTap: () => taps++,
                onLongPress: () => held.add('álbum'),
              ),
              SpeedDialGrid(
                items: [
                  (
                    title: 'Casilla',
                    subtitle: 's',
                    url: null,
                    onTap: () => taps++,
                    onLongPress: () => held.add('collage'),
                  ),
                ],
              ),
              OnePeShortcuts(
                items: [
                  (
                    title: 'Acceso',
                    subtitle: 's',
                    url: null,
                    icon: Icons.queue_music,
                    onTap: () => taps++,
                    onLongPress: () => held.add('de one pe'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      for (final label in [
        'Fila',
        'Top',
        'Ranking',
        'Disco',
        'Casilla',
        'Acceso',
      ]) {
        await tester.longPress(find.text(label));
        await tester.pump();
      }
      expect(held, ['fila', 'top', 'ranking', 'álbum', 'collage', 'de one pe']);
      // Mantener pulsado no cuenta como toque.
      expect(taps, 0);
      // Un toque normal sigue funcionando y no abre la hoja.
      await tester.tap(find.text('Fila'));
      await tester.pump();
      expect(taps, 1);
      expect(held, hasLength(6));
    },
  );

  testWidgets('las filas ya no llevan botón de tres puntos', (tester) async {
    await tester.pumpWidget(
      _app(
        SongRow(title: 'Fila', subtitle: 'a', onTap: () {}, onLongPress: () {}),
      ),
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
