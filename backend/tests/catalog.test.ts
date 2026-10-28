import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { LruCache } from '../src/infrastructure/cache/lru-cache.js';
import { CatalogService } from '../src/modules/catalog/application/catalog-service.js';
import { CatalogLimiter } from '../src/modules/catalog/application/catalog-limiter.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';
import {
  ProviderTimeoutError,
  ProviderUnavailableError,
  type MusicProvider,
  type Track,
} from '../src/modules/catalog/domain/music-provider.js';

const track: Track = {
  id: 'youtube:abcdefghijk',
  source: 'youtube',
  sourceId: 'abcdefghijk',
  title: 'Song',
  artistName: 'Artist',
  durationSeconds: 123,
  thumbnailUrl: null,
};
function provider() {
  return {
    search: vi.fn<MusicProvider['search']>().mockResolvedValue([track]),
    getTrack: vi.fn<MusicProvider['getTrack']>().mockResolvedValue(track),
    resolvePlayback: vi
      .fn<MusicProvider['resolvePlayback']>()
      .mockResolvedValue({ mode: 'unavailable', reason: 'No source' }),
  };
}
function fixture(music = provider()) {
  const app = createApp({
    musicProvider: music,
    tokenVerifier: {
      async verify(token) {
        if (token === 'invalid') throw new InvalidTokenError();
        return {
          firebaseUid: token,
          provider: token === 'other' ? 'password' : 'google.com',
        };
      },
    },
  });
  return { app, music };
}
afterEach(() => vi.useRealTimers());

describe('caché de catálogo', () => {
  it('expulsa por LRU y vence desde la escritura, sin extender el TTL al leer', () => {
    let now = 0;
    const cache = new LruCache<number>(2, 100, () => now);
    cache.set('a', 1);
    cache.set('b', 2);
    expect(cache.get('a')).toBe(1);
    cache.set('c', 3);
    expect(cache.get('b')).toBeUndefined();
    now = 99;
    expect(cache.get('a')).toBe(1);
    now = 100;
    expect(cache.get('a')).toBeUndefined();
  });
  it('coalesce solicitudes y evita mutar las respuestas cacheadas', async () => {
    const music = provider();
    const service = new CatalogService(music);
    const [a, b] = await Promise.all([
      service.search('query'),
      service.search('query'),
    ]);
    expect(music.search).toHaveBeenCalledTimes(1);
    a[0]!.title = 'changed';
    expect(b[0]?.title).toBe('Song');
    expect((await service.search('query'))[0]?.title).toBe('Song');
  });
  it('separa búsqueda y detalle, almacena vacíos y expira cada TTL', async () => {
    let now = 0;
    const music = provider();
    music.search.mockResolvedValue([]);
    const service = new CatalogService(music, { now: () => now });
    await service.search('q');
    await service.search('q');
    await service.getTrack('abcdefghijk');
    expect(music.search).toHaveBeenCalledTimes(1);
    now = 600_000;
    await service.search('q');
    await service.getTrack('abcdefghijk');
    expect(music.search).toHaveBeenCalledTimes(2);
    expect(music.getTrack).toHaveBeenCalledTimes(1);
    now = 3_600_000;
    await service.getTrack('abcdefghijk');
    expect(music.getTrack).toHaveBeenCalledTimes(2);
  });
  it('no cachea fallos y limpia la petición fallida', async () => {
    const music = provider();
    music.search.mockRejectedValueOnce(new ProviderUnavailableError());
    const service = new CatalogService(music);
    await expect(service.search('q')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
    await expect(service.search('q')).resolves.toEqual([track]);
    expect(music.search).toHaveBeenCalledTimes(2);
  });
  it('aborta por timeout y descarta respuestas tardías', async () => {
    vi.useFakeTimers();
    const music = provider();
    let complete!: (tracks: Track[]) => void;
    music.search.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          complete = resolve;
        }),
    );
    const service = new CatalogService(music, { timeoutMs: 10 });
    const result = expect(service.search('q')).rejects.toBeInstanceOf(
      ProviderTimeoutError,
    );
    await vi.advanceTimersByTimeAsync(10);
    await result;
    expect(music.search.mock.calls[0]?.[1]?.aborted).toBe(true);
    complete([{ ...track, title: 'stale' }]);
    await vi.advanceTimersByTimeAsync(0);
    expect((await service.search('q'))[0]?.title).toBe('Song');
    expect(music.search).toHaveBeenCalledTimes(2);
  });
  it('acota peticiones externas distintas en vuelo', async () => {
    vi.useFakeTimers();
    const music = provider();
    music.search.mockImplementation(() => new Promise(() => {}));
    const service = new CatalogService(music, { maxPending: 1, timeoutMs: 10 });
    const first = expect(service.search('a')).rejects.toBeInstanceOf(
      ProviderTimeoutError,
    );
    await expect(service.search('b')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
    await vi.advanceTimersByTimeAsync(10);
    await first;
  });
});

