import { z } from 'zod';
import {
  appActivityPage,
  findAppListen,
  storeAppListen,
  updateAppActivity,
} from './app-activity.js';
import { LinkError } from '../youtube/domain.js';
import { LibraryCursors } from '../youtube/library-cursor.js';
import type {
  ConnectedLibraryProvider,
  GooglePage,
  PageRequest,
  ReadContext,
  VideoDetails,
} from '../youtube/library-domain.js';
import {
  YoutubeLibraryService,
  type AuthorizedRead,
} from '../youtube/library-service.js';
import type { YoutubeLinkService } from '../youtube/link-service.js';
import type {
  AccountPageResult,
  MusicListen,
  MusicArtist,
  MusicPageRequest,
  MusicPlaylist,
  MusicTrack,
} from './provider.js';

export interface ChannelMusicProvider extends ConnectedLibraryProvider {
  subscribedMusicChannels(
    context: ReadContext,
    page: PageRequest,
  ): Promise<GooglePage<MusicArtist>>;
  playlistInfo(
    context: ReadContext,
    id: string,
  ): Promise<{ channelId: string; title: string; private: boolean } | null>;
  listLikedVideos(
    context: ReadContext,
    page: PageRequest,
  ): Promise<GooglePage<VideoDetails>>;
  searchMusic(
    context: ReadContext,
    query: string,
    page: PageRequest,
    channelId?: string,
  ): Promise<GooglePage<VideoDetails>>;
}
export function licensedRecordings(
  value: string | undefined,
): ReadonlyMap<string, string> {
  if (!value?.trim()) return new Map();
  const entries = z
    .record(
      z.string().regex(/^[A-Za-z0-9_-]{11}$/),
      z.url({ protocol: /^https$/ }),
    )
    .parse(JSON.parse(value));
  for (const url of Object.values(entries)) {
    const uri = new URL(url);
    if (uri.username || uri.password || uri.search || uri.hash)
      throw new Error('Invalid licensed audio URL');
  }
  return new Map(Object.entries(entries));
}
const capabilities = [
  'playlists',
  'playlist',
  'liked',
  'search',
  'artist',
  'artists',
  'songs',
  'mysicRecents',
  'onRepeat',
] as const;
const allowed = new Set<string>(capabilities);
const scanPosition = z.object({
  list: z.string().optional(),
  offset: z.int().min(0).max(49).optional(),
  playlist: z.string().optional(),
  contents: z.string().optional(),
});
type ScanPosition = z.infer<typeof scanPosition>;

function recording(
  video: VideoDetails | undefined,
  sources: ReadonlyMap<string, string>,
  entryId?: string,
): MusicTrack[] {
  if (
    !video?.isRecording ||
    video.availability !== 'available' ||
    !video.title ||
    !/^[\w-]{11}$/.test(video.id)
  )
    return [];
  return [
    {
      kind: 'track',
      id: video.id,
      title: video.title,
      artist:
        video.channelTitle?.replace(/ - Topic$/, '') ||
        'Artista sin identificar',
      durationSeconds: video.durationSeconds ?? 0,
      thumbnailUrl: video.thumbnailUrl ?? undefined,
      playback: sources.has(video.id) ? 'licensed' : 'unavailable',
      audioUrl: sources.get(video.id),
      artistId: video.artistId,
      entryId,
    },
  ];
}

export class ChannelMusicService {
  protected readonly library: YoutubeLibraryService;
  protected readonly cursors: LibraryCursors;
  constructor(
    protected readonly link: YoutubeLinkService,
    private readonly provider: ChannelMusicProvider,
    protected readonly sources: ReadonlyMap<string, string> = new Map(),
  ) {
    this.library = new YoutubeLibraryService(link.grants, provider);
    this.cursors = new LibraryCursors(link.grants.box);
  }

  async connection(uid: string, _recheckMusic = false) {
    return this.connectionFor(await this.link.owner(uid));
  }

  protected async connectionFor(userId: string) {
    const current = await this.link.connection(userId);
    const linked = current.status === 'linked';
    const expired = current.status === 'reauthorization_required';
    return {
      provider: 'youtubeOAuth',
      status: !this.link.enabled
        ? 'unavailable'
        : linked
          ? 'linked'
          : expired
            ? 'expired'
            : 'unlinked',
      account: current.channel
        ? {
            id: current.channel.id,
            name: current.channel.title,
            historyPaused: current.mysicHistoryPaused === true,
          }
        : null,
      generation: current.generation ?? null,
      libraryId: current.mysicLibraryId ?? null,
      activityEpoch: current.mysicActivityEpoch ?? 0,
      accounts: [],
      capabilities: this.link.enabled
        ? [
            ...capabilities,
            'recordInMysic',
            ...(this.sources.size ? ['playback'] : []),
          ]
        : [],
    };
  }

