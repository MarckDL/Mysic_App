import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { YoutubeLibraryClient } from '../domain/youtube-library-client.js';
import {
  YoutubeLibraryUserNotSyncedError,
  YoutubeRemotePlaylistNotFoundError,
} from '../domain/youtube-library.js';
import type { YoutubeLibraryRepository } from '../domain/youtube-library-repository.js';

export class YoutubeLibraryService {
  constructor(
    private readonly repository: YoutubeLibraryRepository,
    private readonly client: YoutubeLibraryClient,
  ) {}

  private async owner(identity: AuthIdentity) {
    const ownerId = await this.repository.findUserId(identity.firebaseUid);
    if (!ownerId) throw new YoutubeLibraryUserNotSyncedError();
    return ownerId;
  }

  async status(identity: AuthIdentity) {
    return this.repository.status(await this.owner(identity));
  }

  async library(identity: AuthIdentity) {
    return this.repository.library(await this.owner(identity));
  }

  async sync(identity: AuthIdentity, accessToken: string) {
    const ownerId = await this.owner(identity);
    const snapshot = await this.client.fetchSnapshot(accessToken);
    return this.repository.replace(ownerId, snapshot);
  }

  async duplicate(identity: AuthIdentity, remotePlaylistId: string) {
    const playlist = await this.repository.duplicate(
      await this.owner(identity),
      remotePlaylistId,
    );
    if (!playlist) throw new YoutubeRemotePlaylistNotFoundError();
    return playlist;
  }

  async disconnect(identity: AuthIdentity) {
    return {
      disconnected: await this.repository.disconnect(
        await this.owner(identity),
      ),
    };
  }
}
