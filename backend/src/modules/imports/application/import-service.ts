import { createHash } from 'node:crypto';
import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { CatalogService } from '../../catalog/application/catalog-service.js';
import {
  ImportError,
  requireDraft,
  type ImportInput,
  type ImportItem,
  type ImportRepository,
} from '../domain/music-import.js';

export class ImportService {
  // Import resolution shares the catalog's eight pending slots with normal browsing.
  private activeBatches = 0;

  constructor(
    private readonly repository: ImportRepository,
    private readonly catalog: CatalogService,
  ) {}

  private async owner(identity: AuthIdentity) {
    const id = await this.repository.findUserId(identity.firebaseUid);
    if (!id)
      throw new ImportError(
        404,
        'USER_NOT_SYNCED',
        'Sincroniza tu perfil para continuar',
      );
    return id;
  }

  async prepare(identity: AuthIdentity, input: ImportInput) {
    const fingerprint = createHash('sha256')
      .update(JSON.stringify({ name: input.name, sourceIds: input.sourceIds }))
      .digest('hex');
    return this.repository.prepare(
      await this.owner(identity),
      input,
      fingerprint,
    );
  }

  async list(identity: AuthIdentity) {
    return this.repository.list(await this.owner(identity));
  }

  async get(identity: AuthIdentity, id: string) {
    return requireDraft(
      await this.repository.find(await this.owner(identity), id),
    );
  }

  async resolve(identity: AuthIdentity, id: string, indices: number[]) {
    const owner = await this.owner(identity);
    const draft = requireDraft(await this.repository.find(owner, id));
    if (draft.confirmedAt) return draft;
    if (indices.some((index) => !draft.items[index])) {
      throw new ImportError(
        400,
        'INVALID_REQUEST',
        'Posición de canción inválida',
      );
    }
    if (this.activeBatches >= 2) {
      throw new ImportError(
        429,
        'IMPORT_BUSY',
        'Espera unos segundos antes de continuar',
      );
    }
    this.activeBatches++;
    try {
      const updates = await Promise.all(
        indices.map(async (index) => {
          const item = draft.items[index]!;
          if (item.status === 'ready' || item.status === 'unavailable')
            return { index, item };
          let resolved: ImportItem;
          try {
            const track = await this.catalog.getTrack(item.sourceId);
            resolved =
              track?.source === 'youtube' && track.sourceId === item.sourceId
                ? { sourceId: item.sourceId, status: 'ready', track }
                : { sourceId: item.sourceId, status: 'unavailable' };
          } catch {
            resolved = { sourceId: item.sourceId, status: 'retry' };
          }
          return { index, item: resolved };
        }),
      );
      return await this.repository.merge(owner, id, updates);
    } finally {
      this.activeBatches--;
    }
  }

  async confirm(identity: AuthIdentity, id: string) {
    return this.repository.confirm(await this.owner(identity), id);
  }

  async discard(identity: AuthIdentity, id: string) {
    await this.repository.discard(await this.owner(identity), id);
  }
}
