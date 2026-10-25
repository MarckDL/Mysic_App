// LRU pequeña y acotada, sin dependencias ni temporizadores por entrada.
export class LruCache<T> {
  private readonly entries = new Map<string, { value: T; expiresAt: number }>();
  constructor(
    private readonly max: number,
    private readonly ttlMs: number,
    private readonly now: () => number = Date.now,
  ) {
    if (!Number.isInteger(max) || max < 1 || ttlMs <= 0)
      throw new Error('Invalid cache configuration');
  }
  get(key: string): T | undefined {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    this.entries.delete(key);
    if (entry.expiresAt <= this.now()) return undefined;
    this.entries.set(key, entry);
    return entry.value;
  }
  set(key: string, value: T): void {
    this.entries.delete(key);
    this.entries.set(key, { value, expiresAt: this.now() + this.ttlMs });
    while (this.entries.size > this.max) {
      const oldest = this.entries.keys().next().value;
      if (oldest !== undefined) this.entries.delete(oldest);
    }
  }
}
