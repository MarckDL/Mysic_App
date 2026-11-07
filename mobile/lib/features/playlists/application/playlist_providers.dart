import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../data/api_playlist_repository.dart';
import '../domain/playlist.dart';
import '../domain/playlist_repository.dart';

final playlistRepositoryProvider = Provider.autoDispose<PlaylistRepository>((
  ref,
) {
  final api = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
  );
  ref.onDispose(api.close);
  return ApiPlaylistRepository(api);
});

final playlistsProvider = FutureProvider.autoDispose<List<PlaylistSummary>>((
  ref,
) async {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) throw const AuthFailure('Inicia sesión con Google.');
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  return ref.watch(playlistRepositoryProvider).list(cancelToken: cancel);
}, retry: (count, error) => null);

final playlistDetailProvider = FutureProvider.autoDispose
    .family<PlaylistDetail, String>((ref, id) async {
      final user = ref.watch(authStateProvider).asData?.value;
      if (user == null) throw const AuthFailure('Inicia sesión con Google.');
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return ref
          .watch(playlistRepositoryProvider)
          .detail(id, cancelToken: cancel);
    }, retry: (count, error) => null);

final playlistActionsProvider =
    NotifierProvider.autoDispose<PlaylistActions, AsyncValue<void>>(
      PlaylistActions.new,
    );

class PlaylistActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<T?> _run<T>(
    Future<T> Function(PlaylistRepository repository) action,
  ) async {
    if (state.isLoading) return null;
    state = const AsyncLoading();
    try {
      final result = await action(ref.read(playlistRepositoryProvider));
      if (ref.mounted) state = const AsyncData(null);
      return result;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return null;
    }
  }

  Future<PlaylistDetail?> create({
    required String name,
    String? description,
    required PlaylistVisibility visibility,
  }) async {
    final result = await _run(
      (repository) => repository.create(
        name: name,
        description: description,
        visibility: visibility,
      ),
    );
    if (result != null && ref.mounted) ref.invalidate(playlistsProvider);
    return result;
  }

  Future<bool> update(
    String id, {
    required String name,
    String? description,
    required PlaylistVisibility visibility,
  }) async {
    final result = await _run(
      (repository) => repository.update(
        id,
        name: name,
        description: description,
        clearDescription: description == null,
        visibility: visibility,
      ),
    );
    if (result == null || !ref.mounted) return false;
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistDetailProvider(id));
    return true;
  }

  Future<bool> delete(String id) async {
    final result = await _run(
      (repository) => repository.delete(id).then((_) => true),
    );
    if (result != true || !ref.mounted) return false;
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistDetailProvider(id));
    return true;
  }

  Future<bool> addTrack(String id, String trackId) async {
    final result = await _run((repository) => repository.addTrack(id, trackId));
    if (result == null || !ref.mounted) return false;
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistDetailProvider(id));
    return true;
  }

  Future<bool> removeTrack(String id, String itemId) async {
    final result = await _run(
      (repository) => repository.removeTrack(id, itemId),
    );
    if (result == null || !ref.mounted) return false;
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistDetailProvider(id));
    return true;
  }

  Future<bool> reorder(String id, List<String> itemIds) async {
    final result = await _run((repository) => repository.reorder(id, itemIds));
    if (result == null || !ref.mounted) return false;
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistDetailProvider(id));
    return true;
  }
}
