import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { CatalogService } from '../../catalog/application/catalog-service.js';
import {
  FavoriteTrackUnavailableError,
  FavoriteUserNotSyncedError,
} from '../domain/favorite.js';
import type { FavoriteRepository } from '../domain/favorite-repository.js';

export class FavoriteService {
  constructor(
    private readonly repository: FavoriteRepository,
    private readonly catalog: CatalogService,
  ) {}

  private async owner(identity: AuthIdentity) {
    const ownerId = await this.repository.findUserId(identity.firebaseUid);
    if (!ownerId) throw new FavoriteUserNotSyncedError();
    return ownerId;
  }

  async list(identity: AuthIdentity) {
    return this.repository.list(await this.owner(identity));
  }

  async status(identity: AuthIdentity, source: string, sourceId: string) {
    return {
      favorite:
        (await this.repository.find(
          await this.owner(identity),
          source,
          sourceId,
        )) !== null,
    };
  }

  async add(identity: AuthIdentity, source: string, sourceId: string) {
    const ownerId = await this.owner(identity);
    const track = await this.catalog.getTrack(sourceId);
    if (!track || track.source !== source || track.sourceId !== sourceId)
      throw new FavoriteTrackUnavailableError();
    return this.repository.upsert(ownerId, track);
  }

  async remove(identity: AuthIdentity, source: string, sourceId: string) {
    return {
      deleted: await this.repository.delete(
        await this.owner(identity),
        source,
        sourceId,
      ),
    };
  }
}
