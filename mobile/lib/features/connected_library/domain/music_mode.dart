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

/// Enlaces de una canción a su artista y a su álbum, con el nombre del
/// álbum cuando el catálogo lo da.
typedef TrackLinks = ({String? artistId, String? albumId, String? album});

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
  bool get nativeCatalog => isDirect;

  /// La misma conexión con otras capacidades.
  MusicConnection copyWith({Set<String>? capabilities}) => MusicConnection(
    status: status,
    provider: provider,
    libraryId: libraryId,
    personalization: personalization,
    activityEpoch: activityEpoch,
    accounts: accounts,
    account: account,
    generation: generation,
    capabilities: capabilities ?? this.capabilities,
  );
}

sealed class MusicItem {
  const MusicItem(this.id, this.title, {this.shelfTitle});

  factory MusicItem.fromJson(
    Map<String, dynamic> data,
  ) => switch (data['kind']) {
    'track' => MusicTrack.fromJson(data),
    'playlist' => MusicPlaylist.fromJson(data),
    'album' => MusicAlbum(
      data['id'] as String,
      data['title'] as String,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      detail: data['subtitle'] is String ? data['subtitle'] as String : null,
      shelfTitle: data['shelfTitle'] as String?,
    ),
    'artist' => MusicArtist(
      data['id'] as String,
      data['title'] as String,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      detail: data['subtitle'] is String ? data['subtitle'] as String : null,
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
    this.albumId,
    this.albumName,
    this.playCount,
    this.thumbnailUrl,
    this.entryId,
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
    albumId: _albumId(data['albumId']),
    // El nombre solo acompaña a un álbum que se puede abrir.
    albumName:
        _albumId(data['albumId']) != null &&
            data['albumName'] is String &&
            (data['albumName'] as String).trim().isNotEmpty
        ? (data['albumName'] as String).trim()
        : null,
    playCount: data['playCount'] as int?,
    audioUri:
        data['playback'] == 'licensed' &&
            RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(data['id'] as String)
        ? _licensedUri(data['audioUrl'])
        : null,
    thumbnailUrl: data['thumbnailUrl'] as String?,
    shelfTitle: data['shelfTitle'] as String?,
    entryId: data['entryId'] is String ? data['entryId'] as String : null,
  );

  /// La entrada de esta canción en la playlist de la que salió; hace falta
  /// para quitarla de ella.
  final String? entryId;

  final String artist;
  final int durationSeconds;
  final bool canPreview;
  final bool nativePlayback;
  final DateTime? listenedAt;
  final Uri? audioUri;
  final String? artistId;

  /// Álbum al que pertenece (id de exploración `MPREb_…`), si se conoce.
  final String? albumId;

  /// Nombre de ese álbum, cuando el servidor lo envía con la canción.
  final String? albumName;

  static String? _albumId(Object? value) =>
      value is String && RegExp(r'^MPREb_[A-Za-z0-9_-]{6,60}$').hasMatch(value)
      ? value
      : null;
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
    artistId: artistId,
    albumId: albumId,
    albumName: albumName,
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
    this.detail,
    this.artist,
    super.shelfTitle,
  });
  final String? thumbnailUrl;

  /// Artista del álbum; solo lo traen los resultados de búsqueda.
  final String? artist;

  /// Tipo y año tal como los da el catálogo, p. ej. "Álbum · 2024".
  final String? detail;
}

/// Página pública de un artista: cabecera, canciones destacadas y discografía.
class ArtistProfile {
  const ArtistProfile({
    required this.id,
    required this.name,
    required this.topSongs,
    required this.shelves,
    this.videos = const [],
    this.playlistShelves = const [],
    this.audience,
    this.description,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final String? audience;
  final String? description;
  final String? thumbnailUrl;
  final List<MusicTrack> topSongs;
  final List<({String title, List<MusicItem> items})> shelves;

  /// Los vídeos del artista (se reproducen como canciones: suena su audio).
  final List<MusicTrack> videos;

  /// Playlists en las que aparece y playlists suyas («Aparece en», «Playlists
  /// de …»), cada grupo con su título.
  final List<({String title, List<MusicItem> items})> playlistShelves;
}

/// Página pública de un álbum: cabecera y pistas en orden.
class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.title,
    required this.artist,
    required this.tracks,
    this.artistId,
    this.year,
    this.info,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String? year;
  final String? info;
  final String? thumbnailUrl;
  final List<MusicTrack> tracks;
}

class MusicArtist extends MusicItem {
  const MusicArtist(
    super.id,
    super.title, {
    this.thumbnailUrl,
    this.detail,
    super.shelfTitle,
  });
  final String? thumbnailUrl;

  /// Oyentes o suscriptores tal como los entrega el catálogo.
  final String? detail;
}

class MusicPage {
  const MusicPage(
    this.items,
    this.nextCursor,
    this.playlist,
    this.excludedCount, [
    this.title,
    this.editable = false,
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
    data['editable'] == true,
  );

  final List<MusicItem> items;
  final String? nextCursor;
  final MusicPlaylist? playlist;
  final int excludedCount;
  final String? title;

  /// La playlist es de la cuenta (se puede editar y eliminar).
  final bool editable;
}
