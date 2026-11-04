import request from 'supertest';
import { Readable, PassThrough } from 'node:stream';
import { once } from 'node:events';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type { AudioStreamTransport } from '../src/infrastructure/music/youtube-audio-stream.js';
import {
  InvalidTokenError,
  type TokenVerifier,
} from '../src/modules/auth/domain/token-verifier.js';
const verifier: TokenVerifier = {
  async verify(token) {
    if (token === 'bad') throw new InvalidTokenError();
    return {
      firebaseUid: token,
      provider: token === 'other' ? 'password' : 'google.com',
    };
  },
};
const path = '/api/v1/playback/audio/aqz-KE-bpKQ';
function setup(
  open: AudioStreamTransport['open'] = async () =>
    Readable.from([Buffer.from('audio-fixture')]),
) {
  const transport = { open: vi.fn(open) };
  return {
    app: createApp({
      tokenVerifier: verifier,
      audioStreamTransport: transport,
    }),
    transport,
  };
}
describe('audio nativo autenticado', () => {
  it.each([null, 'bad', 'other'])(
    'rechaza sesión %s antes de consultar el proveedor',
    async (token) => {
      const { app, transport } = setup();
      const req = request(app).get(path);
      if (token) req.auth(token, { type: 'bearer' });
      expect((await req).status).toBe(token === 'other' ? 403 : 401);
      expect(transport.open).not.toHaveBeenCalled();
    },
  );
  it('envía el ID exacto, solo audio, sin URL de proveedor ni credenciales', async () => {
    const { app, transport } = setup();
    const response = await request(app).get(path).auth('a', { type: 'bearer' });
    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toBe('audio/mp4');
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.headers['accept-ranges']).toBe('none');
    expect(response.body.toString()).toBe('audio-fixture');
    expect(transport.open.mock.calls[0]?.[0]).toBe('aqz-KE-bpKQ');
    expect(transport.open.mock.calls[0]?.[1].aborted).toBe(true);
  });
  it.each([
    '/api/v1/playback/audio/invalid',
    `${path}?url=https://evil.test`,
    `${path}?user_id=b`,
  ])('rechaza entrada arbitraria: %s', async (url) => {
    const { app, transport } = setup();
    expect(
      (await request(app).get(url).auth('a', { type: 'bearer' })).status,
    ).toBe(400);
    expect(transport.open).not.toHaveBeenCalled();
  });
  it('no finge rangos y acepta inicio nativo', async () => {
    const { app, transport } = setup();
    expect(
      (
        await request(app)
          .get(path)
          .auth('a', { type: 'bearer' })
          .set('Range', 'bytes=100-')
      ).status,
    ).toBe(416);
    expect(transport.open).not.toHaveBeenCalled();
    expect(
      (
        await request(app)
          .get(path)
          .auth('a', { type: 'bearer' })
          .set('Range', 'bytes=0-')
      ).status,
    ).toBe(200);
  });
  it('oculta errores internos antes de iniciar el medio', async () => {
    const { app } = setup(async () => {
      throw new Error('secret URL token');
    });
    const response = await request(app).get(path).auth('a', { type: 'bearer' });
    expect(response.status).toBe(503);
    expect(JSON.stringify(response.body)).not.toContain('secret');
  });
  it('reemplaza el stream previo del mismo UID para anterior/siguiente', async () => {
    const signals: AbortSignal[] = [];
    const { app, transport } = setup(async (_id, signal) => {
      signals.push(signal);
      const audio = new PassThrough();
      audio.write('init');
      return audio;
    });
    const server = app.listen(0);
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error();
    const url = `http://127.0.0.1:${address.port}${path}`;
    const abort = new AbortController();
    try {
      const response = await fetch(url, {
        headers: { Authorization: 'Bearer a' },
        signal: abort.signal,
      });
      expect(response.status).toBe(200);
      const secondAbort = new AbortController();
      const second = await fetch(url, {
        headers: { Authorization: 'Bearer a' },
        signal: secondAbort.signal,
      });
      expect(second.status).toBe(200);
      expect(transport.open).toHaveBeenCalledTimes(2);
      await vi.waitFor(() => expect(signals[0]?.aborted).toBe(true));
      secondAbort.abort();
    } finally {
      abort.abort();
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  });
  it('mantiene el límite global al reemplazar solo por UID', async () => {
    const { app, transport } = setup(async () => {
      const audio = new PassThrough();
      audio.write('init');
      return audio;
    });
    const server = app.listen(0);
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error();
    const url = `http://127.0.0.1:${address.port}${path}`;
    const firstAbort = new AbortController();
    const secondAbort = new AbortController();
    try {
      const first = await fetch(url, {
        headers: { Authorization: 'Bearer a' },
        signal: firstAbort.signal,
      });
      const second = await fetch(url, {
        headers: { Authorization: 'Bearer b' },
        signal: secondAbort.signal,
      });
      expect(first.status).toBe(200);
      expect(second.status).toBe(200);
      expect(
        (await fetch(url, { headers: { Authorization: 'Bearer c' } })).status,
      ).toBe(429);
      expect(transport.open).toHaveBeenCalledTimes(2);
    } finally {
      firstAbort.abort();
      secondAbort.abort();
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  });
});
