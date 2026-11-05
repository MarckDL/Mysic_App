import { Readable, Transform } from 'node:stream';
import type { ReadableStream as WebReadableStream } from 'node:stream/web';
import type {
  PlaybackSourceResolver,
  ResolvedPlaybackSource,
} from '../../modules/playback/domain/playback-source-resolver.js';
import { YoutubePlaybackTokenBroker } from './youtube-playback-token-broker.js';

export type AudioStreamResult = Readonly<{
  stream: Readable;
  status: 200 | 206;
  contentType: string;
  contentLength: number;
  contentRange?: string;
}>;

export interface AudioStreamTransport {
  warm(signal?: AbortSignal): Promise<void>;
  prefetch(sourceId: string, signal: AbortSignal): Promise<void>;
  open(
    sourceId: string,
    signal: AbortSignal,
    range?: string,
  ): Promise<AudioStreamResult>;
  close(): Promise<void>;
}

export type AudioTransportMetric = Readonly<{
  stage: 'first-byte';
  durationMs: number;
  retry: boolean;
  success: boolean;
}>;

export class InvalidAudioRangeError extends Error {
  constructor(readonly contentLength?: number) {
    super('Invalid audio range');
  }
}

type SelectedRange = {
  start: number;
  end: number;
  partial: boolean;
  header?: string;
};

export function selectAudioRange(
  value: string | undefined,
  contentLength: number,
): SelectedRange {
  if (!Number.isSafeInteger(contentLength) || contentLength <= 0)
    throw new InvalidAudioRangeError();
  if (value === undefined)
    return { start: 0, end: contentLength - 1, partial: false };
  const match = /^bytes=(\d*)-(\d*)$/.exec(value);
  if (!match || (!match[1] && !match[2]))
    throw new InvalidAudioRangeError(contentLength);
  let start: number;
  let end: number;
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!Number.isSafeInteger(suffix) || suffix <= 0)
      throw new InvalidAudioRangeError(contentLength);
    start = Math.max(0, contentLength - suffix);
    end = contentLength - 1;
  } else {
    start = Number(match[1]);
    end = match[2] ? Number(match[2]) : contentLength - 1;
    if (
      !Number.isSafeInteger(start) ||
      !Number.isSafeInteger(end) ||
      start < 0 ||
      start >= contentLength ||
      end < start
    )
      throw new InvalidAudioRangeError(contentLength);
    end = Math.min(end, contentLength - 1);
  }
  return {
    start,
    end,
    partial: true,
    header: `bytes=${start}-${end}`,
  };
}

function checkedMediaUrl(value: string) {
  const url = new URL(value);
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    !url.hostname.endsWith('.googlevideo.com')
  )
    throw new Error('Playback source unavailable');
  return url;
}

function byteLimiter(
  maximum: number,
  onFirstByte: () => void,
  onFailure: () => void,
) {
  let received = 0;
  return new Transform({
    transform(chunk: Buffer, _encoding, callback) {
      if (received === 0 && chunk.length > 0) onFirstByte();
      received += chunk.length;
      if (received > maximum) onFailure();
      callback(
        received > maximum ? new Error('Audio response too large') : null,
        chunk,
      );
    },
    flush(callback) {
      if (received !== maximum) onFailure();
      callback(
        received === maximum ? null : new Error('Audio response incomplete'),
      );
    },
  });
}

export class YoutubeAudioStream implements AudioStreamTransport {
  constructor(
    private readonly resolver: PlaybackSourceResolver = new YoutubePlaybackTokenBroker(),
    private readonly fetcher: typeof fetch = fetch,
    private readonly metric: (value: AudioTransportMetric) => void = () => {},
  ) {}

  warm(signal?: AbortSignal) {
    return this.resolver.warm(signal);
  }

  async prefetch(sourceId: string, signal: AbortSignal) {
    await this.resolver.resolve(sourceId, signal);
  }

  close() {
    return this.resolver.close();
  }

  async open(sourceId: string, signal: AbortSignal, range?: string) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(sourceId) || signal.aborted)
      throw new Error('Playback source unavailable');
    const started = Date.now();
    let retried = false;
    let measured = false;
    const record = (success: boolean) => {
      if (measured) return;
      measured = true;
      this.metric({
        stage: 'first-byte',
        durationMs: Date.now() - started,
        retry: retried,
        success,
      });
    };
    try {
      let source = await this.resolver.resolve(sourceId, signal);
      let selection = selectAudioRange(range, source.contentLength);
      let response = await this.fetchSource(source, selection, signal);
      if (response.status === 403) {
        retried = true;
        this.resolver.invalidate(sourceId);
        source = await this.resolver.resolve(sourceId, signal);
        selection = selectAudioRange(range, source.contentLength);
        response = await this.fetchSource(source, selection, signal);
      }
      return this.normalizeResponse(
        response,
        source,
        selection,
        () => record(true),
        () => record(false),
      );
    } catch (error) {
      record(false);
      throw error;
    }
  }

  private async fetchSource(
    source: ResolvedPlaybackSource,
    selection: SelectedRange,
    signal: AbortSignal,
  ) {
    let url = checkedMediaUrl(source.privateUrl);
    for (let redirect = 0; redirect <= 2; redirect++) {
      const opening = new AbortController();
      const timer = setTimeout(() => opening.abort(), 15_000);
      let response: Response;
      try {
        response = await this.fetcher(url, {
          headers: selection.header ? { Range: selection.header } : undefined,
          redirect: 'manual',
          signal: AbortSignal.any([signal, opening.signal]),
        });
      } finally {
        clearTimeout(timer);
      }
      if (![301, 302, 303, 307, 308].includes(response.status)) return response;
      const location = response.headers.get('location');
      if (!location || redirect === 2)
        throw new Error('Playback source unavailable');
      url = checkedMediaUrl(new URL(location, url).href);
    }
    throw new Error('Playback source unavailable');
  }

  private normalizeResponse(
    response: Response,
    source: ResolvedPlaybackSource,
    selection: SelectedRange,
    onFirstByte: () => void,
    onFailure: () => void,
  ): AudioStreamResult {
    const expectedStatus = selection.partial ? 206 : 200;
    const expectedLength = selection.end - selection.start + 1;
    const declaredLength = Number(response.headers.get('content-length'));
    const contentRange = selection.partial
      ? `bytes ${selection.start}-${selection.end}/${source.contentLength}`
      : undefined;
    if (
      response.status !== expectedStatus ||
      !response.body ||
      (Number.isFinite(declaredLength) && declaredLength !== expectedLength) ||
      (selection.partial &&
        response.headers.get('content-range') !== contentRange)
    )
      throw new Error('Playback source unavailable');
    const upstream = Readable.fromWeb(
      response.body as unknown as WebReadableStream<Uint8Array>,
    );
    const limited = byteLimiter(expectedLength, onFirstByte, onFailure);
    // pipe() no reenvía por sí solo los errores del origen. El body de fetch
    // puede emitir AbortError después de que el consumidor ya cerró el stream;
    // se mantiene este listener durante toda la vida del origen y se entrega
    // el error al stream público, que la ruta/pipeline controla.
    upstream.on('error', (error: Error) => limited.destroy(error));
    limited.on('close', () => upstream.destroy());
    return {
      stream: upstream.pipe(limited),
      status: expectedStatus,
      contentType: source.mimeType,
      contentLength: expectedLength,
      ...(contentRange ? { contentRange } : {}),
    };
  }
}
