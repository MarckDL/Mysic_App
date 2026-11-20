import { LruCache } from '../../../infrastructure/cache/lru-cache.js';
import type { AccountPageResult } from '../../integrations/youtube-music/provider.js';
import { ProviderUnavailableError } from '../domain/music-provider.js';

export const searchTypes = ['all', 'song', 'video', 'artist', 'album'] as const;
export type DiscoveryType = (typeof searchTypes)[number];
export type DiscoveryRequest =
  | { view: 'explore' }
  | { view: 'search'; query: string; type: DiscoveryType }
  | { view: 'artist' | 'album' | 'playlist' | 'related'; id: string };
export type DiscoveryLoader = (
  request: DiscoveryRequest,
  signal: AbortSignal,
) => Promise<AccountPageResult>;

export class DiscoveryService {
  private readonly pages = new LruCache<AccountPageResult>(160, 2 * 60_000);
  private readonly inFlight = new Map<string, Promise<AccountPageResult>>();
  constructor(
    private readonly primary: DiscoveryLoader,
    private readonly fallback: DiscoveryLoader,
  ) {}
  async related(seedId: string, signal: AbortSignal) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(seedId))
      throw new ProviderUnavailableError();
    signal.throwIfAborted();
    return new Promise<AccountPageResult>((resolve, reject) => {
      const abort = () => reject(signal.reason);
      signal.addEventListener('abort', abort, { once: true });
      this.read({ view: 'related', id: seedId })
        .then(resolve, reject)
        .finally(() => signal.removeEventListener('abort', abort));
    });
  }
  async read(request: DiscoveryRequest) {
    const key = JSON.stringify(request);
    const cached = this.pages.get(key);
    if (cached) return cached;
    const existing = this.inFlight.get(key);
    if (existing) return existing;
    if (this.inFlight.size >= 16) throw new ProviderUnavailableError();
    // El escritorio requiere autenticación para Related. El catálogo público
    // obtiene esas sugerencias y, si faltan pistas, la radio de la canción.
    const lookup =
      request.view === 'related'
        ? this.primary(request, AbortSignal.timeout(22_000))
        : this.primary(request, AbortSignal.timeout(8_000)).catch(() =>
            this.fallback(request, AbortSignal.timeout(7_000)),
          );
    const load = lookup
      .then((page) => {
        this.pages.set(key, page);
        return page;
      })
      .finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, load);
    return load;
  }
}
