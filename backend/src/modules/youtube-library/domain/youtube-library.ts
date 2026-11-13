import type { Track } from '../../catalog/domain/music-provider.js';

export interface YoutubeLibraryTrack extends Track {
  externalItemId: string;
  position: number;
}

export interface YoutubeLibraryPlaylist {
  externalId: string;
  title: string;
  thumbnailUrl: string | null;
  tracks: YoutubeLibraryTrack[];
}

export interface YoutubeLibrarySnapshot {
  channel: {
    id: string;
    displayName: string;
    avatarUrl: string | null;
  };
  playlists: YoutubeLibraryPlaylist[];
  likes: Track[];
  subscriptions: Array<{
    channelId: string;
    title: string;
    thumbnailUrl: string | null;
  }>;
}

export interface YoutubeConnectionStatus {
  connected: boolean;
  displayName: string | null;
  avatarUrl: string | null;
  lastSyncedAt: string | null;
  playlistCount: number;
  likedTrackCount: number;
  subscriptionCount: number;
}

export class YoutubeLibraryUserNotSyncedError extends Error {}
export class YoutubeRemotePlaylistNotFoundError extends Error {}
export class YoutubeLibraryUnauthorizedError extends Error {}
export class YoutubeLibraryQuotaError extends Error {}
export class YoutubeLibraryUnavailableError extends Error {}
export class YoutubeLibraryDatabaseError extends Error {}
