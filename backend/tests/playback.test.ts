import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { AuthorizedDemoProvider } from '../src/infrastructure/music/authorized-demo-provider.js';
import { YoutubeProvider } from '../src/infrastructure/music/youtube-provider.js';
import type { MusicProvider } from '../src/modules/catalog/domain/music-provider.js';
import {
  InvalidTokenError,
  type TokenVerifier,
} from '../src/modules/auth/domain/token-verifier.js';
import { PlaybackService } from '../src/modules/playback/application/playback-service.js';
import {
  demoAssetPath,
  demoSourceId,
} from '../src/modules/playback/domain/playback-result.js';

const path = '/api/v1/playback/resolve';
const body = { source: 'demo', sourceId: demoSourceId };
const verifier: TokenVerifier = {
  async verify(token) {
    if (token === 'bad') throw new InvalidTokenError();
    return {
      firebaseUid: token,
      provider: token === 'other' ? 'password' : 'google.com',
    };
  },
};
function fakeProvider(
  resolvePlayback: MusicProvider['resolvePlayback'],
): MusicProvider {
  return {
    search: async () => [],
    getTrack: async () => null,
    resolvePlayback,
  };
}
afterEach(() => vi.useRealTimers());

describe('resolución de audio autorizado', () => {
  it('resuelve solo el asset demo registrado, sin URL ni tokens', async () => {
    const app = createApp({ tokenVerifier: verifier });
    const response = await request(app)
      .post(path)
      .auth('a', { type: 'bearer' })
      .send(body);
    expect(response.status).toBe(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body).toEqual({
      mode: 'direct',
      delivery: 'asset',
      assetPath: demoAssetPath,
      contentType: 'audio/wav',
      durationSeconds: 8,
    });
    expect(response.body.url).toBeUndefined();
    const unknown = await request(app)
      .post(path)
      .auth('a', { type: 'bearer' })
      .send({ ...body, sourceId: 'unknown' });
    expect(unknown.status).toBe(200);
    expect(unknown.body.mode).toBe('unavailable');
  });
  it('informa indisponibilidad YouTube sin inicializar el SDK ni extraer audio', async () => {
    const factory = vi.fn();
    const music = new YoutubeProvider(factory);
    const app = createApp({ tokenVerifier: verifier, musicProvider: music });
    const response = await request(app)
      .post(path)
      .auth('a', { type: 'bearer' })
      .send({ source: 'youtube', sourceId: 'abcdefghijk' });
    expect(response.status).toBe(200);
    expect(response.body.mode).toBe('unavailable');
    expect(response.body.reason).toContain('autorizada');
    expect(factory).not.toHaveBeenCalled();
  });
  it.each([null, 'bad', 'other'])(
    'requiere Google y token válido: %s',
    async (token) => {
      const app = createApp({ tokenVerifier: verifier });
      const req = request(app).post(path).send(body);
      if (token) req.auth(token, { type: 'bearer' });
      expect((await req).status).toBe(token === 'other' ? 403 : 401);
    },
  );
  it.each([
    {},
    { ...body, url: 'https://evil.test/audio' },
    { ...body, user_id: 'b' },
    { source: 'youtube', sourceId: 'https://example.test' },
    { source: 'external', sourceId: demoSourceId },
    { ...body, sourceId: ['a'] },
  ])('rechaza campos/identidades/fuentes arbitrarias', async (payload) => {
    const response = await request(createApp({ tokenVerifier: verifier }))
      .post(path)
      .auth('a', { type: 'bearer' })
      .send(payload);
    expect(response.status).toBe(400);
  });
  it('no devuelve errores internos ni confunde fallo con unavailable válido', async () => {
    const service = new PlaybackService(
      new Map([
        [
          'demo',
          fakeProvider(async () => {
            throw new Error('private token');
          }),
        ],
      ]),
    );
    const response = await request(
      createApp({ tokenVerifier: verifier, playbackService: service }),
    )
      .post(path)
      .auth('a', { type: 'bearer' })
      .send(body);
    expect(response.status).toBe(503);
    expect(response.text).not.toContain('private token');
  });
  it('bloquea rutas de asset no registradas e integración embebida no habilitada', async () => {
    const wrong = fakeProvider(async () => ({
      mode: 'direct',
      delivery: 'asset',
      assetPath: '../../private',
      contentType: 'audio/wav',
      durationSeconds: 8,
    }));
    await expect(
      new PlaybackService(new Map([['demo', wrong]])).resolve(
        'demo',
        demoSourceId,
      ),
    ).rejects.toThrow();
    const embedded = fakeProvider(async () => ({
      mode: 'embedded',
      url: 'https://example.test',
    }));
    expect(
      (
        await new PlaybackService(new Map([['demo', embedded]])).resolve(
          'demo',
          demoSourceId,
        )
      ).mode,
    ).toBe('unavailable');
  });
  it('aborta resolución lenta y no mantiene recursos temporales', async () => {
    vi.useFakeTimers();
    let signal: AbortSignal | undefined;
    const slow = fakeProvider(async (_id, currentSignal) => {
      signal = currentSignal;
      return new Promise(() => {});
    });
    const result = expect(
      new PlaybackService(new Map([['demo', slow]]), 10).resolve(
        'demo',
        demoSourceId,
      ),
    ).rejects.toThrow();
    await vi.advanceTimersByTimeAsync(10);
    await result;
    expect(signal?.aborted).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });
  it('limita por UID sin afectar otra cuenta', async () => {
    const app = createApp({ tokenVerifier: verifier });
    for (let i = 0; i < 30; i++)
      expect(
        (await request(app).post(path).auth('a', { type: 'bearer' }).send(body))
          .status,
      ).toBe(200);
    const limited = await request(app)
      .post(path)
      .auth('a', { type: 'bearer' })
      .send(body);
    expect(limited.status).toBe(429);
    expect(limited.headers['retry-after']).toBeDefined();
    expect(
      (await request(app).post(path).auth('b', { type: 'bearer' }).send(body))
        .status,
    ).toBe(200);
  });
  it('el proveedor demo solo referencia su pista registrada', async () => {
    const demo = new AuthorizedDemoProvider();
    expect(await demo.search()).toEqual([]);
    expect((await demo.getTrack(demoSourceId))?.source).toBe('demo');
    expect(await demo.getTrack('other')).toBeNull();
  });
});
