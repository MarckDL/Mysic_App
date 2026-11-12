import type { Track } from '../../catalog/domain/music-provider.js';
import type { RatingSummary } from './rating.js';

export interface RatingRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  get(
    ownerId: string,
    source: string,
    sourceId: string,
  ): Promise<RatingSummary>;
  upsert(ownerId: string, track: Track, score: number): Promise<RatingSummary>;
  delete(
    ownerId: string,
    source: string,
    sourceId: string,
  ): Promise<RatingSummary>;
}
