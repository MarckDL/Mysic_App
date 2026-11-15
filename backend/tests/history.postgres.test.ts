import { randomUUID } from 'node:crypto';
import { beforeAll, afterAll, describe, it, expect } from 'vitest';
import { PrismaHistoryRepository } from '../src/infrastructure/database/prisma-history-repository.js';
import {
  getDatabase,
  disconnectDatabase,
} from '../src/infrastructure/database/prisma.js';
import { HistoryConflict } from '../src/modules/history/domain/history.js';
import type { Track } from '../src/modules/catalog/domain/music-provider.js';
describe.skipIf(!process.env.TEST_DATABASE_URL)('history PostgreSQL', () => {
  const repo = new PrismaHistoryRepository();
  const prefix = `history-test-${randomUUID()}`;
  let a = '';
  let b = '';
  const sourceId = randomUUID().replaceAll('-', '').slice(0, 11);
  const track: Track = {
    id: `youtube:${sourceId}`,
    source: 'youtube',
    sourceId,
    title: 'History test',
    artistName: 'Test',
    durationSeconds: 180,
    thumbnailUrl: null,
  };
  beforeAll(async () => {
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    const users = await Promise.all(
      ['a', 'b'].map((n) =>
        getDatabase().user.create({
          data: { firebaseUid: `${prefix}-${n}`, displayName: n },
        }),
      ),
    );
    a = users[0]!.id;
    b = users[1]!.id;
  });
  afterAll(async () => {
    try {
      await getDatabase().user.deleteMany({
        where: { firebaseUid: { startsWith: prefix } },
      });
      await getDatabase().track.deleteMany({
        where: { source: 'youtube', sourceId },
      });
    } finally {
      await disconnectDatabase();
    }
  });
  it('preserves maxima under concurrent retries and isolates owners', async () => {
    const input = {
      sessionId: randomUUID(),
      catalogTrackId: track.id,
      startedAt: new Date(Date.now() - 120000).toISOString(),
      listenedMs: 30000,
      completed: false,
    };
    // The catalog track does not exist yet: exercise both unique-key races,
    // including late smaller checkpoints after the completed checkpoint.
    await Promise.all(
      [30000, 60000, 45000, 32000, 50000, 35000, 55000, 40000].map(
        (listenedMs) =>
          repo.save(
            a,
            { ...input, listenedMs, completed: listenedMs === 60000 },
            track,
          ),
      ),
    );
    await repo.save(a, input, track);
    const rows = await repo.list(a, 20);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ listenedMs: 60000, completed: true });
    expect(await repo.list(b, 20)).toEqual([]);
    await expect(repo.save(b, input, track)).rejects.toBeInstanceOf(
      HistoryConflict,
    );
    await expect(
      repo.save(a, { ...input, startedAt: new Date().toISOString() }, track),
    ).rejects.toBeInstanceOf(HistoryConflict);
  });
  it('paginates identical timestamps without repeats', async () => {
    const startedAt = new Date(Date.now() - 60000).toISOString();
    for (let i = 0; i < 3; i++)
      await repo.save(
        b,
        {
          sessionId: randomUUID(),
          catalogTrackId: track.id,
          startedAt,
          listenedMs: 30000,
          completed: false,
        },
        track,
      );
    const first = await repo.list(b, 2);
    const last = first[1]!;
    const second = await repo.list(b, 2, {
      id: last.id,
      startedAt: last.startedAt,
    });
    expect(first).toHaveLength(2);
    expect(second).toHaveLength(1);
    expect(new Set([...first, ...second].map((r) => r.id)).size).toBe(3);
  });
  it('enables RLS and cascades account deletion', async () => {
    const rows = await getDatabase().$queryRaw<
      { relrowsecurity: boolean }[]
    >`SELECT relrowsecurity FROM pg_class WHERE oid='mysic.listening_history'::regclass`;
    expect(rows[0]!.relrowsecurity).toBe(true);
    await getDatabase().user.delete({ where: { id: b } });
    expect(await repo.list(b, 20)).toEqual([]);
  });
});
