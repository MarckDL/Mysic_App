import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import express from 'express';
import { createApp } from '../src/app.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';
import {
  createPreviewMusicProvider,
  PreviewMusicProvider,
} from '../src/modules/integrations/youtube-music/preview-provider.js';
import {
  youtubeMusicRoot as root,
  youtubeMusicRouter,
} from '../src/modules/integrations/youtube-music/routes.js';
import { YouTubeMusicService } from '../src/modules/integrations/youtube-music/service.js';
import type { MusicPageRequest } from '../src/modules/integrations/youtube-music/provider.js';

const verifier = {
  async verify(token: string) {
    if (!['a', 'b', 'other'].includes(token)) throw new InvalidTokenError();
    return { firebaseUid: token, provider: 'google.com' };
  },
};

function mount(preview = new PreviewMusicProvider('a', 'b'), now = Date.now) {
  const app = express();
  app.use(express.json());
  app.use(
    root,
    youtubeMusicRouter(verifier, new YouTubeMusicService(preview, now)),
  );
  return request(app);
}

function signal() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

type Agent = ReturnType<typeof mount>;
const connection = root + '/connection';
const pages = (gen: string, surface: string) =>
  root + '/connections/' + gen + '/pages/' + surface;
const listenPath = (gen: string, id: string) =>
  root + '/connections/' + gen + '/listens/' + id;
async function link(
  api: Agent,
  token: string,
  accountId: string,
  generation: string | null = null,
) {
  const result = await api
    .post(connection)
    .auth(token, { type: 'bearer' })
    .send({
      accountId,
      generation,
    })
    .expect(200);
  return result.body.generation as string;
}

