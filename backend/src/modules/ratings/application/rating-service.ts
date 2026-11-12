import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { CatalogService } from '../../catalog/application/catalog-service.js';
import {
  RatingTrackUnavailableError,
  RatingUserNotSyncedError,
} from '../domain/rating.js';
import type { RatingRepository } from '../domain/rating-repository.js';

export class RatingService {
  constructor(
    private readonly repository: RatingRepository,
    private readonly catalog: CatalogService,
  ) {}

  private async owner(identity: AuthIdentity) {
    const ownerId = await this.repository.findUserId(identity.firebaseUid);
    if (!ownerId) throw new RatingUserNotSyncedError();
    return ownerId;
  }

  async get(identity: AuthIdentity, source: string, sourceId: string) {
    return this.repository.get(await this.owner(identity), source, sourceId);
  }

  async set(
    identity: AuthIdentity,
    source: string,
    sourceId: string,
    score: number,
  ) {
    const ownerId = await this.owner(identity);
    const track = await this.catalog.getTrack(sourceId);
    if (!track || track.source !== source || track.sourceId !== sourceId)
      throw new RatingTrackUnavailableError();
    return this.repository.upsert(ownerId, track, score);
  }

  async remove(identity: AuthIdentity, source: string, sourceId: string) {
    return this.repository.delete(await this.owner(identity), source, sourceId);
  }
}
