import { randomBytes, randomUUID } from 'node:crypto';
import { SecretBox } from '../../../infrastructure/youtube/secrets.js';
import { LinkError } from '../youtube/domain.js';
import { LibraryCursors } from '../youtube/library-cursor.js';
import type {
  MusicAccount,
  MusicListen,
  MusicPageRequest,
  YouTubeMusicProvider,
} from './provider.js';

interface Binding {
  account: MusicAccount;
  generation: string;
  expiresAt: number;
}

export class YouTubeMusicService {
  private readonly revisions = new Map<string, string>();
  private readonly bindings = new Map<string, Binding>();
  private readonly cursors = new LibraryCursors(
    new SecretBox('music', new Map([['music', randomBytes(32)]])),
  );

  constructor(
    private readonly provider: YouTubeMusicProvider | null,
    private readonly now = Date.now,
    private readonly lifetimeMs = 8 * 60 * 60_000,
  ) {}

  connection(uid: string) {
    const accounts = this.provider?.accounts(uid) ?? [];
    const binding = this.bindings.get(uid);
    return {
      status:
        accounts.length === 0
          ? 'unavailable'
          : !binding
            ? 'unlinked'
            : binding.expiresAt <= this.now()
              ? 'expired'
              : 'linked',
      provider: accounts.length === 0 ? null : this.provider?.kind,
      capabilities: accounts.length === 0 ? [] : this.provider?.capabilities,
      accounts,
      account: binding?.account ?? null,
      generation: binding?.generation ?? null,
    };
  }

  private assertGeneration(uid: string, generation: string | null) {
    if ((this.bindings.get(uid)?.generation ?? null) !== generation)
      throw new LinkError(409, 'MUSIC_LINK_CHANGED');
  }

  async link(uid: string, accountId: string, generation: string | null) {
    const provider = this.provider;
    if (!provider?.accounts(uid).length)
      throw new LinkError(503, 'MUSIC_UNAVAILABLE');
    this.assertGeneration(uid, generation);
    const before = this.revisions.get(uid);
    const account = await provider.confirm(uid, accountId);
    // Compare the full binding, including an unlink that occurred during confirmation.
    if (this.revisions.get(uid) !== before || account.id !== accountId)
      throw new LinkError(409, 'MUSIC_LINK_CHANGED');
    const next = randomUUID();
    this.revisions.set(uid, next);
    this.bindings.set(uid, {
      account,
      generation: next,
      expiresAt: this.now() + this.lifetimeMs,
    });
    return this.connection(uid);
  }

  unlink(uid: string, generation: string) {
    this.assertGeneration(uid, generation);
    this.bindings.delete(uid);
    this.revisions.set(uid, randomUUID());
  }

  private context(uid: string, generation: string) {
    const provider = this.provider;
    if (!provider?.accounts(uid).length)
      throw new LinkError(503, 'MUSIC_UNAVAILABLE');
    this.assertGeneration(uid, generation);
    const binding = this.bindings.get(uid)!;
    if (binding.expiresAt <= this.now())
      throw new LinkError(409, 'MUSIC_RECONNECT');
    return { provider, accountId: binding.account.id };
  }

  async read(
    uid: string,
    generation: string,
    request: Omit<MusicPageRequest, 'size' | 'continuation'>,
    limit?: number,
    cursor?: string,
  ) {
    const { provider, accountId } = this.context(uid, generation);
    if (!provider.capabilities.includes(request.surface))
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    const scope = JSON.stringify([
      uid,
      generation,
      accountId,
      request.surface,
      request.playlistId,
      request.query,
    ]);
    const page = this.cursors.resume(
      scope,
      cursor,
      limit ?? (cursor ? undefined : 20),
    );
    const { continuation, ...result } = await provider.read(uid, accountId, {
      ...request,
      size: page.size,
      continuation: page.token,
    });
    this.context(uid, generation);
    return {
      ...result,
      nextCursor: this.cursors.next(scope, page, [], continuation),
    };
  }

  async listen(
    uid: string,
    generation: string,
    id: string,
    listen?: MusicListen,
  ) {
    const { provider, accountId } = this.context(uid, generation);
    if (!provider.capabilities.includes('recordListen'))
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    if (listen) {
      await provider.recordListen(uid, accountId, id, listen);
      this.context(uid, generation);
      return null;
    }
    const result = await provider.findListen(uid, accountId, id);
    this.context(uid, generation);
    return result;
  }
}
