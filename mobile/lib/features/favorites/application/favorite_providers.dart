import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../ratings/application/rating_providers.dart';
import '../data/api_favorite_repository.dart';
import '../domain/favorite.dart';
import '../domain/favorite_repository.dart';

final favoriteRepositoryProvider = Provider.autoDispose<FavoriteRepository>((
  ref,
) {
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return ApiFavoriteRepository(api);
});

final favoritesProvider = FutureProvider.autoDispose<List<FavoriteItem>>((
  ref,
) async {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) throw const AuthFailure('Inicia sesión con Google.');
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  return ref.watch(favoriteRepositoryProvider).list(cancelToken: cancel);
}, retry: (count, error) => null);

final favoriteActionsProvider =
    NotifierProvider.autoDispose<FavoriteActions, AsyncValue<void>>(
      FavoriteActions.new,
    );

class FavoriteActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> setFavorite(String trackId, bool favorite) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      final repository = ref.read(favoriteRepositoryProvider);
      if (favorite) {
        await repository.add(trackId);
      } else {
        await repository.remove(trackId);
      }
      if (!ref.mounted) return false;
      ref.invalidate(favoritesProvider);
      ref.invalidate(trackInteractionsProvider(trackId));
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    }
  }
}
