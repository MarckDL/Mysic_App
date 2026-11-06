import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/playlists/application/playlist_providers.dart';
import 'package:mysic/features/playlists/domain/playlist.dart';
import 'package:mysic/features/playlists/domain/playlist_repository.dart';
import 'package:mysic/features/playlists/presentation/playlist_detail_screen.dart';
import 'package:mysic/features/playlists/presentation/playlists_screen.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';
import 'support/fake_auth_repository.dart';

const firstId = '11111111-1111-4111-8111-111111111111';
const secondId = '22222222-2222-4222-8222-222222222222';
const itemId = '33333333-3333-4333-8333-333333333333';

class FakePlaylists implements PlaylistRepository {
  final summaries = <PlaylistSummary>[];
  final details = <String, PlaylistDetail>{};
  final removed = <String>[];

  FakePlaylists() {
    final detail = makeDetail(firstId, 'Viaje', withTrack: true);
    summaries.add(detail);
    details[firstId] = detail;
  }

  static PlaylistDetail makeDetail(
    String id,
    String name, {
    bool withTrack = false,
  }) => PlaylistDetail(
    id: id,
    name: name,
    visibility: PlaylistVisibility.private,
    trackCount: withTrack ? 1 : 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    ownedByCurrentUser: true,
    tracks: withTrack
        ? [
            PlaylistItem(
              id: itemId,
              position: 0,
              addedAt: DateTime(2026),
              track: const CatalogTrack(
                id: 'youtube:abcdefghijk',
                title: 'Song',
                artistName: 'Artist',
              ),
            ),
          ]
        : const [],
  );

  @override
  Future<List<PlaylistSummary>> list({CancelToken? cancelToken}) async =>
      List.unmodifiable(summaries);
  @override
  Future<PlaylistDetail> detail(String id, {CancelToken? cancelToken}) async =>
      details[id]!;
  @override
  Future<PlaylistDetail> create({
    required String name,
    String? description,
    PlaylistVisibility visibility = PlaylistVisibility.private,
  }) async {
    final value = makeDetail(secondId, name);
    summaries.insert(0, value);
    details[value.id] = value;
    return value;
  }

  @override
  Future<PlaylistDetail> removeTrack(String id, String occurrenceId) async {
    removed.add(occurrenceId);
    final old = details[id]!;
    final value = makeDetail(old.id, old.name);
    details[id] = value;
    summaries[summaries.indexWhere((item) => item.id == id)] = value;
    return value;
  }

  @override
  Future<PlaylistDetail> addTrack(String id, String catalogTrackId) async =>
      details[id]!;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<PlaylistDetail> reorder(String id, List<String> itemIds) async =>
      details[id]!;
  @override
  Future<PlaylistDetail> update(
    String id, {
    String? name,
    String? description,
    bool clearDescription = false,
    PlaylistVisibility? visibility,
  }) async => details[id]!;
}

void main() {
  testWidgets('lista, abre, retira y crea playlists', (tester) async {
    final repository = FakePlaylists();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const PlaylistsScreen()),
        GoRoute(
          path: '/playlists/:id',
          builder: (_, state) =>
              PlaylistDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: const AuthUser(uid: 'a')),
          ),
          playlistRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Viaje'), findsOneWidget);
    await tester.tap(find.text('Viaje'));
    await tester.pumpAndSettle();
    expect(find.text('Song'), findsOneWidget);
    await tester.tap(find.byTooltip('Quitar de la playlist'));
    await tester.pumpAndSettle();
    expect(repository.removed, [itemId]);
    expect(find.textContaining('playlist está vacía'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Entrenamiento');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Entrenamiento'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });
}
