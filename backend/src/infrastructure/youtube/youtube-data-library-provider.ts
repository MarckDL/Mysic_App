import { z } from 'zod';
import { LinkError } from '../../modules/integrations/youtube/domain.js';
import type {
  ConnectedLibraryProvider,
  ReadContext,
  PageRequest,
  VideoDetails,
} from '../../modules/integrations/youtube/library-domain.js';
import {
  youtubeThumbnail,
  youtubeSourceIdPattern,
} from '../music/youtube-normalizer.js';

const identifier = z.string().min(1).max(512);
const optionalText = z.string().optional();
const thumbnails = z
  .object({
    high: z.unknown().optional(),
    medium: z.unknown().optional(),
    default: z.unknown().optional(),
  })
  .optional();
// Canonical music topics. Use topicCategories, plus curated IDs when a response includes them.
const musicTopics = new Set([
  'Music',
  'Christian_music',
  'Classical_music',
  'Country_music',
  'Electronic_music',
  'Hip_hop_music',
  'Independent_music',
  'Jazz',
  'Music_of_Asia',
  'Music_of_Latin_America',
  'Pop_music',
  'Reggae',
  'Rhythm_and_blues',
  'Rock_music',
  'Soul_music',
]);
const musicTopicIds = new Set([
  '/m/04rlf',
  '/m/02mscn',
  '/m/0ggq0m',
  '/m/01lyv',
  '/m/02lkt',
  '/m/0glt670',
  '/m/05rwpb',
  '/m/03_d0',
  '/m/028sqc',
  '/m/0g293',
  '/m/064t9',
  '/m/06cqb',
  '/m/06j6l',
  '/m/06by7',
  '/m/0gywn',
]);
const channelIdFormat = /^UC[A-Za-z0-9_-]{22}$/;

const channel = z.object({
  id: identifier,
  snippet: z.object({ title: z.string() }),
});
const playlist = z.object({
  id: identifier,
  snippet: z.object({ channelId: identifier, title: z.string(), thumbnails }),
  status: z
    .object({
      privacyStatus: z.enum(['public', 'unlisted', 'private']).optional(),
    })
    .optional(),
  contentDetails: z
    .object({ itemCount: z.number().int().nonnegative().optional() })
    .optional(),
});
const entry = z.object({
  id: identifier,
  snippet: z.object({
    position: z.number().int().nonnegative(),
    title: optionalText,
  }),
  contentDetails: z.object({ videoId: optionalText }).optional(),
});
const video = z.object({
  id: identifier,
  snippet: z
    .object({
      title: optionalText,
      channelTitle: optionalText,
      channelId: optionalText,
      categoryId: optionalText,
      description: optionalText,
      thumbnails,
    })
    .optional(),
  contentDetails: z
    .object({
      duration: optionalText,
      regionRestriction: z
        .object({
          allowed: z.array(z.string()).optional(),
          blocked: z.array(z.string()).optional(),
        })
        .optional(),
    })
    .optional(),
  status: z
    .object({ uploadStatus: optionalText, privacyStatus: optionalText })
    .optional(),
});
const thumbnailFields = 'thumbnails(high/url,medium/url,default/url)';
const args = (page: PageRequest) => ({
  maxResults: String(page.maxResults),
  ...(page.pageToken ? { pageToken: page.pageToken } : {}),
});
const thumb = (data: z.infer<typeof thumbnails>) =>
  youtubeThumbnail([data?.high, data?.medium, data?.default]);

