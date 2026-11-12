import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type {
  MusicProvider,
  Track,
} from '../src/modules/catalog/domain/music-provider.js';
import type { FavoriteRepository } from '../src/modules/favorites/domain/favorite-repository.js';

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
const favorite = { createdAt: '2026-11-12T00:00:00.000Z', track };

function fixture() {
  const owned = new Set(['owner-a']);
  const repository: FavoriteRepository = {
    findUserId: vi.fn(async (uid) =>
      uid === 'unsynced' ? null : `owner-${uid}`,
    ),
    list: vi.fn(async (owner) => (owned.has(owner) ? [favorite] : [])),
    find: vi.fn(async (owner) => (owned.has(owner) ? favorite : null)),
    upsert: vi.fn(async (owner) => {
      owned.add(owner);
      return favorite;
    }),
    delete: vi.fn(async (owner) => owned.delete(owner)),
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
    favoriteRepository: repository,
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

describe('rutas de favoritos', () => {
  it('requiere cuenta Google sincronizada', async () => {
    const { app } = fixture();
    expect((await request(app).get('/api/v1/favorites')).status).toBe(401);
    expect(
      (
        await request(app)
          .get('/api/v1/favorites')
          .auth('password', { type: 'bearer' })
      ).status,
    ).toBe(403);
    const unsynced = await request(app)
      .get('/api/v1/favorites')
      .auth('unsynced', { type: 'bearer' });
    expect(unsynced.status).toBe(404);
    expect(unsynced.body.error.code).toBe('USER_NOT_SYNCED');
  });

  it('lista y consulta únicamente los favoritos del token', async () => {
    const { app, repository } = fixture();
    const listed = await request(app)
      .get('/api/v1/favorites')
      .auth('a', { type: 'bearer' });
    expect(listed.status).toBe(200);
    expect(listed.body.items).toEqual([favorite]);
    expect(repository.list).toHaveBeenCalledWith('owner-a');
    const other = await request(app)
      .get(`/api/v1/favorites/youtube/${sourceId}`)
      .auth('b', { type: 'bearer' });
    expect(other.body).toEqual({ favorite: false });
    expect(repository.find).toHaveBeenCalledWith(
      'owner-b',
      'youtube',
      sourceId,
    );
    expect(listed.headers['cache-control']).toBe('no-store');
  });

  it('agrega de forma idempotente y elimina solo para el propietario', async () => {
    const { app, repository, music } = fixture();
    for (let index = 0; index < 2; index++) {
      const added = await request(app)
        .put(`/api/v1/favorites/youtube/${sourceId}`)
        .auth('b', { type: 'bearer' });
      expect(added.status).toBe(200);
      expect(added.body.track.id).toBe(track.id);
    }
    expect(repository.upsert).toHaveBeenCalledTimes(2);
    expect(music.getTrack).toHaveBeenCalledWith(sourceId, expect.anything());
    const removed = await request(app)
      .delete(`/api/v1/favorites/youtube/${sourceId}`)
      .auth('b', { type: 'bearer' });
    expect(removed.body).toEqual({ deleted: true });
    expect(repository.delete).toHaveBeenCalledWith(
      'owner-b',
      'youtube',
      sourceId,
    );
  });

  it('rechaza proveedor, id, cuerpo y consulta arbitrarios', async () => {
    const { app } = fixture();
    const responses = await Promise.all([
      request(app)
        .get(`/api/v1/favorites/spotify/${sourceId}`)
        .auth('a', { type: 'bearer' }),
      request(app)
        .get('/api/v1/favorites/youtube/bad')
        .auth('a', { type: 'bearer' }),
      request(app)
        .put(`/api/v1/favorites/youtube/${sourceId}`)
        .auth('a', { type: 'bearer' })
        .send({ userId: 'owner-b' }),
      request(app)
        .get('/api/v1/favorites?userId=owner-b')
        .auth('a', { type: 'bearer' }),
    ]);
    expect(responses.map((value) => value.status)).toEqual([
      400, 400, 400, 400,
    ]);
  });
});
