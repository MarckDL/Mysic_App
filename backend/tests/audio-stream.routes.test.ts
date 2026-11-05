import request from 'supertest';
import { Readable, PassThrough } from 'node:stream';
import { once } from 'node:events';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type { AudioStreamTransport } from '../src/infrastructure/music/youtube-audio-stream.js';
import { selectAudioRange } from '../src/infrastructure/music/youtube-audio-stream.js';
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
  open: AudioStreamTransport['open'] = async (_id, _signal, range) => {
    const fixture = Buffer.from('audio-fixture');
    const selected = selectAudioRange(range, fixture.length);
    const body = fixture.subarray(selected.start, selected.end + 1);
    return {
      stream: Readable.from([body]),
      status: selected.partial ? 206 : 200,
      contentType: 'audio/mp4',
      contentLength: body.length,
      ...(selected.partial
        ? {
            contentRange: `bytes ${selected.start}-${selected.end}/${fixture.length}`,
          }
        : {}),
    };
  },
) {
  const transport = { open: vi.fn(open) };
  const completeTransport = {
    ...transport,
    warm: vi.fn<AudioStreamTransport['warm']>(async () => {}),
    prefetch: vi.fn<AudioStreamTransport['prefetch']>(async () => {}),
    close: vi.fn<AudioStreamTransport['close']>(async () => {}),
  };
  return {
    app: createApp({
      tokenVerifier: verifier,
      audioStreamTransport: completeTransport,
    }),
    transport: completeTransport,
  };
}
describe('audio nativo autenticado', () => {
  it('precarga solo la resolución autenticada de la siguiente pista', async () => {
    const { app, transport } = setup();
    const response = await request(app)
      .post('/api/v1/playback/prefetch/aqz-KE-bpKQ')
      .auth('a', { type: 'bearer' });
    expect(response.status).toBe(204);
    expect(transport.prefetch).toHaveBeenCalledOnce();
    expect(transport.open).not.toHaveBeenCalled();
    expect(transport.prefetch.mock.calls[0]?.[0]).toBe('aqz-KE-bpKQ');
    expect(transport.prefetch.mock.calls[0]?.[1].aborted).toBe(false);
    expect(
      (
        await request(app).post(
          '/api/v1/playback/prefetch/aqz-KE-bpKQ?url=evil',
        )
      ).status,
    ).toBe(401);
  });

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
    expect(response.headers['accept-ranges']).toBe('bytes');
    expect(response.headers['content-length']).toBe('13');
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
  it('acepta rangos iniciales, intermedios y finales', async () => {
    const { app, transport } = setup();
    const initial = await request(app)
      .get(path)
      .auth('a', { type: 'bearer' })
      .set('Range', 'bytes=0-3');
    expect(initial.status).toBe(206);
    expect(initial.headers['content-range']).toBe('bytes 0-3/13');
    expect(initial.body.toString()).toBe('audi');
    const middle = await request(app)
      .get(path)
      .auth('a', { type: 'bearer' })
      .set('Range', 'bytes=6-9');
    expect(middle.status).toBe(206);
    expect(middle.body.toString()).toBe('fixt');
    const suffix = await request(app)
      .get(path)
      .auth('a', { type: 'bearer' })
      .set('Range', 'bytes=-4');
    expect(suffix.status).toBe(206);
    expect(suffix.headers['content-range']).toBe('bytes 9-12/13');
    expect(suffix.body.toString()).toBe('ture');
    const invalid = await request(app)
      .get(path)
      .auth('a', { type: 'bearer' })
      .set('Range', 'bytes=100-');
    expect(invalid.status).toBe(416);
    expect(invalid.headers['content-range']).toBe('bytes */13');
    expect(transport.open).toHaveBeenCalledTimes(4);
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
      return {
        stream: audio,
        status: 200,
        contentType: 'audio/mp4',
        contentLength: 100,
      };
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
  it('mantiene controlado un AbortError tardío al desconectarse el cliente', async () => {
    const audio = new PassThrough();
    audio.write('init');
    const { app } = setup(async () => ({
      stream: audio,
      status: 200,
      contentType: 'audio/mp4',
      contentLength: 100,
    }));
    const server = app.listen(0);
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error();
    const abort = new AbortController();
    try {
      const response = await fetch(`http://127.0.0.1:${address.port}${path}`, {
        headers: { Authorization: 'Bearer a' },
        signal: abort.signal,
      });
      expect(response.status).toBe(200);
      abort.abort();
      await vi.waitFor(() => expect(audio.destroyed).toBe(true));

      expect(() =>
        audio.emit(
          'error',
          new DOMException('This operation was aborted', 'AbortError'),
        ),
      ).not.toThrow();
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
      return {
        stream: audio,
        status: 200,
        contentType: 'audio/mp4',
        contentLength: 100,
      };
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
