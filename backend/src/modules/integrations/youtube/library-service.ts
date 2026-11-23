import { setTimeout as delay } from 'node:timers/promises';
import { getDatabase } from '../../../infrastructure/database/prisma.js';
import { LinkError } from './domain.js';
import { YoutubeGrants } from './grants.js';
import { LibraryCursors } from './library-cursor.js';
import type {
  ConnectedLibraryProvider,
  ReadContext,
} from './library-domain.js';

export interface LibraryQuery {
  limit?: number;
  cursor?: string;
}
export type AuthorizedRead = <T>(
  operation: (context: ReadContext) => Promise<T>,
) => Promise<T>;

export class YoutubeLibraryService {
  private readonly cursors: LibraryCursors;
  constructor(
    private readonly grants: YoutubeGrants,
    private readonly provider: ConnectedLibraryProvider,
  ) {
    this.cursors = new LibraryCursors(grants.box);
  }
  async authorized<T>(
    userId: string,
    expectedGeneration: string | undefined,
    clientSignal: AbortSignal,
    run: (
      channelId: string,
      generation: string,
      read: AuthorizedRead,
      activityEpoch: number,
    ) => Promise<T>,
    verifyActivityEpoch = false,
  ): Promise<T> {
    const connections = getDatabase().externalMusicConnection;
    const current = await connections.findUnique({ where: { userId } });
    if (!current || current.status !== 'linked')
      throw new LinkError(409, 'REAUTHORIZE_YOUTUBE');
    if (
      expectedGeneration !== undefined &&
      current.generation !== expectedGeneration
    )
      throw new LinkError(409, 'YOUTUBE_LINK_CHANGED');
    const binding = {
      userId,
      generation: current.generation,
      status: 'linked',
    };
    const ensureCurrent = async () => {
      const latest = await connections.findFirst({
        where: binding,
        select: { mysicActivityEpoch: true },
      });
      if (!latest) throw new LinkError(409, 'YOUTUBE_LINK_CHANGED');
      if (
        verifyActivityEpoch &&
        latest.mysicActivityEpoch !== current.mysicActivityEpoch
      )
        throw new LinkError(409, 'MYSIC_ACTIVITY_CHANGED');
    };
    const signal = AbortSignal.any([clientSignal, AbortSignal.timeout(15_000)]);
    const deadline = Date.now() + 15_000;
    const checkTime = () => {
      if (signal.aborted) throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    };
    checkTime();
    let access = await this.grants.access(
      userId,
      false,
      current.generation,
      current,
    );
    let refreshed = false,
      retries = 0;
    const read = async <T>(operation: (context: ReadContext) => Promise<T>) => {
      for (;;) {
        checkTime();
        try {
          return await operation({ access, signal });
        } catch (e) {
          if (!(e instanceof LinkError)) throw e;
          if (e.code === 'YOUTUBE_ACCESS_REJECTED') {
            if (refreshed) throw new LinkError(409, 'REAUTHORIZE_YOUTUBE');
            refreshed = true;
            access = await this.grants.access(
              userId,
              true,
              current.generation,
              current,
            );
            continue;
          }
          if (e.code !== 'GOOGLE_UNAVAILABLE' || retries >= 2) throw e;
          const wait = Math.max(
            (e.retryAfter ?? 0) * 1000,
            100 * 2 ** retries + Math.random() * 100,
          );
          if (Date.now() + wait >= deadline || signal.aborted) throw e;
          retries++;
          await delay(wait, undefined, { signal }).catch(() => {
            throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
          });
        }
      }
    };
    const result = await run(
      current.channelId,
      current.generation,
      read,
      current.mysicActivityEpoch,
    );
    await ensureCurrent();
    checkTime();
    return result;
  }

  async list(
    userId: string,
    playlistId: string | undefined,
    query: LibraryQuery,
    clientSignal: AbortSignal,
  ) {
    return this.authorized(
      userId,
      undefined,
      clientSignal,
      async (channelId, generation, read) => {
        const context = JSON.stringify([
          'youtube-library-v1',
          userId,
          generation,
          channelId,
          playlistId ?? null,
        ]);
        const page = this.cursors.resume(context, query.cursor, query.limit);
        const request = { maxResults: page.size, pageToken: page.token };
        const pageIds: string[] = [];
        const isNew = (id: string) => {
          if (page.seen.has(id)) return false;
          page.seen.add(id);
          pageIds.push(id);
          return true;
        };
        const finish = <T>(items: T[], nextToken?: string) => {
          return {
            items,
            nextCursor: this.cursors.next(context, page, pageIds, nextToken),
            fetchedAt: new Date().toISOString(),
          };
        };
        if (!playlistId) {
          const result = await read((ctx) =>
            this.provider.listPlaylists(ctx, request),
          );
          const items = result.items
            .filter((item) => item.channelId === channelId && isNew(item.id))
            .map(({ channelId: _owner, ...dto }) => dto);
          return finish(items, result.nextPageToken);
        }
        const owner = await read((ctx) =>
          this.provider.playlistOwner(ctx, playlistId),
        );
        if (owner !== channelId) throw new LinkError(404, 'PLAYLIST_NOT_FOUND');
        const result = await read((ctx) =>
          this.provider.listPlaylistItems(ctx, playlistId, request),
        );
        const entries = result.items.filter((item) =>
          isNew(item.playlistItemId),
        );
        const ids = [
          ...new Set(
            entries.flatMap((item) => (item.videoId ? [item.videoId] : [])),
          ),
        ];
        const videos = ids.length
          ? await read((ctx) => this.provider.getVideos(ctx, ids))
          : [];
        const byId = new Map(videos.map((video) => [video.id, video]));
        const items = entries.map((item) => {
          const video = item.videoId ? byId.get(item.videoId) : undefined;
          const availability = video?.availability ?? 'unavailable';
          return {
            ...item,
            title: video?.title ?? item.title,
            channelTitle: video?.channelTitle ?? null,
            thumbnailUrl: video?.thumbnailUrl ?? null,
            durationSeconds: video?.durationSeconds ?? null,
            availability,
            openUrl:
              availability === 'available'
                ? 'https://www.youtube.com/watch?v=' + item.videoId
                : null,
          };
        });
        return {
          ...finish(items, result.nextPageToken),
          unavailableCount: items.filter(
            (item) => item.availability === 'unavailable',
          ).length,
        };
      },
    );
  }
}
