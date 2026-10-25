import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../data/api_catalog_repository.dart';
import '../domain/catalog_repository.dart';
import '../domain/catalog_track.dart';

final catalogRepositoryProvider = Provider.autoDispose<CatalogRepository>((
  ref,
) {
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return ApiCatalogRepository(api);
});

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<CatalogTrack>, String>((ref, query) async {
      final user = ref.watch(authStateProvider).asData?.value;
      if (user == null) throw const AuthFailure('Inicia sesión con Google.');
      final cancel = CancelToken();
      ref.onDispose(() => cancel.cancel());
      return ref
          .watch(catalogRepositoryProvider)
          .search(query, cancelToken: cancel);
    }, retry: (count, error) => null);

final trackDetailProvider = FutureProvider.autoDispose
    .family<CatalogTrack, String>((ref, id) async {
      final user = ref.watch(authStateProvider).asData?.value;
      if (user == null) throw const AuthFailure('Inicia sesión con Google.');
      final cancel = CancelToken();
      ref.onDispose(() => cancel.cancel());
      return ref
          .watch(catalogRepositoryProvider)
          .detail(id, cancelToken: cancel);
    }, retry: (count, error) => null);