function seconds(duration?: string) {
  if (!duration) return null;
  const match =
    /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/.exec(
      duration,
    );
  if (!match || !match.slice(1).some(Boolean)) return null;
  const value = Math.floor(
    Number(match[1] ?? 0) * 86400 +
      Number(match[2] ?? 0) * 3600 +
      Number(match[3] ?? 0) * 60 +
      Number(match[4] ?? 0),
  );
  return Number.isSafeInteger(value) ? value : null;
}
function availability(
  item: z.infer<typeof video>,
): VideoDetails['availability'] {
  const uploaded = item.status?.uploadStatus;
  if (uploaded && ['deleted', 'failed', 'rejected'].includes(uploaded))
    return 'unavailable';
  const region = item.contentDetails?.regionRestriction;
  if (region?.allowed?.length === 0) return 'unavailable';
  if (
    region?.allowed ||
    region?.blocked?.length ||
    uploaded !== 'processed' ||
    !item.status?.privacyStatus
  )
    return 'unknown';
  return 'available';
}
function retrySeconds(value: string | null) {
  if (!value) return undefined;
  const seconds = /^\d+$/.test(value)
    ? Number(value)
    : (Date.parse(value) - Date.now()) / 1000;
  return Number.isFinite(seconds) ? Math.max(1, Math.ceil(seconds)) : undefined;
}
export class YoutubeDataLibraryProvider implements ConnectedLibraryProvider {
  constructor(private readonly transport: typeof fetch = fetch) {}
  private async list<T>(
    resource:
      | 'channels'
      | 'playlists'
      | 'playlistItems'
      | 'videos'
      | 'search'
      | 'subscriptions',
    query: Record<string, string>,
    schema: z.ZodType<T>,
    context: ReadContext,
  ) {
    const url = new URL('https://www.googleapis.com/youtube/v3/' + resource);
    url.search = new URLSearchParams(query).toString();
    const signal = AbortSignal.any([context.signal, AbortSignal.timeout(5000)]);
    try {
      const response = await this.transport(url.href, {
        headers: { Authorization: 'Bearer ' + context.access },
        signal,
        redirect: 'error',
      });
      const data = await response.json().catch(() => {
        if (signal.aborted) throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
        return null;
      });
      if (!response.ok) {
        const reason = data?.error?.errors?.[0]?.reason;
        const retry = retrySeconds(response.headers.get('retry-after'));
        if (response.status === 401)
          throw new LinkError(401, 'YOUTUBE_ACCESS_REJECTED');
        if (
          response.status === 429 ||
          [
            'quotaExceeded',
            'dailyLimitExceeded',
            'rateLimitExceeded',
            'userRateLimitExceeded',
          ].includes(reason)
        )
          throw new LinkError(429, 'YOUTUBE_QUOTA', retry);
        if (reason === 'insufficientPermissions')
          throw new LinkError(403, 'MISSING_SCOPE');
        if (reason === 'invalidPageToken')
          throw new LinkError(409, 'INVALID_CURSOR');
        if (response.status === 404)
          throw new LinkError(404, 'PLAYLIST_NOT_FOUND');
        if (response.status === 403)
          throw new LinkError(403, 'YOUTUBE_FORBIDDEN');
        throw new LinkError(503, 'GOOGLE_UNAVAILABLE', retry);
      }
      const result = z
        .object({
          nextPageToken: z.string().min(1).max(2048).optional(),
          items: z.array(schema).max(50),
        })
        .safeParse(data);
      if (!result.success) throw new LinkError(503, 'GOOGLE_INVALID_RESPONSE');
      return result.data;
    } catch (e) {
      if (e instanceof LinkError) throw e;
      throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    }
  }
  async listChannels(context: ReadContext) {
    const page = await this.list(
      'channels',
      {
        part: 'snippet',
        mine: 'true',
        maxResults: '2',
        fields: 'nextPageToken,items(id,snippet/title)',
      },
      channel,
      context,
    );
    return {
      ...page,
      items: page.items.map((x) => ({ id: x.id, title: x.snippet.title })),
    };
  }
  async listPlaylists(context: ReadContext, page: PageRequest) {
    const result = await this.list(
      'playlists',
      {
        part: 'snippet,status,contentDetails',
        mine: 'true',
        ...args(page),
        fields:
          'nextPageToken,items(id,snippet(channelId,title,' +
          thumbnailFields +
          '),status/privacyStatus,contentDetails/itemCount)',
      },
      playlist,
      context,
    );
    return {
      ...result,
      items: result.items.map((x) => ({
        id: x.id,
        title: x.snippet.title,
        channelId: x.snippet.channelId,
        thumbnailUrl: thumb(x.snippet.thumbnails),
        visibility: x.status?.privacyStatus ?? null,
        itemCount: x.contentDetails?.itemCount ?? null,
      })),
    };
  }
  async subscribedMusicChannels(context: ReadContext, page: PageRequest) {
    const subscriptions = await this.list(
      'subscriptions',
      {
        part: 'snippet',
        mine: 'true',
        order: 'alphabetical',
        ...args(page),
        fields: 'nextPageToken,items(snippet/resourceId/channelId)',
      },
      z.object({
        snippet: z.object({ resourceId: z.object({ channelId: z.string() }) }),
      }),
      context,
    );
    const ids = [
      ...new Set(
        subscriptions.items
          .map((s) => s.snippet.resourceId.channelId)
          .filter((id) => channelIdFormat.test(id)),
      ),
    ];
    if (!ids.length)
      return { items: [], nextPageToken: subscriptions.nextPageToken };
    const details = await this.list(
      'channels',
      {
        part: 'snippet,topicDetails',
        id: ids.join(','),
        maxResults: String(ids.length),
        fields:
          'items(id,snippet(title,' +
          thumbnailFields +
          '),topicDetails(topicCategories,topicIds))',
      },
      z.object({
        id: z.string(),
        snippet: z.object({ title: z.string(), thumbnails }),
        topicDetails: z
          .object({
            topicCategories: z.array(z.string()).optional(),
            topicIds: z.array(z.string()).optional(),
          })
          .optional(),
      }),
      context,
    );
    const music = new Map(
      details.items
        .filter(
          (c) =>
            c.topicDetails?.topicIds?.some((id) => musicTopicIds.has(id)) ||
            c.topicDetails?.topicCategories?.some(
              (url) =>
                url.startsWith('https://en.wikipedia.org/wiki/') &&
                musicTopics.has(
                  url.slice('https://en.wikipedia.org/wiki/'.length),
                ),
            ),
        )
        .map((c) => [
          c.id,
          {
            kind: 'artist' as const,
            id: c.id,
            title: c.snippet.title,
            thumbnailUrl: thumb(c.snippet.thumbnails) ?? undefined,
          },
        ]),
    );
    return {
      items: ids.flatMap((id) => music.get(id) ?? []),
      nextPageToken: subscriptions.nextPageToken,
    };
  }
  async playlistInfo(context: ReadContext, id: string) {
    const result = await this.list(
      'playlists',
      {
        id,
        part: 'snippet,status',
        fields: 'items(id,snippet(channelId,title),status/privacyStatus)',
      },
      playlist,
      context,
    );
    const item = result.items.find((item) => item.id === id);
    return item
      ? {
          channelId: item.snippet.channelId,
          title: item.snippet.title,
          private: item.status?.privacyStatus === 'private',
        }
      : null;
  }
  async playlistOwner(context: ReadContext, id: string) {
    const result = await this.list(
      'playlists',
      { id, part: 'snippet', fields: 'items(id,snippet/channelId)' },
      z.object({
        id: identifier,
        snippet: z.object({ channelId: identifier }),
      }),
      context,
    );
    return result.items.find((x) => x.id === id)?.snippet.channelId ?? null;
  }
  async listPlaylistItems(
    context: ReadContext,
    playlistId: string,
    page: PageRequest,
  ) {
    const result = await this.list(
      'playlistItems',
      {
        part: 'snippet,contentDetails',
        playlistId,
        ...args(page),
        fields:
          'nextPageToken,items(id,snippet(position,title),contentDetails/videoId)',
      },
      entry,
      context,
    );
    return {
      ...result,
      items: result.items.map((x) => ({
        playlistItemId: x.id,
        position: x.snippet.position,
        title: x.snippet.title ?? null,
        videoId: youtubeSourceIdPattern.test(x.contentDetails?.videoId ?? '')
          ? x.contentDetails!.videoId!
          : null,
      })),
    };
  }
  async getVideos(context: ReadContext, ids: string[]) {
    if (!ids.length) return [];
    if (ids.length > 50) throw new RangeError('Too many video IDs');
    return (await this.videosPage(context, { id: ids.join(',') })).items;
  }
  listLikedVideos(context: ReadContext, page: PageRequest) {
    return this.videosPage(context, { myRating: 'like', ...args(page) });
  }
  async searchMusic(
    context: ReadContext,
    query: string,
    page: PageRequest,
    channelId?: string,
  ) {
    const result = await this.list(
      'search',
      {
        part: 'id',
        type: 'video',
        ...(query && { q: query }),
        ...(channelId && { channelId }),
        videoCategoryId: '10',
        fields: 'nextPageToken,items(id/videoId)',
        ...args(page),
      },
      z.object({
        id: z.object({ videoId: z.string().regex(youtubeSourceIdPattern) }),
      }),
      context,
    );
    const ids = result.items.map((item) => item.id.videoId);
    const videos = new Map(
      (await this.getVideos(context, ids)).map((v) => [v.id, v]),
    );
    return {
      items: ids.flatMap((id) => (videos.has(id) ? [videos.get(id)!] : [])),
      nextPageToken: result.nextPageToken,
    };
  }
  private async videosPage(
    context: ReadContext,
    query: Record<string, string>,
  ) {
    const result = await this.list(
      'videos',
      {
        part: 'snippet,contentDetails,status',
        ...query,
        fields:
          'nextPageToken,items(id,snippet(title,channelTitle,channelId,categoryId,description,' +
          thumbnailFields +
          '),contentDetails(duration,regionRestriction),status(uploadStatus,privacyStatus))',
      },
      video,
      context,
    );
    return {
      nextPageToken: result.nextPageToken,
      items: result.items.map((x) => ({
        id: x.id,
        title: x.snippet?.title ?? null,
        channelTitle: x.snippet?.channelTitle ?? null,
        artistId: /^UC[A-Za-z0-9_-]{22}$/.test(x.snippet?.channelId ?? '')
          ? x.snippet!.channelId
          : undefined,
        durationSeconds: seconds(x.contentDetails?.duration),
        thumbnailUrl: thumb(x.snippet?.thumbnails),
        availability: availability(x),
        // The public API has no song flag. Require the two attribution lines of an autogenerated recording.
        isMusicCategory: x.snippet?.categoryId === '10',
        isRecording:
          x.snippet?.categoryId === '10' &&
          /^Provided to YouTube by .+/im.test(x.snippet.description ?? '') &&
          /^Auto-generated by YouTube\.\s*$/im.test(
            x.snippet.description ?? '',
          ),
      })),
    };
  }
}
