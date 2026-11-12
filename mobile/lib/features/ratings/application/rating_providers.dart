import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../data/api_rating_repository.dart';
import '../domain/rating.dart';
import '../domain/rating_repository.dart';

final ratingRepositoryProvider = Provider.autoDispose<RatingRepository>((ref) {
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return ApiRatingRepository(api);
});

final ratingProvider = FutureProvider.autoDispose.family<RatingSummary, String>(
  (ref, trackId) async {
    if (ref.watch(authStateProvider).asData?.value == null) {
      throw const AuthFailure('Inicia sesión con Google.');
    }
    final cancel = CancelToken();
    ref.onDispose(cancel.cancel);
    return ref
        .watch(ratingRepositoryProvider)
        .get(trackId, cancelToken: cancel);
  },
  retry: (count, error) => null,
);

final ratingActionsProvider =
    NotifierProvider.autoDispose<RatingActions, AsyncValue<void>>(
      RatingActions.new,
    );

class RatingActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> set(String trackId, int? score) async {
    if (state.isLoading || (score != null && (score < 1 || score > 5))) {
      return false;
    }
    state = const AsyncLoading();
    try {
      final repository = ref.read(ratingRepositoryProvider);
      if (score == null) {
        await repository.remove(trackId);
      } else {
        await repository.set(trackId, score);
      }
      if (!ref.mounted) return false;
      state = const AsyncData(null);
      ref.invalidate(ratingProvider(trackId));
      return true;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    }
  }
}
