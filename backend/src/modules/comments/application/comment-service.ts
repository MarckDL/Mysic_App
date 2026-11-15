import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { CatalogService } from '../../catalog/application/catalog-service.js';
import { ProviderTimeoutError } from '../../catalog/domain/music-provider.js';
import {
  CommentError,
  type CommentRepository,
  type ModerationAction,
  type PageRequest,
  type ReportReason,
} from '../domain/comment.js';

export class CommentService {
  constructor(
    private readonly repository: CommentRepository,
    private readonly catalog: CatalogService,
  ) {}

  private async userId(identity: AuthIdentity) {
    const id = await this.repository.findUserId(identity.firebaseUid);
    if (!id) throw new CommentError('USER_NOT_SYNCED');
    return id;
  }

  private async moderatorId(identity: AuthIdentity) {
    if (identity.moderator !== true) throw new CommentError('FORBIDDEN');
    return this.userId(identity);
  }

  async list(identity: AuthIdentity, catalogId: string, page: PageRequest) {
    return this.repository.list(
      await this.userId(identity),
      catalogId.slice('youtube:'.length),
      page,
    );
  }

  async create(identity: AuthIdentity, catalogId: string, body: string) {
    const userId = await this.userId(identity);
    const track = await this.catalog
      .getTrack(catalogId.slice('youtube:'.length))
      .catch((error: unknown) => {
        throw new CommentError(
          error instanceof ProviderTimeoutError
            ? 'CATALOG_TIMEOUT'
            : 'CATALOG_UNAVAILABLE',
        );
      });
    if (!track || track.id !== catalogId)
      throw new CommentError('TRACK_NOT_FOUND');
    return this.repository.create(userId, track, body);
  }

  async edit(identity: AuthIdentity, id: string, body: string) {
    return this.repository.edit(await this.userId(identity), id, body);
  }

  async remove(identity: AuthIdentity, id: string) {
    await this.repository.remove(await this.userId(identity), id);
  }

  async report(identity: AuthIdentity, id: string, reason: ReportReason) {
    await this.repository.report(await this.userId(identity), id, reason);
  }

  async queue(identity: AuthIdentity, page: PageRequest) {
    await this.moderatorId(identity);
    return this.repository.queue(page);
  }

  async resolve(identity: AuthIdentity, id: string, action: ModerationAction) {
    await this.repository.resolve(await this.moderatorId(identity), id, action);
  }
}