  async unlink(uid: string, generation: string) {
    await this.link.unlink(await this.link.owner(uid), generation);
  }

  async activityPreference(
    uid: string,
    generation: string,
    action: boolean | 'clear',
  ) {
    if (!this.link.enabled)
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    await updateAppActivity(await this.link.owner(uid), generation, action);
  }

  protected mapTrack(video: VideoDetails | undefined, entryId?: string) {
    return recording(video, this.sources, entryId);
  }

  async listen(
    uid: string,
    generation: string,
    id: string,
    listen?: MusicListen,
  ) {
    if (!this.link.enabled)
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    const userId = await this.link.owner(uid);
    return this.library.authorized(
      userId,
      generation,
      new AbortController().signal,
      async (_channel, _binding, read) => {
        const existing = await findAppListen(userId, generation, id);
        if (!listen) return existing;
        if (existing) {
          if (existing.trackId !== listen.trackId)
            throw new LinkError(409, 'MUSIC_LISTEN_CONFLICT');
          return existing;
        }
        if (!/^[A-Za-z0-9_-]{11}$/.test(listen.trackId))
          throw new LinkError(400, 'INVALID_REQUEST');
        const videos = await read((ctx) =>
          this.provider.getVideos(ctx, [listen.trackId]),
        );
        const video = videos.find((v) => v.id === listen.trackId);
        if (!this.mapTrack(video).length)
          throw new LinkError(404, 'MUSIC_TRACK_NOT_FOUND');
        const threshold = video?.durationSeconds
          ? Math.min(30000, video.durationSeconds * 500)
          : 30000;
        if (listen.listenedMs < threshold)
          throw new LinkError(400, 'INSUFFICIENT_LISTEN');
        await storeAppListen(userId, generation, id, listen);
        return listen;
      },
    );
  }

  private async tracks(
    read: AuthorizedRead,
    playlistId: string,
    page: PageRequest,
  ) {
    const entries = await read((ctx) =>
      this.provider.listPlaylistItems(ctx, playlistId, page),
    );
    const ids = [
      ...new Set(entries.items.flatMap((e) => (e.videoId ? [e.videoId] : []))),
    ];
    const videos = ids.length
      ? await read((ctx) => this.provider.getVideos(ctx, ids))
      : [];
    const byId = new Map(videos.map((v) => [v.id, v]));
    const items = entries.items.flatMap((entry) =>
      this.mapTrack(byId.get(entry.videoId ?? ''), entry.playlistItemId),
    );
    return {
      items,
      excludedCount: entries.items.length - items.length,
      nextPageToken: entries.nextPageToken,
    };
  }

  // Bound cost per HTTP request. A mixed playlist can qualify on any page.
  private async libraryRows(
    songs: boolean,
    read: AuthorizedRead,
    channel: string,
    size: number,
    token?: string,
  ) {
    let position: ScanPosition = token
      ? scanPosition.parse(JSON.parse(token))
      : {};
    const items: (MusicPlaylist | MusicTrack)[] = [];
    let excludedCount = 0;
    const visited = new Set<string>();
    let list:
      Awaited<ReturnType<ChannelMusicProvider['listPlaylists']>> | undefined;
    let listPages = 0;
    let contentPages = 0;
    while (items.length < size) {
      const key = JSON.stringify(position);
      if (visited.has(key)) throw new LinkError(503, 'GOOGLE_INVALID_RESPONSE');
      visited.add(key);
      if (!list) {
        if (listPages >= 3) break;
        list = await read((ctx) =>
          this.provider.listPlaylists(ctx, {
            maxResults: 50,
            pageToken: position.list,
          }),
        );
        listPages++;
      }
      const offset = position.offset ?? 0;
      const item = list.items[offset];
      if (item && item.channelId === channel && item.itemCount !== 0) {
        if (contentPages >= 3) break;
        contentPages++;
        const result = await this.tracks(read, item.id, {
          maxResults: songs ? Math.min(50, size - items.length) : 50,
          pageToken:
            item.id === position.playlist ? position.contents : undefined,
        });
        if (songs) {
          excludedCount += result.excludedCount;
          items.push(
            ...result.items.map((track) => ({ ...track, entryId: undefined })),
          );
        }
        if (!songs && result.items.length) {
          items.push({
            kind: 'playlist',
            id: item.id,
            title: item.title,
            private: item.visibility === 'private',
            thumbnailUrl: item.thumbnailUrl ?? undefined,
          });
        } else if (result.nextPageToken) {
          position = {
            list: position.list,
            offset,
            playlist: item.id,
            contents: result.nextPageToken,
          };
          continue;
        }
      }
      if (offset + 1 < list.items.length) {
        position = { list: position.list, offset: offset + 1 };
        continue;
      }
      if (!list.nextPageToken)
        return { items, nextPageToken: undefined, excludedCount };
      position = { list: list.nextPageToken };
      list = undefined;
    }
    return { items, nextPageToken: JSON.stringify(position), excludedCount };
  }

