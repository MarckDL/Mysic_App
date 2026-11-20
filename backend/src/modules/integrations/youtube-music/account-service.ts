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
// Google continuations are opaque and can represent more rows than a mobile page.
// Retain unread rows on the server, scoped to this user, link and view by LibraryCursors.
export class AccountMusicService extends ChannelMusicService {
  private readonly pendingPages = new LruCache<PendingPage>(1024, 15 * 60_000);
  constructor(
    link: YoutubeLinkService,
    data: ChannelMusicProvider,
    sources: ReadonlyMap<string, string>,
    private readonly catalog: MusicAccountCatalog,
  ) {
    super(link, data, sources);
  }
  override async connection(uid: string) {
    const state = await super.connection(uid);
    return {
      ...state,
      capabilities: state.capabilities.length
        ? [
            ...surfaces,
            'mysicRecents',
            'onRepeat',
            'recordInMysic',
            'playback',
            'accountMusicCatalog',
          ]
        : [],
    };
  }
  protected override activityTrack(
    video: VideoDetails | undefined,
    entryId?: string,
  ): MusicTrack[] {
    const rows = super.activityTrack(
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
              if (!(err instanceof LinkError) || err.status !== 404) throw err;
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
