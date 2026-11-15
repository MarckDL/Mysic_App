import '../../../core/network/authenticated_api_client.dart';
import '../domain/comments.dart';

class ApiCommentRepository implements CommentRepository {
  ApiCommentRepository(this._client);

  final AuthenticatedApiClient _client;

  static const _moderation = '/api/v1/moderation/comments';
  String _track(String id) =>
      '/api/v1/tracks/${Uri.encodeComponent(id)}/comments';
  String _comment(String id) => '/api/v1/comments/${Uri.encodeComponent(id)}';

  Future<CommentPage> _page(String path, String? cursor) async =>
      CommentPage.fromJson(
        await _client.get(path, query: {if (cursor != null) 'cursor': cursor}),
      );

  @override
  Future<CommentPage> list(String trackId, {String? cursor}) =>
      _page(_track(trackId), cursor);

  @override
  Future<CommentPage> queue({String? cursor}) => _page(_moderation, cursor);

  @override
  Future<void> publish(String trackId, String body) async {
    await _client.post(_track(trackId), body: {'body': body});
  }

  @override
  Future<void> edit(String id, String body) async {
    await _client.patch(_comment(id), body: {'body': body});
  }

  @override
  Future<void> remove(String id) async {
    await _client.delete(_comment(id));
  }

  @override
  Future<void> report(String id, ReportReason reason) async {
    await _client.post(
      '${_comment(id)}/reports',
      body: {'reason': reason.name},
    );
  }

  @override
  Future<void> resolve(String id, ModerationAction action) async {
    await _client.patch(
      '$_moderation/${Uri.encodeComponent(id)}',
      body: {'action': action.name},
    );
  }
}
