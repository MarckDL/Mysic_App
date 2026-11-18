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
    .object({ title: optionalText, channelTitle: optionalText, thumbnails })
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
    resource: 'channels' | 'playlists' | 'playlistItems' | 'videos',
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
    const result = await this.list(
      'videos',
      {
        part: 'snippet,contentDetails,status',
        id: ids.join(','),
        fields:
          'items(id,snippet(title,channelTitle,' +
          thumbnailFields +
          '),contentDetails(duration,regionRestriction),status(uploadStatus,privacyStatus))',
      },
      video,
      context,
    );
    return result.items.map((x) => ({
      id: x.id,
      title: x.snippet?.title ?? null,
      channelTitle: x.snippet?.channelTitle ?? null,
      durationSeconds: seconds(x.contentDetails?.duration),
      thumbnailUrl: thumb(x.snippet?.thumbnails),
      availability: availability(x),
    }));
  }
}
