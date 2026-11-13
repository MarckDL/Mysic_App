import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/favorites/application/favorite_providers.dart';
import 'package:mysic/features/favorites/domain/favorite.dart';
import 'package:mysic/features/favorites/domain/favorite_repository.dart';
import 'package:mysic/features/favorites/presentation/favorites_screen.dart';
import 'package:mysic/features/ratings/application/rating_providers.dart';
import 'package:mysic/features/ratings/domain/rating_repository.dart';
import 'package:mysic/features/ratings/domain/track_interactions.dart';
import 'package:mysic/features/ratings/presentation/track_preferences_panel.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';
import 'support/fake_auth_repository.dart';

const trackId = 'youtube:abcdefghijk';

class FakeFavorites implements FavoriteRepository {
  final items = <FavoriteItem>[
    FavoriteItem(
      createdAt: DateTime(2026, 11, 12),
      track: const CatalogTrack(
        id: trackId,
        title: 'Song',
        artistName: 'Artist',
      ),
    ),
  ];

  @override
  Future<List<FavoriteItem>> list({CancelToken? cancelToken}) async =>
      List.unmodifiable(items);
  @override
  Future<void> add(String trackId, {CancelToken? cancelToken}) async {
    if (items.isEmpty) {
      items.add(
        FavoriteItem(
          createdAt: DateTime(2026, 11, 12),
          track: CatalogTrack(id: trackId, title: 'Song', artistName: 'Artist'),
        ),
      );
    }
  }

  @override
  Future<void> remove(String trackId, {CancelToken? cancelToken}) async {
    items.removeWhere((item) => item.track.id == trackId);
  }
}

class FakeRatings implements RatingRepository {
  int? score;
  bool favorite = true;
  @override
  Future<TrackInteractions> interactions(
    String trackId, {
    CancelToken? cancelToken,
  }) async => TrackInteractions(
    isFavorite: favorite,
    myRating: score,
    ratingAverage: score?.toDouble(),
    ratingCount: score == null ? 0 : 1,
  );

  @override
  Future<TrackInteractions> rate(
    String trackId,
    int score, {
    required bool isFavorite,
    CancelToken? cancelToken,
  }) async {
    this.score = score;
    return TrackInteractions(
      isFavorite: isFavorite,
      myRating: score,
      ratingAverage: score.toDouble(),
      ratingCount: 1,
    );
  }
}

void main() {
  testWidgets('lista, abre y retira favoritos sin confirmación', (
    tester,
  ) async {
    final favorites = FakeFavorites();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const FavoritesScreen()),
        GoRoute(
          path: '/tracks/:id',
          builder: (_, _) => const Scaffold(body: Text('Detalle abierto')),
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
          favoriteRepositoryProvider.overrideWithValue(favorites),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Song'), findsOneWidget);
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle abierto'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quitar de favoritos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no tienes favoritos'), findsOneWidget);
  });

  testWidgets('muestra favorito, estrellas y actualiza rating', (tester) async {
    final favorites = FakeFavorites();
    final ratings = FakeRatings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: const AuthUser(uid: 'a')),
          ),
          favoriteRepositoryProvider.overrideWithValue(favorites),
          ratingRepositoryProvider.overrideWithValue(ratings),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TrackPreferencesPanel(trackId: trackId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Guardada en tus favoritos'), findsOneWidget);
    expect(find.text('Aún no hay calificaciones.'), findsOneWidget);
    await tester.tap(find.byTooltip('4 estrellas'));
    await tester.pumpAndSettle();
    expect(ratings.score, 4);
    expect(find.text('4.0 de 5 · 1 voto'), findsOneWidget);
  });
}
