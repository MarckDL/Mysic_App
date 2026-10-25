import { LruCache } from '../../../infrastructure/cache/lru-cache.js';
import {
  ProviderTimeoutError,
  ProviderUnavailableError,
  type MusicProvider,
  type Track,
} from '../domain/music-provider.js';

export class CatalogService {
  private readonly searches: LruCache<Track[]>;
  private readonly tracks: LruCache<Track | null>;
  private readonly pending = new Map<string, Promise<unknown>>();
  constructor(
    private readonly provider: MusicProvider,
    private readonly options: {
      now?: () => number;
      timeoutMs?: number;
      maxPending?: number;
    } = {},
  ) {
    this.searches = new LruCache(100, 10 * 60_000, options.now);
    this.tracks = new LruCache(500, 60 * 60_000, options.now);
  }
  async search(query: string): Promise<Track[]> {
    const key = `youtube:song:${query}`;
    const cached = this.searches.get(key);
    if (cached !== undefined) return structuredClone(cached);
    return structuredClone(
      await this.coalesce(key, async (signal) => {
        const result = (await this.provider.search(query, signal)).slice(0, 20);
        signal.throwIfAborted();
        this.searches.set(key, result);
        return result;
      }),
    );
  }
  async getTrack(sourceId: string): Promise<Track | null> {
    const key = `youtube:${sourceId}`;
    const cached = this.tracks.get(key);
    if (cached !== undefined) return structuredClone(cached);
    return structuredClone(
      await this.coalesce(key, async (signal) => {
        const track = await this.provider.getTrack(sourceId, signal);
        signal.throwIfAborted();
        this.tracks.set(key, track);
        return track;
      }),
    );
  }
  private coalesce<T>(
    key: string,
    load: (signal: AbortSignal) => Promise<T>,
  ): Promise<T> {
    const pending = this.pending.get(key);
    if (pending) return pending as Promise<T>;
    if (this.pending.size >= (this.options.maxPending ?? 8)) {
      return Promise.reject(new ProviderUnavailableError());
    }
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout>;
    const timeout = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new ProviderTimeoutError());
      }, this.options.timeoutMs ?? 10_000);
    });
    const operation = Promise.race([
      Promise.resolve().then(() => load(controller.signal)),
      timeout,
    ]).finally(() => {
      clearTimeout(timer);
      this.pending.delete(key);
    });
    this.pending.set(key, operation);
    return operation;
  }
}
