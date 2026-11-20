import '../../search/domain/catalog_track.dart';
import '../../playback/domain/track_audio_engine.dart';

enum MusicSurface {
  home,
  songs,
  liked,
  channelLiked,
  albums,
  album,
  playlists,
  playlist,
  search,
  history,
  mysicRecents,
  onRepeat,
  artist,
  artists,
}

enum MusicLinkStatus { unavailable, unlinked, linked, expired }

class MusicAccount {
  const MusicAccount(this.id, this.name, this.historyPaused);

  factory MusicAccount.fromJson(Map<String, dynamic> data) => MusicAccount(
    data['id'] as String,
    data['name'] as String,
    data['historyPaused'] == true,
  );

  final String id;
  final String name;
  final bool historyPaused;
}

class MusicConnection {
  const MusicConnection({
    required this.status,
    this.provider,
    this.libraryId,
    this.personalization,
    this.activityEpoch = 0,
    this.accounts = const [],
    this.account,
    this.generation,
    this.capabilities = const {},
  });

  factory MusicConnection.fromJson(Map<String, dynamic> data) =>
      MusicConnection(
        status: MusicLinkStatus.values.byName(data['status'] as String),
        provider: data['provider'] as String?,
        libraryId: data['libraryId'] as String?,
        personalization: data['personalization'] as String?,
        activityEpoch: data['activityEpoch'] as int? ?? 0,
        accounts: (data['accounts'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(MusicAccount.fromJson)
            .toList(),
        account: data['account'] is Map<String, dynamic>
            ? MusicAccount.fromJson(data['account'] as Map<String, dynamic>)
            : null,
        generation: data['generation'] as String?,
        capabilities: (data['capabilities'] as List<dynamic>)
            .cast<String>()
            .toSet(),
      );

  final MusicLinkStatus status;
  final String? provider;
  final String? personalization;
  bool get channelOnly =>
      personalization == 'channelOnly' || personalization == 'unverified';
  String get accessDescription => switch (personalization) {
    'partialMusic' => 'Acceso parcial a tu biblioteca de YouTube Music.',
    'channelOnly' => 'Acceso al canal de YouTube.',
    'unverified' => 'Biblioteca musical pendiente de verificar.',
    'verified' => 'Canal y biblioteca musical verificados.',
    _ => 'Canal vinculado',
  };
  final String? libraryId;
  final int activityEpoch;
  final List<MusicAccount> accounts;
  final MusicAccount? account;
  final String? generation;
  final Set<String> capabilities;
  bool get usesChannelLikes =>
      !capabilities.contains('liked') && capabilities.contains('channelLiked');
  String get likesActionLabel => usesChannelLikes
      ? 'Ver los Me gusta de mi canal'
      : 'Ver mis Me gusta de YouTube Music';
  bool get serverPending => provider == 'serverPending';
  bool get isPreview => provider == 'preview';
  bool get isDirect => provider == 'youtubeOAuth';
  bool get isDesktop => provider == 'mysicDesktop';
  bool get nativeCatalog => isDirect || isDesktop;
}

sealed class MusicItem {
  const MusicItem(this.id, this.title, {this.shelfTitle});

  factory MusicItem.fromJson(Map<String, dynamic> data) =>
      switch (data['kind']) {
        'track' => MusicTrack.fromJson(data),
        'playlist' => MusicPlaylist.fromJson(data),
        'album' => MusicAlbum(
          data['id'] as String,
          data['title'] as String,
          thumbnailUrl: data['thumbnailUrl'] as String?,
          shelfTitle: data['shelfTitle'] as String?,
        ),
        'artist' => MusicArtist(
          data['id'] as String,
          data['title'] as String,
          thumbnailUrl: data['thumbnailUrl'] as String?,
          shelfTitle: data['shelfTitle'] as String?,
        ),
        _ => throw const FormatException('Elemento musical desconocido.'),
      };

  final String id;
  final String title;
  final String? shelfTitle;
}

class MusicTrack extends MusicItem {
  const MusicTrack(
    super.id,
    super.title,
    this.artist,
    this.durationSeconds,
    this.canPreview,
    this.listenedAt, {
    super.shelfTitle,
    this.audioUri,
    this.nativePlayback = false,
    this.artistId,
    this.playCount,
    this.thumbnailUrl,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> data) => MusicTrack(
    data['id'] as String,
    data['title'] as String,
    data['artist'] as String,
    data['durationSeconds'] as int,
    data['playback'] == 'bundledPreview',
    DateTime.tryParse(data['listenedAt'] as String? ?? ''),
    nativePlayback:
        data['playback'] == 'native' &&
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(data['id'] as String),
    artistId:
        data['artistId'] is String &&
            RegExp(
              r'^UC[A-Za-z0-9_-]{22}$',
            ).hasMatch(data['artistId'] as String)
        ? data['artistId'] as String
        : null,
    playCount: data['playCount'] as int?,
    audioUri:
        data['playback'] == 'licensed' &&
            RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(data['id'] as String)
        ? _licensedUri(data['audioUrl'])
        : null,
    thumbnailUrl: data['thumbnailUrl'] as String?,
    shelfTitle: data['shelfTitle'] as String?,
  );

  final String artist;
  final int durationSeconds;
  final bool canPreview;
  final bool nativePlayback;
  final DateTime? listenedAt;
  final Uri? audioUri;
  final String? artistId;
  final int? playCount;
  bool get canPlayInMysic => nativePlayback || audioUri != null;
  static Uri? _licensedUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment
        ? uri
        : null;
  }

  final String? thumbnailUrl;

  CatalogTrack toPlaybackTrack({
    Uri? deviceAudio,
    TrackAudioReader? readAudio,
  }) => CatalogTrack(
    id: canPreview ? '${CatalogTrack.musicPreviewPrefix}$id' : 'youtube:$id',
    title: title,
    artistName: artist,
    durationSeconds: durationSeconds > 0 ? durationSeconds : null,
    thumbnailUrl: thumbnailUrl,
    licensedAudio: audioUri,
    musicAccountTrack: nativePlayback,
    deviceAudio: deviceAudio,
    readAudio: readAudio,
  );
}

class MusicPlaylist extends MusicItem {
  const MusicPlaylist(
    super.id,
    super.title,
    this.isPrivate, {
    super.shelfTitle,
    this.thumbnailUrl,
  });
  final String? thumbnailUrl;

  factory MusicPlaylist.fromJson(Map<String, dynamic> data) => MusicPlaylist(
    data['id'] as String,
    data['title'] as String,
    data['private'] == true,
    thumbnailUrl: data['thumbnailUrl'] as String?,
    shelfTitle: data['shelfTitle'] as String?,
  );

  final bool isPrivate;
}

class MusicAlbum extends MusicItem {
  const MusicAlbum(
    super.id,
    super.title, {
    this.thumbnailUrl,
    super.shelfTitle,
  });
  final String? thumbnailUrl;
}

class MusicArtist extends MusicItem {
  const MusicArtist(
    super.id,
    super.title, {
    this.thumbnailUrl,
    super.shelfTitle,
  });
  final String? thumbnailUrl;
}

class MusicPage {
  const MusicPage(
    this.items,
    this.nextCursor,
    this.playlist,
    this.excludedCount, [
    this.title,
  ]);

  factory MusicPage.fromJson(Map<String, dynamic> data) => MusicPage(
    (data['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(MusicItem.fromJson)
        .toList(),
    data['nextCursor'] as String?,
    data['playlist'] is Map<String, dynamic>
        ? MusicPlaylist.fromJson(data['playlist'] as Map<String, dynamic>)
        : null,
    data['excludedCount'] as int? ?? 0,
    data['title'] as String?,
  );

  final List<MusicItem> items;
  final String? nextCursor;
  final MusicPlaylist? playlist;
  final int excludedCount;
  final String? title;
}
