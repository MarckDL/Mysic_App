import type { Track } from '../../catalog/domain/music-provider.js';
import type { RatingStatus } from './rating.js';

export interface RatingRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  status(ownerId: string, catalogTrackId: string): Promise<RatingStatus>;
  upsert(ownerId: string, track: Track, score: number): Promise<RatingStatus>;
}
