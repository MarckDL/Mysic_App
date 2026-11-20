import type { CatalogService } from '../../catalog/application/catalog-service.js';
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
  'channelLiked',
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
interface Access {
  status: 'verified' | 'partialMusic' | 'channelOnly' | 'unverified';
  collections: string[];
}
// Google continuations are opaque and can represent more rows than a mobile page.
// Retain unread rows on the server, scoped to this user, link and view by LibraryCursors.
export class AccountMusicService extends ChannelMusicService {
  private readonly pendingPages = new LruCache<PendingPage>(1024, 15 * 60_000);
  private readonly verifiedAccess = new LruCache<Access>(1024, 5 * 60_000);
  private readonly transientAccess = new LruCache<Access>(1024, 15_000);
  private readonly checkingAccess = new Map<string, Promise<Access>>();
  constructor(
    link: YoutubeLinkService,
    data: ChannelMusicProvider,
    sources: ReadonlyMap<string, string>,
    private readonly catalog: MusicAccountCatalog,
    private readonly songs: Pick<CatalogService, 'search'>,
  ) {
    super(link, data, sources);
  }
  private accessKey(uid: string, generation: string) {
    return JSON.stringify([uid, generation]);
  }
  private async access(uid: string, generation: string): Promise<Access> {
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
  ): Promise<Access> {
    const userId = await this.link.owner(uid);
    const state = await this.library.authorized(
      userId,
      generation,
      AbortSignal.timeout(12_000),
      async (_channel, _binding, read): Promise<Access> => {
        try {
          await read((ctx) => this.catalog.verify(ctx));
          return { status: 'verified', collections: [] };
        } catch (err) {
          if (!(err instanceof LinkError)) throw err;
          if (err.code === 'MUSIC_ACCESS_DENIED') {
            const verify = this.catalog.verifyCollection?.bind(this.catalog);
            if (!verify) return { status: 'channelOnly', collections: [] };
            // Liked songs and saved albums are separate resources. Each must confirm
            // the signed-in user before it can become a source in the mobile library.
            const collections = ['liked', 'albums'] as const;
            const checks = await Promise.allSettled(
              collections.map((surface) => read((ctx) => verify(ctx, surface))),
            );
            const granted = collections.filter(
              (_, i) => checks[i]?.status === 'fulfilled',
            );
            const transient = checks.some(
              (result) =>
                result.status === 'rejected' &&
                (!(result.reason instanceof LinkError) ||
                  result.reason.status >= 429),
            );
            return {
              status: granted.length
                ? 'partialMusic'
                : transient
                  ? 'unverified'
                  : 'channelOnly',
              collections: granted.includes('albums')
                ? [...granted, 'album']
                : granted,
            };
          }
          if (
            err.status === 429 ||
            err.status === 503 ||
            err.code === 'MUSIC_PLAYLIST_NOT_FOUND'
          )
            return { status: 'unverified', collections: [] };
          throw err;
        }
      },
    );
    (state.status === 'unverified' || state.status === 'partialMusic'
      ? this.transientAccess
      : this.verifiedAccess
    ).set(key, state);
    return state;
  }
  override async connection(uid: string) {
    const state = await super.connection(uid);
    if (state.status !== 'linked' || !state.generation)
      return { ...state, personalization: 'notLinked', capabilities: [] };
    const access = await this.access(uid, state.generation);
    return {
      ...state,
      personalization: access.status,
      capabilities:
        access.status === 'verified'
          ? [...surfaces, ...activityCapabilities, 'accountMusicCatalog']
          : [
              ...channelSurfaces.filter(
                (cap) =>
                  cap !== 'channelLiked' ||
                  !access.collections.includes('liked'),
              ),
              ...access.collections,
              ...activityCapabilities,
            ],
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
    if (!this.link.enabled)
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    if (request.surface === 'channelLiked') {
      return super.read(
        uid,
        generation,
        { surface: 'liked' },
        limit,
        cursor,
        signal,
      );
    }
    if (!surfaces.some((s) => s === request.surface))
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    if (request.surface === 'search') {
      return this.readAccount(uid, generation, request, limit, cursor, signal);
    }
    const access = await this.access(uid, generation);
    if (
      access.status !== 'verified' &&
      !access.collections.includes(request.surface)
    ) {
      if (channelSurfaces.includes(request.surface))
        return super.read(uid, generation, request, limit, cursor, signal);
      throw new LinkError(
        access.status === 'unverified' ? 503 : 403,
        access.status === 'unverified'
          ? 'MUSIC_ACCESS_UNVERIFIED'
          : 'MUSIC_ACCESS_DENIED',
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
      const key = this.accessKey(uid, generation);
      this.verifiedAccess.delete(key);
      this.transientAccess.delete(key);
      if (!channelSurfaces.includes(request.surface)) throw err;
      if (cursor) throw new LinkError(409, 'CURSOR_EXPIRED');
      return super.read(uid, generation, request, limit, undefined, signal);
    }
  }
  private async searchSongs(query: string) {
    try {
      const tracks = await this.songs.search(query);
      return {
        items: tracks
          .filter((track) => track.source === 'youtube')
          .map((track): MusicTrack => ({
            kind: 'track',
            id: track.sourceId,
            title: track.title,
            artist: track.artistName,
            durationSeconds: track.durationSeconds ?? 0,
            thumbnailUrl: track.thumbnailUrl ?? undefined,
            playback: 'native',
          })),
        excluded: 0,
        next: undefined,
        title: undefined,
      };
    } catch {
      throw new LinkError(503, 'MUSIC_SEARCH_UNAVAILABLE');
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
            const batch =
              request.surface === 'search'
                ? await this.searchSongs(request.query ?? '')
                : await read((ctx) =>
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
