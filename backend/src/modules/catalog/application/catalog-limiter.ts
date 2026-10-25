import { LruCache } from '../../../infrastructure/cache/lru-cache.js';

export class CatalogLimiter {
  private readonly windows: LruCache<{ count: number; until: number }>;
  constructor(
    private readonly now: () => number = Date.now,
    private readonly limit = 30,
    private readonly windowMs = 60_000,
  ) {
    this.windows = new LruCache(10_000, windowMs, now);
  }
  consume(uid: string): number | null {
    const now = this.now();
    let window = this.windows.get(uid);
    if (!window || window.until <= now) {
      window = { count: 0, until: now + this.windowMs };
      this.windows.set(uid, window);
    }
    if (window.count >= this.limit)
      return Math.max(1, Math.ceil((window.until - now) / 1000));
    window.count++;
    return null;
  }
}
