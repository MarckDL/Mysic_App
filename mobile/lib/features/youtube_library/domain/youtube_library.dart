import '../../search/domain/catalog_track.dart';

class YoutubeConnectionStatus {
  const YoutubeConnectionStatus({
    required this.connected,
    required this.displayName,
    required this.avatarUrl,
    required this.lastSyncedAt,
    required this.playlistCount,
    required this.likedTrackCount,
    required this.subscriptionCount,
  });

  factory YoutubeConnectionStatus.fromJson(Map<String, dynamic> json) =>
      YoutubeConnectionStatus(
        connected: json['connected'] == true,
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        lastSyncedAt: json['lastSyncedAt'] is String
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
        playlistCount: json['playlistCount'] as int? ?? 0,
        likedTrackCount: json['likedTrackCount'] as int? ?? 0,
        subscriptionCount: json['subscriptionCount'] as int? ?? 0,
      );

  final bool connected;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? lastSyncedAt;
  final int playlistCount;
  final int likedTrackCount;
  final int subscriptionCount;
}

class YoutubeRemotePlaylist {
  const YoutubeRemotePlaylist({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.itemCount,
  });
  factory YoutubeRemotePlaylist.fromJson(Map<String, dynamic> json) =>
      YoutubeRemotePlaylist(
        id: json['id'] as String,
        title: json['title'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        itemCount: json['itemCount'] as int? ?? 0,
      );
  final String id;
  final String title;
  final String? thumbnailUrl;
  final int itemCount;
}

class YoutubeLibrary {
  const YoutubeLibrary({required this.likes, required this.playlists});
  factory YoutubeLibrary.fromJson(Map<String, dynamic> json) => YoutubeLibrary(
    likes: (json['likes'] as List? ?? const [])
        .map((value) => CatalogTrack.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    playlists: (json['playlists'] as List? ?? const [])
        .map(
          (value) =>
              YoutubeRemotePlaylist.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
  );
  final List<CatalogTrack> likes;
  final List<YoutubeRemotePlaylist> playlists;
}
