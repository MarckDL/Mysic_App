import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../data/api_comment_repository.dart';
import '../domain/comments.dart';

final commentRepositoryProvider = Provider.autoDispose<CommentRepository>((
  ref,
) {
  final client = AuthenticatedApiClient(
    ref.watch(authRepositoryProvider),
    baseUrl: ApiConfig.baseUrl,
    keepSessionOnForbidden: true,
  );
  ref.onDispose(client.close);
  return ApiCommentRepository(client);
});

final commentFeedProvider = AsyncNotifierProvider.autoDispose
    .family<CommentFeed, CommentPage, String?>(
      CommentFeed.new,
      retry: (count, error) => null,
    );

class CommentFeed extends AsyncNotifier<CommentPage> {
  CommentFeed(this._trackId);

  // null representa la cola de moderación.
  final String? _trackId;
  late CommentRepository _repository;

  @override
  Future<CommentPage> build() {
    final user = ref.watch(authStateProvider).asData?.value;
    if (user == null) throw const AuthFailure('Inicia sesión con Google.');
    _repository = ref.watch(commentRepositoryProvider);
    return _page();
  }

  Future<CommentPage> _page({String? cursor}) {
    final trackId = _trackId;
    return trackId == null
        ? _repository.queue(cursor: cursor)
        : _repository.list(trackId, cursor: cursor);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null) return;
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    final next = await _page(cursor: cursor);
    if (!ref.mounted || ref.read(authStateProvider).asData?.value?.uid != uid) {
      return;
    }
    final known = current.items.map((item) => item.id).toSet();
    state = AsyncData(
      CommentPage([
        ...current.items,
        ...next.items.where((item) => known.add(item.id)),
      ], next.nextCursor),
    );
  }

  Future<void> publish(String body) => _repository.publish(_trackId!, body);
  Future<void> edit(String id, String body) => _repository.edit(id, body);
  Future<void> remove(String id) => _repository.remove(id);
  Future<void> report(String id, ReportReason reason) =>
      _repository.report(id, reason);
  Future<void> resolve(String id, ModerationAction action) =>
      _repository.resolve(id, action);
}
