import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';
import { CatalogService } from '../src/modules/catalog/application/catalog-service.js';
import type { MusicProvider } from '../src/modules/catalog/domain/music-provider.js';
import { ImportService } from '../src/modules/imports/application/import-service.js';
import type {
  ImportRepository,
  ImportItem,
  MusicImport,
} from '../src/modules/imports/domain/music-import.js';

const path = '/api/v1/imports/youtube-music';
const id = randomUUID();
const value: MusicImport = {
  id,
  userId: 'owner-a',
  fingerprint: 'test',
  name: 'Lista',
  items: ['abcdefghijk', 'bcdefghijkl'].map((sourceId) => ({
    sourceId,
    status: 'pending',
  })),
  expiresAt: new Date(Date.now() + 24 * 60 * 60_000),
  confirmedAt: null,
  playlistId: null,
  savedCount: 0,
  skippedCount: 0,
};

function fixture() {
  const repository: ImportRepository = {
    findUserId: vi.fn(async (uid) => (uid === 'missing' ? null : 'owner-a')),
    prepare: vi.fn(async () => structuredClone(value)),
    list: vi.fn(async () => [structuredClone(value)]),
    find: vi.fn(async () => structuredClone(value)),
    merge: vi.fn(
      async (
        _owner: string,
        _id: string,
        updates: {
          index: number;
          item: ImportItem;
        }[],
      ) => ({
        ...structuredClone(value),
        items: updates.map((update) => update.item),
      }),
    ),
    confirm: vi.fn(async () => structuredClone(value)),
    discard: vi.fn(async () => {}),
  };
  const provider: MusicProvider = {
    search: vi.fn(),
    getTrack: vi.fn(async (sourceId) => ({
      id: 'youtube:' + sourceId,
      source: 'youtube' as const,
      sourceId,
      title: 'Canción',
      artistName: 'Artista',
      durationSeconds: 200,
      thumbnailUrl: null,
    })),
    resolvePlayback: vi.fn(),
  };
  const verifier = {
    async verify(token: string) {
      if (token === 'invalid') throw new InvalidTokenError();
      return {
        firebaseUid: token,
        provider: token === 'password' ? 'password' : 'google.com',
      };
    },
  };
  return {
    repository,
    provider,
    app: createApp({
      tokenVerifier: verifier,
      musicProvider: provider,
      importRepository: repository,
    }),
  };
}

