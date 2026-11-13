import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../data/youtube_library_repository.dart';
import '../domain/youtube_library.dart';
import '../../playlists/application/playlist_providers.dart';

final youtubeLibraryRepositoryProvider =
    Provider.autoDispose<YoutubeLibraryRepository>((ref) {
      final api = AuthenticatedApiClient(
        ref.watch(authRepositoryProvider),
        baseUrl: ApiConfig.baseUrl,
      );
      ref.onDispose(api.close);
      return YoutubeLibraryRepository(api);
    });

final youtubeConnectionStatusProvider =
    FutureProvider.autoDispose<YoutubeConnectionStatus>(
      (ref) => ref.watch(youtubeLibraryRepositoryProvider).status(),
    );

final youtubeLibraryProvider = FutureProvider.autoDispose<YoutubeLibrary>(
  (ref) => ref.watch(youtubeLibraryRepositoryProvider).library(),
);

final youtubeLibraryActionsProvider =
    NotifierProvider.autoDispose<YoutubeLibraryActions, AsyncValue<void>>(
      YoutubeLibraryActions.new,
    );

class YoutubeLibraryActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> connectAndSync() async => _run(() async {
    final token = await ref
        .read(authRepositoryProvider)
        .authorizeYouTubeReadOnly();
    await ref.read(youtubeLibraryRepositoryProvider).sync(token);
  });

  Future<bool> disconnect() =>
      _run(ref.read(youtubeLibraryRepositoryProvider).disconnect);

  Future<bool> duplicate(String remotePlaylistId) => _run(() async {
    await ref
        .read(youtubeLibraryRepositoryProvider)
        .duplicate(remotePlaylistId);
    ref.invalidate(playlistsProvider);
  });

  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      await action();
      if (!ref.mounted) return false;
      state = const AsyncData(null);
      ref.invalidate(youtubeConnectionStatusProvider);
      ref.invalidate(youtubeLibraryProvider);
      return true;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    }
  }
}