describe('rutas catálogo autenticadas', () => {
  it.each(['/api/v1/search?q=artist', '/api/v1/tracks/youtube:abcdefghijk'])(
    'protege %s',
    async (path) => {
      const { app, music } = fixture();
      for (const token of [null, 'invalid', 'other']) {
        const req = request(app).get(path);
        if (token) req.auth(token, { type: 'bearer' });
        const response = await req;
        expect(response.status).toBe(token === 'other' ? 403 : 401);
        expect(response.headers['cache-control']).toBe('no-store');
      }
      expect(music.search).not.toHaveBeenCalled();
      expect(music.getTrack).not.toHaveBeenCalled();
    },
  );
  it('devuelve resultados normalizados y cache compartida solo tras autenticar', async () => {
    const { app, music } = fixture();
    const path = '/api/v1/search?q=%20Daft%20%20Punk%20';
    const response = await request(app).get(path).auth('a', { type: 'bearer' });
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ items: [track] });
    expect(music.search.mock.calls[0]?.[0]).toBe('Daft Punk');
    expect(response.headers['cache-control']).toBe('no-store');
    await request(app).get(path).auth('b', { type: 'bearer' });
    expect(music.search).toHaveBeenCalledTimes(1);
    expect((await request(app).get(path)).status).toBe(401);
  });
  it.each([
    '/api/v1/search',
    '/api/v1/search?q=a',
    '/api/v1/search?q=ab&q=cd',
    '/api/v1/search?q=ok&user_id=b',
    '/api/v1/search?q=%0Aab',
    '/api/v1/tracks/invalid',
    '/api/v1/tracks/youtube:abcdefghijk?url=https://evil.test',
  ])('rechaza entrada inválida %s', async (path) => {
    const { app, music } = fixture();
    expect(
      (await request(app).get(path).auth('a', { type: 'bearer' })).status,
    ).toBe(400);
    expect(music.search).not.toHaveBeenCalled();
    expect(music.getTrack).not.toHaveBeenCalled();
  });
  it('devuelve vacío válido, detalle independiente y 404 cuando el proveedor confirma ausencia', async () => {
    const music = provider();
    music.search.mockResolvedValue([]);
    const { app } = fixture(music);
    const empty = await request(app)
      .get('/api/v1/search?q=none')
      .auth('a', { type: 'bearer' });
    expect(empty.body).toEqual({ items: [] });
    const detail = await request(app)
      .get('/api/v1/tracks/youtube:abcdefghijk')
      .auth('a', { type: 'bearer' });
    expect(detail.body).toEqual(track);
    music.getTrack.mockResolvedValue(null);
    expect(
      (
        await request(app)
          .get('/api/v1/tracks/youtube:12345678901')
          .auth('a', { type: 'bearer' })
      ).status,
    ).toBe(404);
  });
  it.each([
    [new Error('private-provider-data'), 503],
    [new ProviderTimeoutError(), 504],
  ] as const)(
    'controla errores externos sin revelar detalles',
    async (error, status) => {
      const music = provider();
      music.search.mockRejectedValue(error);
      const { app } = fixture(music);
      const response = await request(app)
        .get('/api/v1/search?q=artist')
        .auth('a', { type: 'bearer' });
      expect(response.status).toBe(status);
      expect(response.text).not.toContain('private-provider-data');
    },
  );
  it('limita por cuenta incluso en cache hits y renueva la ventana', async () => {
    let now = 0;
    const music = provider();
    const app = createApp({
      musicProvider: music,
      catalogLimiter: new CatalogLimiter(() => now, 1),
      tokenVerifier: {
        verify: async (uid) => ({ firebaseUid: uid, provider: 'google.com' }),
      },
    });
    const search = (uid: string) =>
      request(app).get('/api/v1/search?q=artist').auth(uid, { type: 'bearer' });
    expect((await search('a')).status).toBe(200);
    const limited = await search('a');
    expect(limited.status).toBe(429);
    expect(limited.headers['retry-after']).toBe('60');
    expect((await search('b')).status).toBe(200);
    now = 60_000;
    expect((await search('a')).status).toBe(200);
    expect(music.search).toHaveBeenCalledTimes(1);
  });
});
