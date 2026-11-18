import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { LruCache } from '../../../infrastructure/cache/lru-cache.js';
import { SecretBox, digest } from '../../../infrastructure/youtube/secrets.js';
import { LinkError } from './domain.js';

const lifetime = 15 * 60_000;
const payload = z.object({
  token: z.string().min(1).max(2048),
  size: z.number().int().min(1).max(50),
  history: z.uuid(),
  expires: z.number().int(),
});
type HistoryPage = { parent?: string; ids: string[]; tokenHash: string };
export class LibraryCursors {
  private readonly history: LruCache<HistoryPage>;
  constructor(
    private readonly box: SecretBox,
    private readonly now = Date.now,
  ) {
    this.history = new LruCache(1024, lifetime, now);
  }
  resume(context: string, cursor?: string, limit?: number) {
    const seen = new Set<string>(),
      tokens = new Set<string>();
    if (!cursor)
      return {
        size: limit ?? 50,
        token: undefined,
        history: undefined,
        expires: this.now() + lifetime,
        seen,
        tokens,
      };
    let data: z.infer<typeof payload>;
    try {
      const [, ...segments] = cursor.split('.');
      if (
        segments.some(
          (segment) =>
            Buffer.from(segment, 'base64url').toString('base64url') !== segment,
        )
      )
        throw new Error();
      data = payload.parse(JSON.parse(this.box.open(cursor, context)));
    } catch {
      throw new LinkError(409, 'INVALID_CURSOR');
    }
    if (data.expires <= this.now()) throw new LinkError(409, 'CURSOR_EXPIRED');
    if (limit !== undefined && data.size !== limit)
      throw new LinkError(409, 'INVALID_CURSOR');
    let id: string | undefined = data.history;
    while (id) {
      const previous = this.history.get(id);
      if (!previous) throw new LinkError(409, 'CURSOR_EXPIRED');
      previous.ids.forEach((value) => seen.add(value));
      tokens.add(previous.tokenHash);
      id = previous.parent;
    }
    return { ...data, seen, tokens };
  }
  next(
    context: string,
    page: ReturnType<LibraryCursors['resume']>,
    ids: string[],
    token?: string,
  ) {
    if (!token) return null;
    if (page.expires <= this.now()) throw new LinkError(409, 'CURSOR_EXPIRED');
    const tokenHash = digest(token);
    if (page.tokens.has(tokenHash))
      throw new LinkError(503, 'GOOGLE_INVALID_RESPONSE');
    const history = randomUUID();
    this.history.set(history, { parent: page.history, ids, tokenHash });
    return this.box.seal(
      JSON.stringify({
        token,
        history,
        expires: page.expires,
        size: page.size,
      }),
      context,
    );
  }
}
