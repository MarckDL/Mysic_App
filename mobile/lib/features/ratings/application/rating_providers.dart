import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../data/api_rating_repository.dart';
import '../domain/rating_repository.dart';
import '../domain/track_interactions.dart';

final ratingRepositoryProvider = Provider.autoDispose<RatingRepository>((ref) {
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return ApiRatingRepository(api);
});

final trackInteractionsProvider = FutureProvider.autoDispose
    .family<TrackInteractions, String>((ref, trackId) async {
      final user = ref.watch(authStateProvider).asData?.value;
      if (user == null) throw const AuthFailure('Inicia sesión con Google.');
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return ref
          .watch(ratingRepositoryProvider)
          .interactions(trackId, cancelToken: cancel);
    }, retry: (count, error) => null);

final ratingActionsProvider =
    NotifierProvider.autoDispose<RatingActions, AsyncValue<void>>(
      RatingActions.new,
    );

class RatingActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> rate(String trackId, int score, bool isFavorite) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(ratingRepositoryProvider)
          .rate(trackId, score, isFavorite: isFavorite);
      if (!ref.mounted) return false;
      ref.invalidate(trackInteractionsProvider(trackId));
      state = const AsyncData(null);
      return updated.myRating == score;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    }
  }
}
