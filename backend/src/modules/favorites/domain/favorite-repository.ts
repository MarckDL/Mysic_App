import type { Track } from '../../catalog/domain/music-provider.js';
import type { FavoriteItem } from './favorite.js';

export interface FavoriteRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  list(ownerId: string): Promise<FavoriteItem[]>;
  find(
    ownerId: string,
    source: string,
    sourceId: string,
  ): Promise<FavoriteItem | null>;
  upsert(ownerId: string, track: Track): Promise<FavoriteItem>;
  delete(ownerId: string, source: string, sourceId: string): Promise<boolean>;
}
