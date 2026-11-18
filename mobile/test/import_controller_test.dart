import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mysic/features/imports/application/import_providers.dart';
import 'package:mysic/features/imports/presentation/import_screen.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/imports/application/import_controller.dart';
import 'package:mysic/features/imports/data/import_client.dart';
import 'package:mysic/features/imports/data/takeout_file_picker.dart';
import 'package:mysic/features/imports/domain/music_import.dart';
import 'package:mysic/features/imports/domain/takeout_playlist.dart';

import 'support/fake_auth_repository.dart';

class Picker extends TakeoutFilePicker {
  @override
  Future<List<TakeoutPlaylist>?> pick() async => [
    const TakeoutPlaylist(
      name: 'Lista',
      sourceIds: ['abcdefghijk', 'bcdefghijkl'],
    ),
  ];
}

class Client extends ImportClient {
  Client()
    : super(
        AuthenticatedApiClient(
          FakeAuthRepository(),
          baseUrl: 'https://example.com',
        ),
      );
  bool failPrepare = false;
  bool failConfirm = false;
  int saved = 0;
  List<int> batches = [];
  MusicImport? draft;
  Completer<void>? wait;
  String? preparedId;

  MusicImport value(
    String id,
    List<ImportSong> items, {
    bool confirmed = false,
  }) => MusicImport(
    id: id,
    name: 'Lista',
    items: items,
    confirmed: confirmed,
    savedCount: confirmed ? 2 : 0,
    skippedCount: 0,
    playlistId: confirmed ? 'playlist-id' : null,
  );

  @override
  Future<List<MusicImport>> list(CancelToken cancel) async =>
      draft == null ? [] : [draft!];

  @override
  Future<MusicImport> prepare(
    String id,
    TakeoutPlaylist list,
    CancelToken cancel,
  ) async {
    preparedId ??= id;
    expect(id, preparedId);
    draft ??= value(
      id,
      list.sourceIds
          .map((sourceId) => ImportSong(sourceId: sourceId, status: 'pending'))
          .toList(),
    );
    if (failPrepare) {
      failPrepare = false;
      throw const ApiFailure('Respuesta perdida');
    }
    return draft!;
  }

  @override
  Future<MusicImport> resolve(
    String id,
    List<int> indices,
    CancelToken cancel,
  ) async {
    await wait?.future;
    batches.addAll(indices);
    draft = value(id, [
      for (var index = 0; index < draft!.items.length; index++)
        ImportSong(
          sourceId: draft!.items[index].sourceId,
          status: indices.contains(index)
              ? 'ready'
              : draft!.items[index].status,
          title: 'Canción',
        ),
    ]);
    return draft!;
  }

  @override
  Future<void> discard(String id, CancelToken cancel) async {
    draft = null;
  }

  @override
  Future<MusicImport> confirm(String id, CancelToken cancel) async {
    if (draft!.confirmed) return draft!;
    saved++;
    draft = value(id, [], confirmed: true);
    if (failConfirm) {
      failConfirm = false;
      throw const ApiFailure('Respuesta perdida');
    }
    return draft!;
  }
}

void main() {
  test(
    'recupera respuestas perdidas de preparación y confirmación sin duplicar',
    () async {
      final client = Client()..failPrepare = true;
      var invalidations = 0;
      final controller = ImportController(
        client,
        Picker(),
        onSaved: () => invalidations++,
      );
      await controller.pick();
      await controller.review();
      expect(controller.error, isNotNull);
      final id = controller.entries.single.id;
      await controller.review();
      expect(controller.entries.single.id, id);
      expect(controller.canConfirm, isTrue);
      client.failConfirm = true;
      await controller.confirm();
      expect(controller.error, isNotNull);
      await controller.confirm();
      expect(client.saved, 1);
      expect(invalidations, 1);
      expect(controller.entries.single.draft!.confirmed, isTrue);
      controller.dispose();
      client.close();
    },
  );

  test('reanuda borradores y limita cada lote a dos pistas', () async {
    final client = Client();
    await client.prepare(
      'pending',
      const TakeoutPlaylist(
        name: 'Lista',
        sourceIds: ['abcdefghijk', 'bcdefghijkl'],
      ),
      CancelToken(),
    );
    final controller = ImportController(client, Picker(), onSaved: () {});
    await controller.load();
    expect(controller.entries.single.source, isNull);
    await controller.review();
    expect(client.batches, [0, 1]);
    expect(controller.canConfirm, isTrue);
    controller.dispose();
    client.close();
  });

  test(
    'descarta callbacks pendientes al cerrar pantalla o cambiar de cuenta',
    () async {
      final client = Client()..wait = Completer<void>();
      var saved = false;
      final controller = ImportController(
        client,
        Picker(),
        onSaved: () => saved = true,
      );
      await controller.pick();
      final review = controller.review();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      client.wait!.complete();
      await review;
      expect(saved, isFalse);
      client.close();
    },
  );
  test(
    'descarta un borrador para liberar espacio sin crear playlists',
    () async {
      final client = Client();
      final controller = ImportController(client, Picker(), onSaved: () {});
      await controller.pick();
      await controller.review();
      await controller.discard(controller.entries.single);
      expect(controller.entries, isEmpty);
      expect(client.draft, isNull);
      expect(client.saved, 0);
      controller.dispose();
      client.close();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'importa desde la pantalla con texto ampliado en ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = Client();
        final controller = ImportController(client, Picker(), onSaved: () {});
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const ImportScreen()),
            GoRoute(
              path: '/playlists/:id',
              builder: (_, _) =>
                  const Scaffold(body: Text('Playlist importada')),
            ),
          ],
        );
        addTearDown(router.dispose);
        addTearDown(controller.dispose);
        addTearDown(client.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              importControllerProvider.overrideWith((ref) => controller),
            ],
            child: MaterialApp.router(
              theme: ThemeData(brightness: brightness),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
            ),
          ),
        );
        Future<void> tap(String text, {double delta = 160}) async {
          await tester.scrollUntilVisible(find.text(text), delta);
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(find.text(text)),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        await tap('Elegir ZIP o CSV');
        await tap('Revisar canciones seleccionadas');
        expect(controller.canConfirm, isTrue);
        await tap('Guardar copia privada');
        expect(client.saved, 1);
        await tap('Lista', delta: -160);
        expect(find.text('Playlist importada'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
