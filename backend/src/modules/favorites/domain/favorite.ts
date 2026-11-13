import type { Track } from '../../catalog/domain/music-provider.js';

export interface FavoriteItem {
  createdAt: string;
  track: Track;
}

export class FavoriteUserNotSyncedError extends Error {}
export class FavoriteTrackNotFoundError extends Error {}
export class FavoriteDatabaseError extends Error {}
