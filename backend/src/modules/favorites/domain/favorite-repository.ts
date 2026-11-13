import type { Track } from '../../catalog/domain/music-provider.js';
import type { FavoriteItem } from './favorite.js';

export interface FavoriteRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  list(ownerId: string): Promise<FavoriteItem[]>;
  has(ownerId: string, catalogTrackId: string): Promise<boolean>;
  add(ownerId: string, track: Track): Promise<void>;
  remove(ownerId: string, catalogTrackId: string): Promise<void>;
}
