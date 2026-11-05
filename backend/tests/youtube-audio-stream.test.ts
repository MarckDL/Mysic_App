import { describe, expect, it, vi } from 'vitest';
import {
  InvalidAudioRangeError,
  YoutubeAudioStream,
  selectAudioRange,
} from '../src/infrastructure/music/youtube-audio-stream.js';
import type {
  PlaybackSourceResolver,
  ResolvedPlaybackSource,
} from '../src/modules/playback/domain/playback-source-resolver.js';

const sourceId = 'aqz-KE-bpKQ';
const source: ResolvedPlaybackSource = {
  sourceId,
  client: 'VISIONOS',
  itag: 140,
  privateUrl: 'https://media.googlevideo.com/videoplayback?private=1',
  mimeType: 'audio/mp4; codecs="mp4a.40.2"',
  contentLength: 10,
  durationMs: 1_000,
  expiresAtMs: Date.now() + 120_000,
};

function fakeResolver() {
  return {
    warm: vi.fn(async () => {}),
    resolve: vi.fn(async () => source),
    invalidate: vi.fn(),
    close: vi.fn(async () => {}),
  } satisfies PlaybackSourceResolver;
}

async function read(stream: NodeJS.ReadableStream) {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks).toString();
}

describe('proxy de rangos de YouTube', () => {
  it('normaliza rangos abiertos, acotados y sufijos', () => {
    expect(selectAudioRange(undefined, 10)).toMatchObject({
      start: 0,
      end: 9,
      partial: false,
    });
    expect(selectAudioRange('bytes=2-', 10)).toMatchObject({
      start: 2,
      end: 9,
      header: 'bytes=2-9',
    });
    expect(selectAudioRange('bytes=2-99', 10).end).toBe(9);
    expect(selectAudioRange('bytes=-3', 10)).toMatchObject({
      start: 7,
      end: 9,
    });
    for (const invalid of [
      'bytes=-0',
      'bytes=10-',
      'bytes=5-2',
      'bytes=0-1,3-4',
      'items=0-1',
      'bytes=-',
    ])
      expect(() => selectAudioRange(invalid, 10)).toThrow(
        InvalidAudioRangeError,
      );
  });

  it('transmite un rango sin cargar el archivo completo', async () => {
    const resolver = fakeResolver();
    const metrics = vi.fn();
    const fetcher = vi.fn(async (_url: URL, init?: RequestInit) => {
      expect(new Headers(init?.headers).get('range')).toBe('bytes=2-5');
      return new Response('2345', {
        status: 206,
        headers: {
          'content-length': '4',
          'content-range': 'bytes 2-5/10',
        },
      });
    });
    const result = await new YoutubeAudioStream(
      resolver,
      fetcher as typeof fetch,
      metrics,
    ).open(sourceId, new AbortController().signal, 'bytes=2-5');
    expect(result.status).toBe(206);
    expect(result.contentLength).toBe(4);
    expect(result.contentRange).toBe('bytes 2-5/10');
    expect(await read(result.stream)).toBe('2345');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(metrics).toHaveBeenCalledOnce();
    expect(metrics).toHaveBeenCalledWith(
      expect.objectContaining({
        stage: 'first-byte',
        retry: false,
        success: true,
      }),
    );
  });

  it('re-resuelve una sola vez ante 403 y conserva el rango', async () => {
    const resolver = fakeResolver();
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 403 }))
      .mockResolvedValueOnce(
        new Response('012', {
          status: 206,
          headers: {
            'content-length': '3',
            'content-range': 'bytes 0-2/10',
          },
        }),
      );
    const result = await new YoutubeAudioStream(
      resolver,
      fetcher as typeof fetch,
    ).open(sourceId, new AbortController().signal, 'bytes=0-2');
    expect(await read(result.stream)).toBe('012');
    expect(resolver.invalidate).toHaveBeenCalledOnce();
    expect(resolver.resolve).toHaveBeenCalledTimes(2);
    expect(fetcher).toHaveBeenCalledTimes(2);
    for (const call of fetcher.mock.calls)
      expect(new Headers(call[1]?.headers).get('range')).toBe('bytes=0-2');
  });

  it('rechaza respuestas parciales inconsistentes o demasiado grandes', async () => {
    const resolver = fakeResolver();
    const ignoredRange = new YoutubeAudioStream(
      resolver,
      vi.fn(
        async () => new Response('0123456789', { status: 200 }),
      ) as typeof fetch,
    );
    await expect(
      ignoredRange.open(sourceId, new AbortController().signal, 'bytes=0-2'),
    ).rejects.toThrow();

    const oversized = new YoutubeAudioStream(
      resolver,
      vi.fn(
        async () =>
          new Response('0123', {
            status: 206,
            headers: {
              'content-length': '3',
              'content-range': 'bytes 0-2/10',
            },
          }),
      ) as typeof fetch,
    );
    const result = await oversized.open(
      sourceId,
      new AbortController().signal,
      'bytes=0-2',
    );
    await expect(read(result.stream)).rejects.toThrow();
  });

  it('no sigue redirecciones fuera del CDN permitido', async () => {
    const proxy = new YoutubeAudioStream(
      fakeResolver(),
      vi.fn(
        async () =>
          new Response(null, {
            status: 302,
            headers: { location: 'https://example.test/private' },
          }),
      ) as typeof fetch,
    );
    await expect(
      proxy.open(sourceId, new AbortController().signal, 'bytes=0-2'),
    ).rejects.toThrow();
  });
});
