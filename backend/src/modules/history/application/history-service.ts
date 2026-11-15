import type { CatalogService } from '../../catalog/application/catalog-service.js';
import {
  HistoryInvalid,
  type HistoryInput,
  type HistoryRepository,
} from '../domain/history.js';
export class HistoryService {
  constructor(
    private repository: HistoryRepository,
    private catalog: CatalogService,
  ) {}
  async owner(uid: string) {
    const id = await this.repository.owner(uid);
    if (!id) throw new HistoryInvalid('Perfil no sincronizado');
    return id;
  }
  async save(uid: string, input: HistoryInput) {
    const owner = await this.owner(uid);
    const elapsed = Date.now() - Date.parse(input.startedAt);
    if (elapsed < -5000 || input.listenedMs > elapsed + 5000)
      throw new HistoryInvalid();
    const track = await this.catalog.getTrack(input.catalogTrackId.slice(8));
    if (!track || track.id !== input.catalogTrackId) throw new HistoryInvalid();
    const threshold =
      track.durationSeconds && track.durationSeconds > 0
        ? Math.min(30000, track.durationSeconds * 500)
        : 30000;
    if (input.listenedMs < threshold) throw new HistoryInvalid();
    input = {
      ...input,
      completed:
        input.completed &&
        !!track.durationSeconds &&
        input.listenedMs >= track.durationSeconds * 900,
    };
    await this.repository.save(owner, input, track);
  }
  async list(
    uid: string,
    limit: number,
    cursor?: { startedAt: string; id: string },
  ) {
    const rows = await this.repository.list(
      await this.owner(uid),
      limit + 1,
      cursor,
    );
    const items = rows.slice(0, limit);
    const last = items.at(-1);
    return {
      items,
      nextCursor:
        rows.length > limit && last
          ? Buffer.from(
              JSON.stringify({ startedAt: last.startedAt, id: last.id }),
            ).toString('base64url')
          : null,
    };
  }
}
