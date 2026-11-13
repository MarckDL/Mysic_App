import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { CatalogService } from '../../catalog/application/catalog-service.js';
import {
  RatingTrackNotFoundError,
  RatingUserNotSyncedError,
} from '../domain/rating.js';
import type { RatingRepository } from '../domain/rating-repository.js';

export class RatingService {
  constructor(
    private readonly repository: RatingRepository,
    private readonly catalog: CatalogService,
  ) {}

  async owner(identity: AuthIdentity): Promise<string> {
    const ownerId = await this.repository.findUserId(identity.firebaseUid);
    if (!ownerId) throw new RatingUserNotSyncedError();
    return ownerId;
  }

  async status(identity: AuthIdentity, catalogTrackId: string) {
    return this.repository.status(await this.owner(identity), catalogTrackId);
  }

  async rate(identity: AuthIdentity, catalogTrackId: string, score: number) {
    const ownerId = await this.owner(identity);
    const track = await this.catalog.getTrack(
      catalogTrackId.slice('youtube:'.length),
    );
    if (!track || track.id !== catalogTrackId)
      throw new RatingTrackNotFoundError();
    return this.repository.upsert(ownerId, track, score);
  }
}
