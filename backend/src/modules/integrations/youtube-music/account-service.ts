import { randomUUID } from 'node:crypto';
import { LruCache } from '../../../infrastructure/cache/lru-cache.js';
import type {
  AccountSurface,
  MusicAccountCatalog,
} from '../../../infrastructure/youtube/music-account-catalog.js';
import { LinkError } from '../youtube/domain.js';
import type { VideoDetails } from '../youtube/library-domain.js';
import type { YoutubeLinkService } from '../youtube/link-service.js';
import {
  ChannelMusicService,
  type ChannelMusicProvider,
} from './channel-service.js';
import type { AccountPageResult, MusicItem, MusicTrack } from './provider.js';

interface PendingPage {
  rows: MusicItem[];
  next?: string;
  started: boolean;
  playlistCursor?: string;
  playlistTokens?: string[];
  checkedTokens: string[];
  title?: string;
}
const surfaces = [
  'home',
  'songs',
  'liked',
  'playlists',
  'playlist',
  'albums',
  'album',
  'artists',
  'artist',
  'search',
] as const;
const channelSurfaces = [
  'playlists',
  'playlist',
  'search',
  'artists',
  'artist',
];
const activityCapabilities = [
  'mysicRecents',
  'onRepeat',
  'recordInMysic',
  'playback',
];
type Personalization = 'verified' | 'channelOnly' | 'unverified';
// Google continuations are opaque and can represent more rows than a mobile page.
// Retain unread rows on the server, scoped to this user, link and view by LibraryCursors.
export class AccountMusicService extends ChannelMusicService {
  private readonly pendingPages = new LruCache<PendingPage>(1024, 15 * 60_000);
  private readonly verifiedAccess = new LruCache<Personalization>(
    1024,
    5 * 60_000,
  );
  private readonly transientAccess = new LruCache<Personalization>(
    1024,
    15_000,
  );
  private readonly checkingAccess = new Map<string, Promise<Personalization>>();
  constructor(
    link: YoutubeLinkService,
    data: ChannelMusicProvider,
    sources: ReadonlyMap<string, string>,
    private readonly catalog: MusicAccountCatalog,
  ) {
    super(link, data, sources);
  }
  private accessKey(uid: string, generation: string) {
    return JSON.stringify([uid, generation]);
  }
  private async access(
    uid: string,
    generation: string,
  ): Promise<Personalization> {
    const key = this.accessKey(uid, generation);
    const cached =
      this.verifiedAccess.get(key) ?? this.transientAccess.get(key);
    if (cached) return cached;
    const pending = this.checkingAccess.get(key);
    if (pending) return pending;
    const check = this.checkAccess(uid, generation, key);
    this.checkingAccess.set(key, check);
    try {
      return await check;
    } finally {
      this.checkingAccess.delete(key);
    }
  }
  private async checkAccess(
    uid: string,
    generation: string,
    key: string,
  ): Promise<Personalization> {
    const userId = await this.link.owner(uid);
    const state = await this.library.authorized(
      userId,
      generation,
      AbortSignal.timeout(6500),
      async (_channel, _binding, read): Promise<Personalization> => {
        try {
          await read((ctx) => this.catalog.verify(ctx));
          return 'verified';
        } catch (err) {
          if (!(err instanceof LinkError)) throw err;
          if (err.code === 'MUSIC_ACCESS_DENIED') return 'channelOnly';
          if (
            err.status === 429 ||
            err.status === 503 ||
            err.code === 'MUSIC_PLAYLIST_NOT_FOUND'
          )
            return 'unverified';
          throw err;
        }
      },
    );
    (state === 'unverified' ? this.transientAccess : this.verifiedAccess).set(
      key,
      state,
    );
    return state;
  }
  override async connection(uid: string) {
    const state = await super.connection(uid);
    if (state.status !== 'linked' || !state.generation)
      return { ...state, personalization: 'notLinked', capabilities: [] };
    const personalization = await this.access(uid, state.generation);
    return {
      ...state,
      personalization,
      capabilities:
        personalization === 'verified'
          ? [...surfaces, ...activityCapabilities, 'accountMusicCatalog']
          : [...channelSurfaces, ...activityCapabilities],
    };
  }
  protected override mapTrack(
    video: VideoDetails | undefined,
    entryId?: string,
  ): MusicTrack[] {
    const rows = super.mapTrack(
      video && (video.isMusicCategory || video.isRecording)
        ? { ...video, isRecording: true }
        : undefined,
      entryId,
    );
    return rows.map((row) => ({
      ...row,
      playback: row.audioUrl ? 'licensed' : 'native',
    }));
  }
  override async read(
    uid: string,
    generation: string,
    request: AccountSurface,
    limit?: number,
    cursor?: string,
    signal = new AbortController().signal,
  ): Promise<AccountPageResult> {
    if (request.surface === 'mysicRecents' || request.surface === 'onRepeat')
      return super.read(uid, generation, request, limit, cursor, signal);
    if (!this.link.enabled || !surfaces.some((s) => s === request.surface))
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    // Public music search in the Data API is independent of access to the private Music feed.
    if (request.surface === 'search')
      return super.read(uid, generation, request, limit, cursor, signal);
    const personalization = await this.access(uid, generation);
    if (personalization !== 'verified') {
      if (channelSurfaces.includes(request.surface))
        return super.read(uid, generation, request, limit, cursor, signal);
      throw new LinkError(
        personalization === 'channelOnly' ? 403 : 503,
        personalization === 'channelOnly'
          ? 'MUSIC_ACCESS_DENIED'
          : 'MUSIC_ACCESS_UNVERIFIED',
      );
    }
    try {
      return await this.readAccount(
        uid,
        generation,
        request,
        limit,
        cursor,
        signal,
      );
    } catch (err) {
      // A single inaccessible playlist does not invalidate the whole account.
      if (
        !(err instanceof LinkError) ||
        err.code !== 'MUSIC_ACCESS_DENIED' ||
        ['album', 'playlist', 'artist'].includes(request.surface)
      )
        throw err;
      this.verifiedAccess.set(this.accessKey(uid, generation), 'channelOnly');
      if (!channelSurfaces.includes(request.surface)) throw err;
      if (cursor) throw new LinkError(409, 'CURSOR_EXPIRED');
      return super.read(uid, generation, request, limit, undefined, signal);
    }
  }
  private async readAccount(
    uid: string,
    generation: string,
    request: AccountSurface,
    limit: number | undefined,
    cursor: string | undefined,
    signal: AbortSignal,
  ): Promise<AccountPageResult> {
    if (
      request.surface === 'album' &&
      !/^MPRE[\w-]+$/.test(request.playlistId ?? '')
    )
      throw new LinkError(400, 'INVALID_REQUEST');
    const userId = await this.link.owner(uid);
    return this.library.authorized(
      userId,
      generation,
      signal,
      async (channel, _, read) => {
        const scope = JSON.stringify([
          'music-account-v2',
          userId,
          channel,
          generation,
          request.surface,
          request.query,
          request.playlistId,
          request.artistId,
        ]);
        const page = this.cursors.resume(
          scope,
          cursor,
          limit ?? (cursor ? undefined : 20),
        );
        const prior = page.token
          ? this.pendingPages.get(page.token)
          : undefined;
        if (page.token && !prior) throw new LinkError(409, 'CURSOR_EXPIRED');
        const state: PendingPage = prior
          ? {
              ...prior,
              rows: [...prior.rows],
              checkedTokens: [...prior.checkedTokens],
              playlistTokens: prior.playlistTokens?.slice(),
            }
          : { rows: [], started: false, checkedTokens: [] };
        const items: MusicItem[] = [];
        const ids: string[] = [];
        let calls = 0,
          excludedCount = 0;
        const detail =
          request.surface === 'playlist' || request.surface === 'album';
        while (items.length < page.size) {
          if (!state.rows.length) {
            if ((state.started && !state.next) || calls >= 6) break;
            const batch = await read((ctx) =>
              this.catalog.read(ctx, request, state.next),
            );
            calls++;
            if (batch.next && state.checkedTokens.includes(batch.next))
              throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');
            if (batch.next) state.checkedTokens.push(batch.next);
            state.rows = [...batch.items];
            state.title ||= batch.title;
            state.next = batch.next;
            state.started = true;
            excludedCount += batch.excluded;
            continue;
          }
          const item = state.rows[0]!;
          // Even the Music playlist shelf may contain ordinary YouTube lists. Require a real musical entry, including in a later page of a mixed playlist.
          if (
            item.kind === 'playlist' &&
            (request.surface === 'playlists' || request.surface === 'home')
          ) {
            if (calls >= 6) break;
            let contents;
            try {
              contents = await read((ctx) =>
                this.catalog.read(
                  ctx,
                  { surface: 'playlist', playlistId: item.id },
                  state.playlistCursor,
                ),
              );
            } catch (err) {
              if (
                !(err instanceof LinkError) ||
                (err.status !== 404 && err.code !== 'MUSIC_ACCESS_DENIED')
              )
                throw err;
            }
            calls++;
            if (!contents?.items.some((row) => row.kind === 'track')) {
              if (contents?.next) {
                if (state.playlistTokens?.includes(contents.next))
                  throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');
                (state.playlistTokens ??= []).push(contents.next);
                state.playlistCursor = contents.next;
                continue;
              }
              state.rows.shift();
              state.playlistCursor = undefined;
              state.playlistTokens = undefined;
              excludedCount++;
              continue;
            }
            state.playlistCursor = undefined;
            state.playlistTokens = undefined;
          }
          state.rows.shift();
          const key = item.kind + ':' + item.id;
          if (!detail && page.seen.has(key)) continue;
          if (!detail) {
            page.seen.add(key);
            ids.push(key);
          }
          const audio =
            item.kind === 'track' ? this.sources.get(item.id) : undefined;
          items.push(
            item.kind === 'track' && audio
              ? { ...item, playback: 'licensed', audioUrl: audio }
              : item,
          );
        }
        const pending =
          state.rows.length || state.next ? randomUUID() : undefined;
        if (pending) this.pendingPages.set(pending, state);
        return {
          items,
          title: state.title,
          excludedCount,
          nextCursor: this.cursors.next(scope, page, ids, pending),
        };
      },
    );
  }
}
