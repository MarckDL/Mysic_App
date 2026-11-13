import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { CatalogService } from '../../catalog/application/catalog-service.js';
import {
  FavoriteTrackNotFoundError,
  FavoriteUserNotSyncedError,
} from '../domain/favorite.js';
import type { FavoriteRepository } from '../domain/favorite-repository.js';

export class FavoriteService {
  constructor(
    private readonly repository: FavoriteRepository,
    private readonly catalog: CatalogService,
  ) {}

  async owner(identity: AuthIdentity): Promise<string> {
    const ownerId = await this.repository.findUserId(identity.firebaseUid);
    if (!ownerId) throw new FavoriteUserNotSyncedError();
    return ownerId;
  }

  async list(identity: AuthIdentity) {
    return this.repository.list(await this.owner(identity));
  }

  async status(identity: AuthIdentity, catalogTrackId: string) {
    return this.repository.has(await this.owner(identity), catalogTrackId);
  }

  async add(identity: AuthIdentity, catalogTrackId: string) {
    const ownerId = await this.owner(identity);
    const track = await this.catalog.getTrack(
      catalogTrackId.slice('youtube:'.length),
    );
    if (!track || track.id !== catalogTrackId)
      throw new FavoriteTrackNotFoundError();
    await this.repository.add(ownerId, track);
    return true;
  }

  async remove(identity: AuthIdentity, catalogTrackId: string) {
    await this.repository.remove(await this.owner(identity), catalogTrackId);
    return false;
  }
}
