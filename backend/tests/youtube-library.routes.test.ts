import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type { YoutubeLibraryClient } from '../src/modules/youtube-library/domain/youtube-library-client.js';
import type { YoutubeLibraryRepository } from '../src/modules/youtube-library/domain/youtube-library-repository.js';

const status = {
  connected: true,
  displayName: 'Dino',
  avatarUrl: null,
  lastSyncedAt: '2026-11-12T18:00:00.000Z',
  playlistCount: 1,
  likedTrackCount: 1,
  subscriptionCount: 1,
};

function fixture() {
  const repository: YoutubeLibraryRepository = {
    findUserId: vi.fn(async (uid) =>
      uid === 'missing' ? null : `owner-${uid}`,
    ),
    status: vi.fn(async () => status),
    library: vi.fn(async () => ({
      likes: [],
      playlists: [],
      subscriptions: [],
    })),
    replace: vi.fn(async () => status),
    duplicate: vi.fn(async (_owner, id) => ({
      id,
      name: 'Importada',
      description: 'Duplicada desde YouTube',
      visibility: 'private' as const,
      trackCount: 2,
      createdAt: status.lastSyncedAt,
      updatedAt: status.lastSyncedAt,
      origin: 'mysic' as const,
      readOnly: false as const,
    })),
    disconnect: vi.fn(async () => true),
  };
  const client: YoutubeLibraryClient = {
    fetchSnapshot: vi.fn(async () => ({
      channel: { id: 'channel-a', displayName: 'Dino', avatarUrl: null },
      playlists: [],
      likes: [],
      subscriptions: [],
    })),
  };
  return {
    app: createApp({
      youtubeLibraryRepository: repository,
      youtubeLibraryClient: client,
      tokenVerifier: {
        async verify(token) {
          return { firebaseUid: token, provider: 'google.com' };
        },
      },
    }),
    repository,
    client,
  };
}

describe('biblioteca conectada de YouTube', () => {
  it('requiere Firebase y aísla el propietario con el token verificado', async () => {
    const { app, repository } = fixture();
    expect(
      (await request(app).get('/api/v1/integrations/youtube/status')).status,
    ).toBe(401);
    const response = await request(app)
      .get('/api/v1/integrations/youtube/status')
      .auth('a', { type: 'bearer' });
    expect(response.status).toBe(200);
    expect(response.body).toEqual(status);
    expect(repository.status).toHaveBeenCalledWith('owner-a');
    expect(response.headers['cache-control']).toBe('no-store');
  });

  it('usa el token temporal solo durante la sincronización', async () => {
    const { app, client, repository } = fixture();
    const temporaryToken = 'temporary-youtube-access-token';
    const response = await request(app)
      .post('/api/v1/integrations/youtube/sync')
      .auth('a', { type: 'bearer' })
      .set('X-YouTube-OAuth-Token', temporaryToken)
      .send({});
    expect(response.status).toBe(200);
    expect(client.fetchSnapshot).toHaveBeenCalledWith(temporaryToken);
    expect(repository.replace).toHaveBeenCalledWith(
      'owner-a',
      expect.objectContaining({
        channel: expect.objectContaining({ id: 'channel-a' }),
      }),
    );
    expect(JSON.stringify(response.body)).not.toContain(temporaryToken);
  });

  it('rechaza tokens ausentes, payload adicional y usuarios no sincronizados', async () => {
    const { app } = fixture();
    const missingToken = await request(app)
      .post('/api/v1/integrations/youtube/sync')
      .auth('a', { type: 'bearer' })
      .send({});
    const extraBody = await request(app)
      .post('/api/v1/integrations/youtube/sync')
      .auth('a', { type: 'bearer' })
      .set('X-YouTube-OAuth-Token', 'temporary-youtube-access-token')
      .send({ token: 'must-not-be-here' });
    const unsynced = await request(app)
      .get('/api/v1/integrations/youtube/status')
      .auth('missing', { type: 'bearer' });
    expect(missingToken.status).toBe(400);
    expect(extraBody.status).toBe(400);
    expect(unsynced.body.error.code).toBe('USER_NOT_SYNCED');
  });

  it('desconecta únicamente los datos importados del propietario', async () => {
    const { app, repository } = fixture();
    const response = await request(app)
      .delete('/api/v1/integrations/youtube')
      .auth('b', { type: 'bearer' });
    expect(response.body).toEqual({ disconnected: true });
    expect(repository.disconnect).toHaveBeenCalledWith('owner-b');
  });

  it('duplica una playlist remota como playlist privada del propietario', async () => {
    const { app, repository } = fixture();
    const id = '00000000-0000-4000-8000-000000000099';
    const response = await request(app)
      .post(`/api/v1/integrations/youtube/playlists/${id}/duplicate`)
      .auth('a', { type: 'bearer' })
      .send({});
    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ id, visibility: 'private' });
    expect(repository.duplicate).toHaveBeenCalledWith('owner-a', id);
  });
});
