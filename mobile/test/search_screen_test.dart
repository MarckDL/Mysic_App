import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/search/application/catalog_providers.dart';
import 'package:mysic/features/search/domain/catalog_repository.dart';
import 'package:mysic/features/search/domain/catalog_track.dart';
import 'package:mysic/features/search/presentation/search_screen.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'support/fake_auth_repository.dart';
import 'package:mysic/app/mysic_app.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';

class SearchFake implements CatalogRepository {
  final calls = <String>[];
  final tokens = <CancelToken?>[];
  final detailCalls = <String>[];
  bool fail = false;
  @override
  Future<List<CatalogTrack>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    calls.add(query);
    tokens.add(cancelToken);
    if (fail) throw const ApiFailure('Catálogo no disponible');
    return query == 'none'
        ? []
        : [
            const CatalogTrack(
              id: 'youtube:abcdefghijk',
              title: 'Song',
              artistName: 'Artist',
            ),
          ];
  }

  @override
  Future<CatalogTrack> detail(String id, {CancelToken? cancelToken}) async {
    detailCalls.add(id);
    return CatalogTrack(id: id, title: 'Song', artistName: 'Artist');
  }
}

void main() {
  Future<void> mount(WidgetTester tester, SearchFake repository) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: const AuthUser(uid: 'a')),
          ),
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('espera 400 ms y cancela la búsqueda anterior al escribir', (
    tester,
  ) async {
    final repository = SearchFake();
    await mount(tester, repository);
    await tester.enterText(find.byType(TextField), 'artist');
    await tester.pump(const Duration(milliseconds: 399));
    expect(repository.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(repository.calls, ['artist']);
    expect(find.text('Song'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'other');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.calls, ['artist', 'other']);
    expect(repository.tokens.first!.isCancelled, isTrue);
  });
  testWidgets('distingue vacío y permite reintentar errores', (tester) async {
    final repository = SearchFake();
    await mount(tester, repository);
    await tester.enterText(find.byType(TextField), 'none');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('No encontramos'), findsOneWidget);
    repository.fail = true;
    await tester.enterText(find.byType(TextField), 'artist');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Catálogo no disponible'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Song'), findsOneWidget);
  });
  testWidgets('navega al detalle y elimina las rutas al cerrar sesión', (
    tester,
  ) async {
    final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
    final repository = SearchFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          verifiedSessionProvider.overrideWith(
            (ref) async => const MysicProfile(
              id: '00000000-0000-4000-8000-000000000001',
              firebaseUid: 'a',
              displayName: 'Ana',
            ),
          ),
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MysicApp(firebaseReady: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar música'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'artist');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle de canción'), findsOneWidget);
    expect(repository.detailCalls, ['youtube:abcdefghijk']);
    expect(find.text('Artist'), findsOneWidget);
    expect(
      find.text('Reproducción aún no disponible en Mysic.'),
      findsOneWidget,
    );
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Detalle de canción'), findsNothing);
    expect(find.text('Song'), findsNothing);
  });
}
