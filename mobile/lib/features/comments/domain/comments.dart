enum ReportReason {
  spam('Spam'),
  harassment('Acoso'),
  other('Otro motivo');

  const ReportReason(this.label);
  final String label;
}

enum ModerationAction { hide, dismiss }

class SongComment {
  const SongComment({
    required this.id,
    required this.authorName,
    required this.body,
    required this.isMine,
    this.reasons = const [],
  });

  final String id;
  final String authorName;
  final String body;
  final bool isMine;
  final List<ReportReason> reasons;

  factory SongComment.fromJson(Map<String, dynamic> json) => SongComment(
    id: json['id'] as String,
    authorName: json['authorName'] as String,
    body: json['body'] as String,
    isMine: json['isMine'] == true,
    reasons: [
      for (final reason in (json['reasons'] as List<dynamic>? ?? []))
        ReportReason.values.byName(reason as String),
    ],
  );
}

class CommentPage {
  const CommentPage(this.items, this.nextCursor);
  final List<SongComment> items;
  final String? nextCursor;

  factory CommentPage.fromJson(Map<String, dynamic> json) => CommentPage([
    for (final item in json['items'] as List<dynamic>)
      SongComment.fromJson(item as Map<String, dynamic>),
  ], json['nextCursor'] as String?);
}

abstract interface class CommentRepository {
  Future<CommentPage> list(String trackId, {String? cursor});
  Future<CommentPage> queue({String? cursor});
  Future<void> publish(String trackId, String body);
  Future<void> edit(String id, String body);
  Future<void> remove(String id);
  Future<void> report(String id, ReportReason reason);
  Future<void> resolve(String id, ModerationAction action);
}
