import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/search/presentation/music_tiles.dart';

void main() {
  test('las escuchas se escriben en singular y plural', () {
    expect(playsLabel(1), '1 escucha');
    expect(playsLabel(34), '34 escuchas');
  });

  testWidgets('la primera canción va destacada y el resto con su puesto', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TopSongCard(
                title: 'Death flags',
                artist: 'mai',
                plays: 60,
                onTap: () => taps++,
              ),
              RankedSongRow(
                rank: 2,
                title: 'Hatachi No Koi',
                artist: 'Lamp',
                plays: 34,
                onTap: () => taps++,
              ),
              RankedSongRow(
                rank: 10,
                title: 'Otra',
                artist: 'Alguien',
                onTap: null,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('60 escuchas'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('34 escuchas'), findsOneWidget);
    // Sin escuchas conocidas no se inventa el número.
    expect(find.text('10'), findsOneWidget);
    expect(find.textContaining('escucha'), findsNWidgets(2));

    await tester.tap(find.text('Death flags'));
    await tester.tap(find.text('Hatachi No Koi'));
    expect(taps, 2);
  });
}
