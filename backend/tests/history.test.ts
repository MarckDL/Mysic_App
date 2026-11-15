import { describe, it, expect, vi } from 'vitest';
import { HistoryService } from '../src/modules/history/application/history-service.js';
import type { HistoryRepository } from '../src/modules/history/domain/history.js';
import type { CatalogService } from '../src/modules/catalog/application/catalog-service.js';
const track = {
  id: 'youtube:abcdefghijk',
  source: 'youtube',
  sourceId: 'abcdefghijk',
  title: 'Song',
  artistName: 'Artist',
  durationSeconds: 120,
  thumbnailUrl: null,
};
function setup() {
  const repository: HistoryRepository = {
    owner: vi.fn(async () => 'owner'),
    save: vi.fn(async () => {}),
    list: vi.fn(async () => []),
  };
  const catalog = {
    getTrack: vi.fn(async () => track),
  } as unknown as CatalogService;
  return { repository, service: new HistoryService(repository, catalog) };
}
const input = () => ({
  sessionId: 'f406a218-04d7-45d4-8674-acd884361385',
  catalogTrackId: track.id,
  startedAt: new Date(Date.now() - 60000).toISOString(),
  listenedMs: 30000,
  completed: false,
});
describe('history rules', () => {
  it('rejects listening below the threshold', async () => {
    const { service, repository } = setup();
    await expect(
      service.save('uid', { ...input(), listenedMs: 29999 }),
    ).rejects.toThrow();
    expect(repository.save).not.toHaveBeenCalled();
  });
  it('does not infer completion from seeking to the end', async () => {
    const { service, repository } = setup();
    await service.save('uid', { ...input(), completed: true });
    expect(repository.save).toHaveBeenCalledWith(
      'owner',
      expect.objectContaining({ completed: false }),
      track,
    );
  });
  it('rejects more listening than elapsed wall time', async () => {
    const { service } = setup();
    await expect(
      service.save('uid', { ...input(), listenedMs: 100000 }),
    ).rejects.toThrow();
  });
  it('requires a synchronized owner', async () => {
    const { service, repository } = setup();
    vi.mocked(repository.owner).mockResolvedValue(null);
    await expect(service.list('uid', 20)).rejects.toThrow();
  });
  it('uses the authenticated uid to select the private list', async () => {
    const { service, repository } = setup();
    await service.list('account-b', 20);
    expect(repository.owner).toHaveBeenCalledWith('account-b');
    expect(repository.list).toHaveBeenCalledWith('owner', 21, undefined);
  });
});
