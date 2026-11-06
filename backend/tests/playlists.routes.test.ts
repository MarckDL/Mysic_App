import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type {
  MusicProvider,
  Track,
} from '../src/modules/catalog/domain/music-provider.js';
import type { PlaylistDetail } from '../src/modules/playlists/domain/playlist.js';
import type { PlaylistRepository } from '../src/modules/playlists/domain/playlist-repository.js';

const playlistId = '11111111-1111-4111-8111-111111111111';
const itemId = '22222222-2222-4222-8222-222222222222';
const track: Track = {
  id: 'youtube:abcdefghijk',
  source: 'youtube',
  sourceId: 'abcdefghijk',
  title: 'Song',
  artistName: 'Artist',
  durationSeconds: 123,
  thumbnailUrl: null,
};

function detail(owner = true): PlaylistDetail {
  return {
    id: playlistId,
    name: 'Lista',
    description: null,
    visibility: owner ? 'private' : 'public',
    trackCount: 1,
    createdAt: '2026-11-06T00:00:00.000Z',
    updatedAt: '2026-11-06T00:00:00.000Z',
    ownedByCurrentUser: owner,
    tracks: [
      {
        id: itemId,
        position: 0,
        addedAt: '2026-11-06T00:00:00.000Z',
        track,
      },
    ],
  };
}

function fixture() {
  const repository: PlaylistRepository = {
    findUserId: vi.fn(async (uid) =>
      uid === 'unsynced' ? null : `owner-${uid}`,
    ),
    listOwned: vi.fn(async () => [detail()]),
    findAccessible: vi.fn(async (owner) =>
      owner === 'owner-a' || owner === 'owner-reader'
        ? detail(owner === 'owner-a')
        : null,
    ),
    create: vi.fn(async () => detail()),
    updateOwned: vi.fn(async (owner) =>
      owner === 'owner-a' ? detail() : null,
    ),
    deleteOwned: vi.fn(async (owner) => owner === 'owner-a'),
    addTrackOwned: vi.fn(async (owner) =>
      owner === 'owner-a' ? detail() : null,
    ),
    removeTrackOwned: vi.fn(async (owner) =>
      owner === 'owner-a' ? detail() : null,
    ),
    reorderOwned: vi.fn(async (owner) =>
      owner === 'owner-a' ? detail() : null,
    ),
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
    playlistRepository: repository,
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

describe('rutas de playlists', () => {
  it('requiere identidad Google y perfil sincronizado', async () => {
    const { app } = fixture();
    expect((await request(app).get('/api/v1/playlists')).status).toBe(401);
    expect(
      (
        await request(app)
          .get('/api/v1/playlists')
          .auth('password', { type: 'bearer' })
      ).status,
    ).toBe(403);
    const missing = await request(app)
      .get('/api/v1/playlists')
      .auth('unsynced', { type: 'bearer' });
    expect(missing.status).toBe(404);
    expect(missing.body.error.code).toBe('USER_NOT_SYNCED');
  });

  it('crea y lista sin aceptar propietario del cliente', async () => {
    const { app, repository } = fixture();
    const created = await request(app)
      .post('/api/v1/playlists')
      .auth('a', { type: 'bearer' })
      .send({ name: ' Lista ', description: null, visibility: 'private' });
    expect(created.status).toBe(201);
    expect(repository.create).toHaveBeenCalledWith('owner-a', {
      name: 'Lista',
      description: null,
      visibility: 'private',
    });
    expect(
      (
        await request(app)
          .post('/api/v1/playlists')
          .auth('a', { type: 'bearer' })
          .send({ name: 'X', userId: 'owner-b' })
      ).status,
    ).toBe(400);
    const listed = await request(app)
      .get('/api/v1/playlists')
      .auth('a', { type: 'bearer' });
    expect(listed.status).toBe(200);
    expect(listed.body.items).toHaveLength(1);
    expect(listed.headers['cache-control']).toBe('no-store');
  });

  it('permite lectura pública pero oculta escrituras ajenas', async () => {
    const { app } = fixture();
    const visible = await request(app)
      .get(`/api/v1/playlists/${playlistId}`)
      .auth('reader', { type: 'bearer' });
    expect(visible.status).toBe(200);
    expect(visible.body.ownedByCurrentUser).toBe(false);
    for (const operation of [
      request(app)
        .patch(`/api/v1/playlists/${playlistId}`)
        .send({ name: 'Ajena' }),
      request(app).delete(`/api/v1/playlists/${playlistId}`),
      request(app)
        .post(`/api/v1/playlists/${playlistId}/tracks`)
        .send({ catalogTrackId: track.id }),
      request(app).delete(`/api/v1/playlists/${playlistId}/tracks/${itemId}`),
      request(app)
        .put(`/api/v1/playlists/${playlistId}/tracks/order`)
        .send({ itemIds: [itemId] }),
    ]) {
      const response = await operation.auth('reader', { type: 'bearer' });
      expect(response.status).toBe(404);
      expect(response.body.error.code).toBe('PLAYLIST_NOT_FOUND');
    }
  });

  it('añade, retira y reordena ocurrencias del propietario', async () => {
    const { app, repository, music } = fixture();
    const added = await request(app)
      .post(`/api/v1/playlists/${playlistId}/tracks`)
      .auth('a', { type: 'bearer' })
      .send({ catalogTrackId: track.id });
    expect(added.status).toBe(200);
    expect(music.getTrack).toHaveBeenCalledWith(
      'abcdefghijk',
      expect.anything(),
    );
    expect(repository.addTrackOwned).toHaveBeenCalledWith(
      'owner-a',
      playlistId,
      track,
      500,
    );
    expect(
      (
        await request(app)
          .delete(`/api/v1/playlists/${playlistId}/tracks/${itemId}`)
          .auth('a', { type: 'bearer' })
      ).status,
    ).toBe(200);
    expect(
      (
        await request(app)
          .put(`/api/v1/playlists/${playlistId}/tracks/order`)
          .auth('a', { type: 'bearer' })
          .send({ itemIds: [itemId] })
      ).status,
    ).toBe(200);
  });

  it('rechaza UUID, campos, límites y órdenes inválidos en la frontera', async () => {
    const { app } = fixture();
    const responses = await Promise.all([
      request(app)
        .get('/api/v1/playlists/not-a-uuid')
        .auth('a', { type: 'bearer' }),
      request(app)
        .post('/api/v1/playlists')
        .auth('a', { type: 'bearer' })
        .send({ name: ' '.repeat(2) }),
      request(app)
        .patch(`/api/v1/playlists/${playlistId}`)
        .auth('a', { type: 'bearer' })
        .send({}),
      request(app)
        .put(`/api/v1/playlists/${playlistId}/tracks/order`)
        .auth('a', { type: 'bearer' })
        .send({ itemIds: ['bad'] }),
    ]);
    expect(responses.map((response) => response.status)).toEqual([
      400, 400, 400, 400,
    ]);
  });
});
