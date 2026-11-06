import type { Track } from '../../catalog/domain/music-provider.js';

export type PlaylistVisibility = 'private' | 'public';

export interface PlaylistSummary {
  id: string;
  name: string;
  description: string | null;
  visibility: PlaylistVisibility;
  trackCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface PlaylistItem {
  id: string;
  position: number;
  addedAt: string;
  track: Track;
}

export interface PlaylistDetail extends PlaylistSummary {
  ownedByCurrentUser: boolean;
  tracks: PlaylistItem[];
}

export interface PlaylistInput {
  name: string;
  description: string | null;
  visibility: PlaylistVisibility;
}

export type PlaylistUpdate = Partial<PlaylistInput>;

export class UserNotSyncedError extends Error {}
export class PlaylistNotFoundError extends Error {}
export class PlaylistCapacityError extends Error {}
export class PlaylistTrackUnavailableError extends Error {}
export class PlaylistInvalidOrderError extends Error {}
export class PlaylistConflictError extends Error {}
export class PlaylistDatabaseError extends Error {}