  async read(
    uid: string,
    generation: string,
    request: Pick<
      MusicPageRequest,
      'surface' | 'query' | 'playlistId' | 'artistId'
    >,
    limit?: number,
    cursor?: string,
    signal = new AbortController().signal,
  ): Promise<AccountPageResult> {
    if (!this.link.enabled || !allowed.has(request.surface))
      throw new LinkError(503, 'MUSIC_CAPABILITY_UNAVAILABLE');
    const userId = await this.link.owner(uid);
    const readsActivity =
      request.surface === 'mysicRecents' || request.surface === 'onRepeat';
    return this.library.authorized(
      userId,
      generation,
      signal,
      async (channel, _, read, activityEpoch) => {
        const scope = JSON.stringify([
          'channel-music-v1',
          userId,
          channel,
          generation,
          request.surface,
          request.playlistId,
          request.query,
          request.artistId,
          ...(readsActivity ? [activityEpoch] : []),
        ]);
        const page = this.cursors.resume(
          scope,
          cursor,
          limit ?? (cursor ? undefined : 20),
        );
        const params = { maxResults: page.size, pageToken: page.token };
        let playlist: MusicPlaylist | undefined;
        const collect = async () => {
          if (
            request.surface === 'mysicRecents' ||
            request.surface === 'onRepeat'
          ) {
            const repeats = request.surface === 'onRepeat';
            const activity = await appActivityPage(
              userId,
              generation,
              repeats,
              page.size,
              page.token,
            );
            const ids = [...new Set(activity.rows.map((v) => v.event.videoId))];
            const videos = ids.length
              ? await read((ctx) => this.provider.getVideos(ctx, ids))
              : [];
            const byId = new Map(videos.map((video) => [video.id, video]));
            const items = activity.rows.flatMap(({ event, count }) =>
              this.mapTrack(
                byId.get(event.videoId),
                repeats ? event.videoId : event.listenId,
              ).map((track) => ({
                ...track,
                listenedAt: event.playedAt.toISOString(),
                playCount: repeats ? count : undefined,
              })),
            );
            return {
              items,
              nextPageToken: activity.nextPageToken,
              excludedCount: activity.rows.length - items.length,
            };
          }
          if (request.surface === 'artists') {
            const result = await read((ctx) =>
              this.provider.subscribedMusicChannels(ctx, params),
            );
            return {
              items: result.items,
              nextPageToken: result.nextPageToken,
              excludedCount: 0,
            };
          }
          if (request.surface === 'playlists' || request.surface === 'songs')
            return this.libraryRows(
              request.surface === 'songs',
              read,
              channel,
              page.size,
              page.token,
            );
          if (request.surface === 'playlist' && request.playlistId) {
            const id = request.playlistId;
            const info = await read((ctx) =>
              this.provider.playlistInfo(ctx, id),
            );
            if (!info || info.channelId !== channel)
              throw new LinkError(404, 'MUSIC_PLAYLIST_NOT_FOUND');
            playlist = {
              kind: 'playlist',
              id,
              title: info.title,
              private: info.private,
            };
            return this.tracks(read, id, params);
          }
          const result =
            request.surface === 'liked'
              ? await read((ctx) => this.provider.listLikedVideos(ctx, params))
              : await read((ctx) =>
                  this.provider.searchMusic(
                    ctx,
                    request.query ?? '',
                    params,
                    request.artistId,
                  ),
                );
          const items = result.items.flatMap((v) =>
            request.surface === 'artist' && v.artistId !== request.artistId
              ? []
              : this.mapTrack(v),
          );
          return {
            items,
            nextPageToken: result.nextPageToken,
            excludedCount: result.items.length - items.length,
          };
        };
        const result = await collect();
        const items = result.items.filter((item) => {
          const id =
            item.kind === 'track' ? (item.entryId ?? item.id) : item.id;
          if (page.seen.has(id)) return false;
          page.seen.add(id);
          return true;
        });
        const ids = items.map((item) =>
          item.kind === 'track' ? (item.entryId ?? item.id) : item.id,
        );
        return {
          items,
          playlist,
          excludedCount: result.excludedCount,
          nextCursor: this.cursors.next(scope, page, ids, result.nextPageToken),
        };
      },
      readsActivity,
    );
  }
}
