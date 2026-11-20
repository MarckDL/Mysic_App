export const musicSurfaces = [
  'home',
  'songs',
  'liked',
  'channelLiked',
  'channelRecommendations',
  'albums',
  'album',
  'playlists',
  'playlist',
  'search',
  'history',
  'mysicRecents',
  'onRepeat',
  'artist',
  'artists',
] as const;

export type MusicSurface = (typeof musicSurfaces)[number];
export type MusicCapability = MusicSurface | 'playback' | 'recordListen';

export interface MusicAccount {
  id: string;
  name: string;
  historyPaused?: boolean;
}

export interface MusicTrack {
  kind: 'track';
  mediaType?: 'song' | 'video';
  id: string;
  title: string;
  artist: string;
  durationSeconds: number;
  playback: 'bundledPreview' | 'licensed' | 'native' | 'unavailable';
  audioUrl?: string;
  thumbnailUrl?: string;
  listenedAt?: string;
  entryId?: string;
  playCount?: number;
  artistId?: string;
}

export interface MusicPlaylist {
  kind: 'playlist';
  id: string;
  title: string;
  private: boolean;
  thumbnailUrl?: string;
}

export interface MusicArtist {
  kind: 'artist';
  id: string;
  title: string;
  thumbnailUrl?: string;
}

export interface MusicAlbum {
  kind: 'album';
  id: string;
  title: string;
  thumbnailUrl?: string;
}
export type MusicItem = (
  MusicTrack | MusicPlaylist | MusicArtist | MusicAlbum
) & {
  shelfTitle?: string;
  subtitle?: string;
};
export interface AccountPageResult {
  items: MusicItem[];
  nextCursor: string | null;
  playlist?: MusicPlaylist;
  title?: string;
  excludedCount: number;
}
export interface MusicPage {
  items: MusicItem[];
  continuation?: string;
  playlist?: MusicPlaylist;
  excludedCount?: number;
}

export interface MusicPageRequest {
  surface: MusicSurface;
  playlistId?: string;
  artistId?: string;
  query?: string;
  size: number;
  continuation?: string;
}

export interface MusicListen {
  activityEpoch?: number;
  trackId: string;
  listenedMs: number;
}

export interface YouTubeMusicProvider {
  readonly kind: 'preview' | 'youtubeMusic';
  readonly capabilities: readonly MusicCapability[];
  accounts(uid: string): readonly MusicAccount[];
  confirm(uid: string, accountId: string): Promise<MusicAccount>;
  read(
    uid: string,
    accountId: string,
    page: MusicPageRequest,
  ): Promise<MusicPage>;
  findListen(
    uid: string,
    accountId: string,
    id: string,
  ): Promise<MusicListen | null>;
  recordListen(
    uid: string,
    accountId: string,
    id: string,
    listen: MusicListen,
  ): Promise<void>;
}