describe('importación YouTube Music', () => {
  it('exige Firebase Google y rechaza tokens inválidos', async () => {
    const { app, repository } = fixture();
    expect((await request(app).get(path)).status).toBe(401);
    expect(
      (await request(app).get(path).auth('invalid', { type: 'bearer' })).status,
    ).toBe(401);
    expect(
      (await request(app).get(path).auth('password', { type: 'bearer' }))
        .status,
    ).toBe(403);
    expect(
      (await request(app).get(path).auth('missing', { type: 'bearer' })).status,
    ).toBe(404);
    expect(repository.list).not.toHaveBeenCalled();
  });

  it('valida límites, IDs y campos inesperados sin aceptar propietario', async () => {
    const { app, repository } = fixture();
    for (const body of [
      { id, name: 'Lista', sourceIds: ['bad'] },
      { id, name: 'Lista', sourceIds: Array(501).fill('abcdefghijk') },
      { id, name: 'Lista', sourceIds: ['abcdefghijk'], userId: 'otro' },
      { id, name: ' \n ', sourceIds: ['abcdefghijk'] },
    ]) {
      expect(
        (await request(app).post(path).auth('a', { type: 'bearer' }).send(body))
          .status,
      ).toBe(400);
    }
    expect(repository.prepare).not.toHaveBeenCalled();
    const result = await request(app)
      .post(path)
      .auth('a', { type: 'bearer' })
      .send({
        id,
        name: ' Lista ',
        sourceIds: ['abcdefghijk'],
      });
    expect(result.status).toBe(200);
    expect(result.headers['cache-control']).toBe('no-store');
    expect(result.body.userId).toBeUndefined();
    expect(repository.prepare).toHaveBeenCalledWith(
      'owner-a',
      expect.objectContaining({ name: 'Lista' }),
      expect.stringMatching(/^[a-f0-9]{64}$/),
    );
  });

  it('admite nombres Unicode de 150 caracteres y rechaza nombres más largos', async () => {
    const { app, repository } = fixture();
    const body = { id, name: '🎧'.repeat(150), sourceIds: ['abcdefghijk'] };
    expect(
      (await request(app).post(path).auth('a', { type: 'bearer' }).send(body))
        .status,
    ).toBe(200);
    expect(
      (
        await request(app)
          .post(path)
          .auth('a', { type: 'bearer' })
          .send({ ...body, name: '🎧'.repeat(151) })
      ).status,
    ).toBe(400);
    expect(repository.prepare).toHaveBeenCalledOnce();
  });

  it('mantiene lotes de dos y diferencia ausencia de un fallo temporal', async () => {
    const { app, provider, repository } = fixture();
    vi.mocked(provider.getTrack)
      .mockResolvedValueOnce(null)
      .mockRejectedValueOnce(new Error('offline'));
    const result = await request(app)
      .post(path + '/' + id + '/resolve')
      .auth('a', { type: 'bearer' })
      .send({ indices: [0, 1] });
    expect(result.status).toBe(200);
    expect(
      result.body.items.map((item: { status: string }) => item.status),
    ).toEqual(['unavailable', 'retry']);
    expect(repository.merge).toHaveBeenCalledOnce();
    for (const indices of [[0, 0], [0, 1, 2], [2], [-1]]) {
      expect(
        (
          await request(app)
            .post(path + '/' + id + '/resolve')
            .auth('a', { type: 'bearer' })
            .send({ indices })
        ).status,
      ).toBe(400);
    }
  });

  it('permite reintentar y confirmar con el contrato de errores habitual', async () => {
    const { app, repository } = fixture();
    const ready = {
      ...value,
      items: [{ sourceId: 'abcdefghijk', status: 'retry' as const }],
    };
    vi.mocked(repository.find).mockResolvedValue(ready);
    const result = await request(app)
      .post(path + '/' + id + '/resolve')
      .auth('a', { type: 'bearer' })
      .send({ indices: [0] });
    expect(result.body.items[0].status).toBe('ready');
    expect(
      (
        await request(app)
          .post(path + '/' + id + '/confirm')
          .auth('a', { type: 'bearer' })
          .send({ userId: 'otro' })
      ).status,
    ).toBe(400);
    expect(
      (
        await request(app)
          .post(path + '/' + id + '/confirm')
          .auth('a', { type: 'bearer' })
          .send({})
      ).status,
    ).toBe(200);
  });

  it('rechaza borradores caducados y acceso a IDs inexistentes', async () => {
    const { app, repository } = fixture();
    vi.mocked(repository.find).mockResolvedValue({
      ...value,
      expiresAt: new Date(0),
    });
    expect(
      (
        await request(app)
          .get(path + '/' + id)
          .auth('a', { type: 'bearer' })
      ).status,
    ).toBe(404);
    vi.mocked(repository.find).mockResolvedValue(null);
    expect(
      (
        await request(app)
          .post(path + '/' + id + '/resolve')
          .auth('a', { type: 'bearer' })
          .send({ indices: [0] })
      ).status,
    ).toBe(404);
  });

  it('acota concurrencia de importación y no resuelve pistas ya listas', async () => {
    const { repository, provider } = fixture();
    let finish!: () => void;
    const wait = new Promise<void>((resolve) => {
      finish = resolve;
    });
    vi.mocked(provider.getTrack).mockImplementation(async () => {
      await wait;
      return null;
    });
    const service = new ImportService(repository, new CatalogService(provider));
    const identity = { firebaseUid: 'a', provider: 'google.com' };
    const first = service.resolve(identity, id, [0]);
    const second = service.resolve(identity, id, [1]);
    await vi.waitFor(() => expect(provider.getTrack).toHaveBeenCalledTimes(2));
    await expect(service.resolve(identity, id, [0])).rejects.toMatchObject({
      status: 429,
    });
    finish();
    await Promise.all([first, second]);
    vi.mocked(repository.find).mockResolvedValue({
      ...value,
      confirmedAt: new Date(),
    });
    await service.resolve(identity, id, [0]);
    expect(provider.getTrack).toHaveBeenCalledTimes(2);
  });
});
