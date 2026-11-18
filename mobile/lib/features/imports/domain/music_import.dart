class ImportSong {
  const ImportSong({required this.sourceId, required this.status, this.title});
  final String sourceId;
  final String status;
  final String? title;

  factory ImportSong.fromJson(Map<String, dynamic> value) => ImportSong(
    sourceId: value['sourceId'] as String,
    status: value['status'] as String,
    title: (value['track'] as Map<String, dynamic>?)?['title'] as String?,
  );
}

class MusicImport {
  const MusicImport({
    required this.id,
    required this.name,
    required this.items,
    required this.confirmed,
    required this.savedCount,
    required this.skippedCount,
    this.playlistId,
  });
  final String id;
  final String name;
  final List<ImportSong> items;
  final bool confirmed;
  final String? playlistId;
  final int savedCount;
  final int skippedCount;

  int count(String status) =>
      items.where((item) => item.status == status).length;

  factory MusicImport.fromJson(Map<String, dynamic> value) => MusicImport(
    id: value['id'] as String,
    name: value['name'] as String,
    items: (value['items'] as List)
        .map((item) => ImportSong.fromJson(item as Map<String, dynamic>))
        .toList(),
    confirmed: value['confirmed'] as bool,
    playlistId: value['playlistId'] as String?,
    savedCount: value['savedCount'] as int,
    skippedCount: value['skippedCount'] as int,
  );
}
