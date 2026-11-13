import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type {
  MusicProvider,
  Track,
} from '../src/modules/catalog/domain/music-provider.js';
import type { FavoriteRepository } from '../src/modules/favorites/domain/favorite-repository.js';
import type { RatingRepository } from '../src/modules/ratings/domain/rating-repository.js';

const track: Track = {
  id: 'youtube:abcdefghijk',
  source: 'youtube',
  sourceId: 'abcdefghijk',
  title: 'Song',
  artistName: 'Artist',
  durationSeconds: 123,
  thumbnailUrl: null,
};

function fixture() {
  const favorites = new Map<string, Set<string>>();
  const scores = new Map<string, Map<string, number>>();
  const favoriteRepository: FavoriteRepository = {
    findUserId: vi.fn(async (uid) =>
      uid === 'unsynced' ? null : `owner-${uid}`,
    ),
    list: vi.fn(async (owner) =>
      favorites.get(owner)?.has(track.id)
        ? [{ createdAt: '2026-11-12T18:00:00.000Z', track }]
        : [],
    ),
    has: vi.fn(async (owner, id) => favorites.get(owner)?.has(id) ?? false),
    add: vi.fn(async (owner, value) => {
      const owned = favorites.get(owner) ?? new Set<string>();
      owned.add(value.id);
      favorites.set(owner, owned);
    }),
    remove: vi.fn(async (owner, id) => {
      favorites.get(owner)?.delete(id);
    }),
  };
  const status = (owner: string) => {
    const values = [...scores.values()]
      .map((owned) => owned.get(track.id))
      .filter((score): score is number => score !== undefined);
    return {
      myRating: scores.get(owner)?.get(track.id) ?? null,
      ratingAverage: values.length
        ? values.reduce((total, score) => total + score, 0) / values.length
        : null,
      ratingCount: values.length,
    };
  };
  const ratingRepository: RatingRepository = {
    findUserId: vi.fn(async (uid) =>
      uid === 'unsynced' ? null : `owner-${uid}`,
    ),
    status: vi.fn(async (owner) => status(owner)),
    upsert: vi.fn(async (owner, value, score) => {
      const owned = scores.get(owner) ?? new Map<string, number>();
      owned.set(value.id, score);
      scores.set(owner, owned);
      return status(owner);
    }),
  };
  const music: MusicProvider = {
    search: vi.fn(async () => [track]),
    getTrack: vi.fn(async () => track),
    resolvePlayback: vi.fn<MusicProvider['resolvePlayback']>(async () => ({
      mode: 'unavailable',
      reason: 'test',
    })),
  };
  const app = createApp({
    favoriteRepository,
    ratingRepository,
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
  return { app, favoriteRepository, ratingRepository, music };
}

describe('rutas de favoritos y calificaciones', () => {
  it('requiere Google y un usuario sincronizado', async () => {
    const { app } = fixture();
    expect((await request(app).get('/api/v1/favorites')).status).toBe(401);
    expect(
      (
        await request(app)
          .get('/api/v1/favorites')
          .auth('password', { type: 'bearer' })
      ).status,
    ).toBe(403);
    const missing = await request(app)
      .get('/api/v1/favorites')
      .auth('unsynced', { type: 'bearer' });
    expect(missing.status).toBe(404);
    expect(missing.body.error.code).toBe('USER_NOT_SYNCED');
  });

  it('agrega un favorito de forma idempotente, lo lista y lo retira', async () => {
    const { app, favoriteRepository, music } = fixture();
    for (let attempt = 0; attempt < 2; attempt++) {
      const response = await request(app)
        .put(`/api/v1/favorites/${track.id}`)
        .auth('a', { type: 'bearer' })
        .send({});
      expect(response.status).toBe(200);
      expect(response.body.isFavorite).toBe(true);
    }
    expect(music.getTrack).toHaveBeenCalledTimes(1);
    expect(favoriteRepository.add).toHaveBeenLastCalledWith('owner-a', track);
    const listed = await request(app)
      .get('/api/v1/favorites')
      .auth('a', { type: 'bearer' });
    expect(listed.body.items).toHaveLength(1);
    expect(listed.headers['cache-control']).toBe('no-store');
    const removed = await request(app)
      .delete(`/api/v1/favorites/${track.id}`)
      .auth('a', { type: 'bearer' });
    expect(removed.body).toEqual({ isFavorite: false });
    expect(
      (
        await request(app)
          .get('/api/v1/favorites')
          .auth('a', { type: 'bearer' })
      ).body.items,
    ).toHaveLength(0);
  });

  it('aísla favoritos y ratings personales entre cuentas', async () => {
    const { app } = fixture();
    await request(app)
      .put(`/api/v1/favorites/${track.id}`)
      .auth('a', { type: 'bearer' })
      .send({});
    const a = await request(app)
      .get(`/api/v1/tracks/${track.id}/interactions`)
      .auth('a', { type: 'bearer' });
    const b = await request(app)
      .get(`/api/v1/tracks/${track.id}/interactions`)
      .auth('b', { type: 'bearer' });
    expect(a.body.isFavorite).toBe(true);
    expect(b.body.isFavorite).toBe(false);
  });

  it('crea, modifica y agrega ratings correctamente', async () => {
    const { app, ratingRepository } = fixture();
    const rate = (user: string, score: number) =>
      request(app)
        .put(`/api/v1/ratings/${track.id}`)
        .auth(user, { type: 'bearer' })
        .send({ score });
    expect((await rate('a', 2)).body).toEqual({
      myRating: 2,
      ratingAverage: 2,
      ratingCount: 1,
    });
    expect((await rate('a', 4)).body.ratingCount).toBe(1);
    const second = await rate('b', 5);
    expect(second.body).toEqual({
      myRating: 5,
      ratingAverage: 4.5,
      ratingCount: 2,
    });
    const status = await request(app)
      .get(`/api/v1/tracks/${track.id}/interactions`)
      .auth('a', { type: 'bearer' });
    expect(status.body).toEqual({
      isFavorite: false,
      myRating: 4,
      ratingAverage: 4.5,
      ratingCount: 2,
    });
    expect(ratingRepository.upsert).toHaveBeenCalledTimes(3);
  });

  it('rechaza IDs, scores y propiedades desconocidas', async () => {
    const { app } = fixture();
    const responses = await Promise.all([
      request(app)
        .put('/api/v1/favorites/bad')
        .auth('a', { type: 'bearer' })
        .send({}),
      request(app)
        .put(`/api/v1/ratings/${track.id}`)
        .auth('a', { type: 'bearer' })
        .send({ score: 0 }),
      request(app)
        .put(`/api/v1/ratings/${track.id}`)
        .auth('a', { type: 'bearer' })
        .send({ score: 3, userId: 'owner-b' }),
    ]);
    expect(responses.map((response) => response.status)).toEqual([
      400, 400, 400,
    ]);
  });
});
