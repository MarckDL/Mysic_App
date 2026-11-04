import type { MusicProvider } from '../../catalog/domain/music-provider.js';
import {
  ProviderTimeoutError,
  ProviderUnavailableError,
} from '../../catalog/domain/music-provider.js';
import {
  demoAssetPath,
  demoSourceId,
  type PlaybackResult,
} from '../domain/playback-result.js';

export class PlaybackService {
  constructor(
    private readonly providers: ReadonlyMap<string, MusicProvider>,
    private readonly timeoutMs = 10_000,
  ) {}
  async resolve(source: string, sourceId: string): Promise<PlaybackResult> {
    const provider = this.providers.get(source);
    if (!provider) throw new ProviderUnavailableError();
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout>;
    const timeout = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new ProviderTimeoutError());
      }, this.timeoutMs);
    });
    try {
      const result = await Promise.race([
        provider.resolvePlayback(sourceId, controller.signal),
        timeout,
      ]);
      // Lista explícita de entrega habilitada. No devolver URLs/arbitrary assets del proveedor.
      if (result.mode === 'direct') {
        if (
          source === 'youtube' &&
          result.delivery === 'api-stream' &&
          /^[A-Za-z0-9_-]{11}$/.test(sourceId) &&
          result.sourceId === sourceId &&
          result.path === `/api/v1/playback/audio/${sourceId}` &&
          result.contentType === 'audio/mp4' &&
          result.seekable === false &&
          result.availabilityVerified === false
        ) {
          return {
            mode: 'direct',
            delivery: 'api-stream',
            sourceId,
            path: result.path,
            contentType: 'audio/mp4',
            seekable: false,
            availabilityVerified: false,
          };
        }

        if (
          source !== 'demo' ||
          sourceId !== demoSourceId ||
          result.delivery !== 'asset' ||
          result.assetPath !== demoAssetPath ||
          result.contentType !== 'audio/wav' ||
          result.durationSeconds !== 8
        ) {
          throw new ProviderUnavailableError();
        }
        return {
          mode: 'direct',
          delivery: 'asset',
          assetPath: demoAssetPath,
          contentType: 'audio/wav',
          durationSeconds: 8,
        };
      }
      if (result.mode === 'embedded')
        return {
          mode: 'unavailable',
          reason: 'La reproducción embebida aún no está integrada.',
        };
      if (result.mode !== 'unavailable' || typeof result.reason !== 'string')
        throw new ProviderUnavailableError();
      return { mode: 'unavailable', reason: result.reason.slice(0, 300) };
    } finally {
      clearTimeout(timer!);
    }
  }
}
