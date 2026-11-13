import type { CatalogService } from '../../catalog/application/catalog-service.js';
import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import {
  PlaylistNotFoundError,
  PlaylistTrackUnavailableError,
  UserNotSyncedError,
  type PlaylistInput,
  type PlaylistUpdate,
} from '../domain/playlist.js';
import type { PlaylistRepository } from '../domain/playlist-repository.js';

export class PlaylistService {
  static readonly maximumItems = 500;

  constructor(
    private readonly repository: PlaylistRepository,
    private readonly catalog: CatalogService,
  ) {}

  private async owner(identity: AuthIdentity): Promise<string> {
    const ownerId = await this.repository.findUserId(identity.firebaseUid);
    if (!ownerId) throw new UserNotSyncedError();
    return ownerId;
  }

  private local<T>(playlist: T) {
    return { ...playlist, origin: 'mysic' as const, readOnly: false as const };
  }

  async list(identity: AuthIdentity) {
    return (await this.repository.listOwned(await this.owner(identity))).map(
      (playlist) => this.local(playlist),
    );
  }

  async detail(identity: AuthIdentity, playlistId: string) {
    const playlist = await this.repository.findAccessible(
      await this.owner(identity),
      playlistId,
    );
    if (!playlist) throw new PlaylistNotFoundError();
    return this.local(playlist);
  }

  async create(identity: AuthIdentity, input: PlaylistInput) {
    return this.local(
      await this.repository.create(await this.owner(identity), input),
    );
  }

  async update(
    identity: AuthIdentity,
    playlistId: string,
    input: PlaylistUpdate,
  ) {
    const playlist = await this.repository.updateOwned(
      await this.owner(identity),
      playlistId,
      input,
    );
    if (!playlist) throw new PlaylistNotFoundError();
    return this.local(playlist);
  }

  async delete(identity: AuthIdentity, playlistId: string) {
    if (
      !(await this.repository.deleteOwned(
        await this.owner(identity),
        playlistId,
      ))
    )
      throw new PlaylistNotFoundError();
  }

  async addTrack(
    identity: AuthIdentity,
    playlistId: string,
    catalogTrackId: string,
  ) {
    const ownerId = await this.owner(identity);
    const sourceId = catalogTrackId.slice('youtube:'.length);
    const track = await this.catalog.getTrack(sourceId);
    if (!track || track.id !== catalogTrackId)
      throw new PlaylistTrackUnavailableError();
    const playlist = await this.repository.addTrackOwned(
      ownerId,
      playlistId,
      track,
      PlaylistService.maximumItems,
    );
    if (!playlist) throw new PlaylistNotFoundError();
    return this.local(playlist);
  }

  async removeTrack(
    identity: AuthIdentity,
    playlistId: string,
    itemId: string,
  ) {
    const playlist = await this.repository.removeTrackOwned(
      await this.owner(identity),
      playlistId,
      itemId,
    );
    if (!playlist) throw new PlaylistNotFoundError();
    return this.local(playlist);
  }

  async reorder(
    identity: AuthIdentity,
    playlistId: string,
    itemIds: readonly string[],
  ) {
    const playlist = await this.repository.reorderOwned(
      await this.owner(identity),
      playlistId,
      itemIds,
    );
    if (!playlist) throw new PlaylistNotFoundError();
    return this.local(playlist);
  }
}
