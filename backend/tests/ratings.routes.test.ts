import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type {
  MusicProvider,
  Track,
} from '../src/modules/catalog/domain/music-provider.js';
import type { RatingRepository } from '../src/modules/ratings/domain/rating-repository.js';

const sourceId = 'abcdefghijk';
const track: Track = {
  id: `youtube:${sourceId}`,
  source: 'youtube',
  sourceId,
  title: 'Song',
  artistName: 'Artist',
  durationSeconds: 123,
  thumbnailUrl: null,
};

function fixture() {
  const scores = new Map<string, number>([['owner-a', 4]]);
  const result = (owner: string) => ({
    myScore: scores.get(owner) ?? null,
    averageScore:
      scores.size === 0
        ? null
        : [...scores.values()].reduce((sum, score) => sum + score, 0) /
          scores.size,
    ratingCount: scores.size,
  });
  const repository: RatingRepository = {
    findUserId: vi.fn(async (uid) =>
      uid === 'unsynced' ? null : `owner-${uid}`,
    ),
    get: vi.fn(async (owner) => result(owner)),
    upsert: vi.fn(async (owner, _track, score) => {
      scores.set(owner, score);
      return result(owner);
    }),
    delete: vi.fn(async (owner) => {
      scores.delete(owner);
      return result(owner);
    }),
  };
  const music: MusicProvider = {
    search: vi.fn(async () => [track]),
    getTrack: vi.fn(async (id) => (id === sourceId ? track : null)),
    resolvePlayback: vi.fn<MusicProvider['resolvePlayback']>(async () => ({
      mode: 'unavailable',
      reason: 'test',
    })),
  };
  const app = createApp({
    ratingRepository: repository,
    musicProvider: music,
    tokenVerifier: {
      async verify(token) {
        return {
          firebaseUid: token,
          provider: token === 'password' ? 'password' : 'google.com',
        };
      },
    },
  });
  return { app, repository, music };
}

describe('rutas de calificaciones', () => {
  it('requiere cuenta Google sincronizada', async () => {
    const { app } = fixture();
    expect(
      (await request(app).get(`/api/v1/ratings/youtube/${sourceId}`)).status,
    ).toBe(401);
    expect(
      (
        await request(app)
          .get(`/api/v1/ratings/youtube/${sourceId}`)
          .auth('password', { type: 'bearer' })
      ).status,
    ).toBe(403);
    expect(
      (
        await request(app)
          .get(`/api/v1/ratings/youtube/${sourceId}`)
          .auth('unsynced', { type: 'bearer' })
      ).body.error.code,
    ).toBe('USER_NOT_SYNCED');
  });

  it('devuelve promedio público y puntuación aislada por token', async () => {
    const { app, repository } = fixture();
    const own = await request(app)
      .get(`/api/v1/ratings/youtube/${sourceId}`)
      .auth('a', { type: 'bearer' });
    expect(own.body).toEqual({ myScore: 4, averageScore: 4, ratingCount: 1 });
    const other = await request(app)
      .get(`/api/v1/ratings/youtube/${sourceId}`)
      .auth('b', { type: 'bearer' });
    expect(other.body).toEqual({
      myScore: null,
      averageScore: 4,
      ratingCount: 1,
    });
    expect(repository.get).toHaveBeenCalledWith('owner-b', 'youtube', sourceId);
    expect(own.headers['cache-control']).toBe('no-store');
  });

  it('crea o actualiza una sola calificación y recalcula promedio', async () => {
    const { app, repository, music } = fixture();
    const first = await request(app)
      .put(`/api/v1/ratings/youtube/${sourceId}`)
      .auth('b', { type: 'bearer' })
      .send({ score: 2 });
    expect(first.body).toEqual({ myScore: 2, averageScore: 3, ratingCount: 2 });
    const updated = await request(app)
      .put(`/api/v1/ratings/youtube/${sourceId}`)
      .auth('b', { type: 'bearer' })
      .send({ score: 5 });
    expect(updated.body).toEqual({
      myScore: 5,
      averageScore: 4.5,
      ratingCount: 2,
    });
    expect(repository.upsert).toHaveBeenLastCalledWith('owner-b', track, 5);
    expect(music.getTrack).toHaveBeenCalledWith(sourceId, expect.anything());
  });

  it('elimina la propia sin afectar las demás', async () => {
    const { app, repository } = fixture();
    const removed = await request(app)
      .delete(`/api/v1/ratings/youtube/${sourceId}`)
      .auth('a', { type: 'bearer' });
    expect(removed.body).toEqual({
      myScore: null,
      averageScore: null,
      ratingCount: 0,
    });
    expect(repository.delete).toHaveBeenCalledWith(
      'owner-a',
      'youtube',
      sourceId,
    );
  });

  it('rechaza puntuaciones y campos fuera del contrato', async () => {
    const { app } = fixture();
    const responses = await Promise.all([
      request(app)
        .put(`/api/v1/ratings/youtube/${sourceId}`)
        .auth('a', { type: 'bearer' })
        .send({ score: 0 }),
      request(app)
        .put(`/api/v1/ratings/youtube/${sourceId}`)
        .auth('a', { type: 'bearer' })
        .send({ score: 6 }),
      request(app)
        .put(`/api/v1/ratings/youtube/${sourceId}`)
        .auth('a', { type: 'bearer' })
        .send({ score: 5, userId: 'owner-b' }),
      request(app)
        .get(`/api/v1/ratings/spotify/${sourceId}`)
        .auth('a', { type: 'bearer' }),
    ]);
    expect(responses.map((value) => value.status)).toEqual([
      400, 400, 400, 400,
    ]);
  });
});