describe('modo YouTube Music con proveedor de simulación', () => {
  it('exige sesión y deja el proveedor real deshabilitado por defecto', async () => {
    const app = request(
      createApp({
        tokenVerifier: verifier,
        youtubeMusicProvider: null,
        youtubeLinkService: undefined,
      }),
    );
    await app.get(connection).expect(401);
    await app.get(connection).auth('invalid', { type: 'bearer' }).expect(401);
    const result = await app
      .get(connection)
      .auth('a', { type: 'bearer' })
      .expect(200);
    expect(result.headers['cache-control']).toBe('private, no-store');
    expect(result.body).toEqual({
      status: 'unavailable',
      account: null,
      accounts: [],
      provider: null,
      generation: null,
      capabilities: [],
    });
    expect(() =>
      createPreviewMusicProvider({
        NODE_ENV: 'production',
        YOUTUBE_MUSIC_PREVIEW_ENABLED: 'true',
      }),
    ).toThrow('isolated test backend');
  });

  it('separa Inicio, búsqueda, playlists privadas, cursores y generaciones entre cuentas', async () => {
    const api = mount();
    const aAuth = { type: 'bearer' } as const;
    await api
      .post(connection)
      .auth('other', aAuth)
      .send({ accountId: 'preview-a', generation: null })
      .expect(503);
    await api
      .post(connection)
      .auth('b', aAuth)
      .send({ accountId: 'preview-a', generation: null })
      .expect(404);
    const a = await link(api, 'a', 'preview-a');
    const b = await link(api, 'b', 'preview-b');
    const homeA = await api.get(pages(a, 'home')).auth('a', aAuth).expect(200);
    const homeB = await api.get(pages(b, 'home')).auth('b', aAuth).expect(200);
    expect(homeA.body.items[0].title).toBe('Ruta de Piura');
    expect(homeB.body.items[0].title).toBe('Lluvia de Misiones');
    const playlist = 'playlist/preview-a-private';
    const first = await api
      .get(pages(a, playlist))
      .query({ limit: 2 })
      .auth('a', aAuth)
      .expect(200);
    expect(first.body.playlist).toMatchObject({
      title: 'Playlist privada · Cuenta A',
      private: true,
    });
    expect(
      first.body.items.map((item: { title: string }) => item.title),
    ).toEqual(['Brisa de Piura', 'Cielo de Piura']);
    expect(first.body.excludedCount).toBe(2);
    const cursor = first.body.nextCursor;
    const next = await api
      .get(pages(a, playlist))
      .query({ cursor })
      .auth('a', aAuth)
      .expect(200);
    expect(next.body.items[0].title).toBe('Ruta de Piura');
    expect(next.body.nextCursor).toBeNull();
    await api.get(pages(a, playlist)).auth('b', aAuth).expect(409);
    await api.get(pages(b, playlist)).auth('b', aAuth).expect(404);
    await api
      .get(pages(b, 'songs'))
      .query({ cursor })
      .auth('b', aAuth)
      .expect(409);
    await api
      .get(pages(a, 'songs'))
      .query({ cursor })
      .auth('a', aAuth)
      .expect(409);
    const search = await api
      .get(pages(a, 'search'))
      .query({ q: 'piura', limit: 1 })
      .auth('a', aAuth)
      .expect(200);
    expect(search.body.items[0].title).toContain('Piura');
    await api
      .get(pages(a, 'search'))
      .query({ q: 'brisa', cursor: search.body.nextCursor })
      .auth('a', aAuth)
      .expect(409);
    const a2 = await link(api, 'a', 'preview-a2', a);
    await api.get(pages(a, 'home')).auth('a', aAuth).expect(409);
    await api
      .get(pages(a2, 'songs'))
      .query({ cursor })
      .auth('a', aAuth)
      .expect(409);
    await api
      .delete(root + '/connections/' + a)
      .auth('a', aAuth)
      .expect(409);
    await api
      .delete(root + '/connections/' + a2)
      .auth('a', aAuth)
      .expect(204);
    await api.get(pages(a2, 'home')).auth('a', aAuth).expect(409);
    const state = await api.get(connection).auth('a', aAuth).expect(200);
    expect(state.body.status).toBe('unlinked');
  });

  it('registra una escucha por reproducción, permite comprobar reintentos y respeta la pausa', async () => {
    const api = mount();
    const a = await link(api, 'a', 'preview-a');
    const b = await link(api, 'b', 'preview-b');
    const auth = { type: 'bearer' } as const;
    const id = randomUUID();
    const path = listenPath(a, id);
    const payload = { trackId: 'preview-a-track-1', listenedMs: 4600 };
    await api
      .put(path)
      .auth('a', auth)
      .send({ ...payload, listenedMs: 100 })
      .expect(400);
    const missing = await api.get(path).auth('a', auth).expect(200);
    expect(missing.body.listen).toBeNull();
    await Promise.all([
      api.put(path).auth('a', auth).send(payload).expect(204),
      api.put(path).auth('a', auth).send(payload).expect(204),
    ]);
    const recorded = await api.get(path).auth('a', auth).expect(200);
    expect(recorded.body.listen).toEqual(payload);
    await api
      .put(path)
      .auth('a', auth)
      .send({ ...payload, trackId: 'preview-a-track-2' })
      .expect(409);
    const aHistory = await api
      .get(pages(a, 'history'))
      .auth('a', auth)
      .expect(200);
    expect(aHistory.body.items).toHaveLength(1);
    expect(aHistory.body.items[0].entryId).toBe(id);
    await api.put(listenPath(b, id)).auth('b', auth).send(payload).expect(404);
    const bHistory = await api
      .get(pages(b, 'history'))
      .auth('b', auth)
      .expect(200);
    expect(bHistory.body.items).toEqual([]);
    const paused = await link(api, 'a', 'preview-a2', a);
    await api
      .put(listenPath(paused, id))
      .auth('a', auth)
      .send({ ...payload, trackId: 'preview-a2-track-1' })
      .expect(204);
    const pausedHistory = await api
      .get(pages(paused, 'history'))
      .auth('a', auth)
      .expect(200);
    expect(pausedHistory.body.items).toEqual([]);
  });

  it('descarta lecturas en vuelo y ofrece reconexión al caducar', async () => {
    const started = signal();
    const resume = signal();
    class DelayedProvider extends PreviewMusicProvider {
      override async read(
        uid: string,
        account: string,
        page: MusicPageRequest,
      ) {
        started.resolve();
        await resume.promise;
        return super.read(uid, account, page);
      }
    }
    let now = 0;
    const api = mount(new DelayedProvider('a', 'b'), () => now);
    const auth = { type: 'bearer' } as const;
    const generation = await link(api, 'a', 'preview-a');
    const privateRead = api
      .get(pages(generation, 'home'))
      .auth('a', auth)
      .then((r) => r);
    await started.promise;
    const next = await link(api, 'a', 'preview-a2', generation);
    resume.resolve();
    const result = await privateRead;
    expect(result.status).toBe(409);
    expect(result.body.error.code).toBe('MUSIC_LINK_CHANGED');
    expect(result.body.items).toBeUndefined();
    now += 8 * 60 * 60_000;
    const expired = await api
      .get(pages(next, 'home'))
      .auth('a', auth)
      .expect(409);
    expect(expired.body.error.code).toBe('MUSIC_RECONNECT');
    const state = await api.get(connection).auth('a', auth).expect(200);
    expect(state.body.status).toBe('expired');
    expect(await link(api, 'a', 'preview-a2', next)).not.toBe(next);
  });

  it('descarta una confirmación antigua aunque la generación haya vuelto a estar vacía', async () => {
    const started = signal();
    const resume = signal();
    class DelayedConfirmation extends PreviewMusicProvider {
      override async confirm(uid: string, accountId: string) {
        if (accountId === 'preview-a') {
          started.resolve();
          await resume.promise;
        }
        return super.confirm(uid, accountId);
      }
    }
    const api = mount(new DelayedConfirmation('a', 'b'));
    const auth = { type: 'bearer' } as const;
    const first = api
      .post(connection)
      .auth('a', auth)
      .send({
        accountId: 'preview-a',
        generation: null,
      })
      .then((r) => r);
    await started.promise;
    const alternate = await link(api, 'a', 'preview-a2');
    await api
      .delete(root + '/connections/' + alternate)
      .auth('a', auth)
      .expect(204);
    resume.resolve();
    expect((await first).body.error.code).toBe('MUSIC_LINK_CHANGED');
  });
});
