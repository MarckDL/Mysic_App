import { Constants } from 'youtubei.js';
import { z } from 'zod';
import {
  LinkError,
  retryAfterSeconds,
} from '../../modules/integrations/youtube/domain.js';
import { LruCache } from '../cache/lru-cache.js';
import type { CatalogVideoKind } from '../../modules/integrations/youtube/library-domain.js';

const queuePanel = z.object({
  videoId: z.string(),
  unplayableText: z.unknown().optional(),
  title: z
    .object({
      simpleText: z.string().optional(),
      runs: z.array(z.object({ text: z.string() })).optional(),
    })
    .optional(),
  navigationEndpoint: z.object({
    watchEndpoint: z.object({
      videoId: z.string(),
      watchEndpointMusicSupportedConfigs: z.object({
        watchEndpointMusicConfig: z.object({ musicVideoType: z.string() }),
      }),
    }),
  }),
});
const panel = z.object({ playlistPanelVideoRenderer: queuePanel });
const wrapped = z.object({
  playlistPanelVideoWrapperRenderer: z.object({
    primaryRenderer: panel,
    counterpart: z.array(z.object({ counterpartRenderer: panel })).optional(),
  }),
});
const queue = z.object({
  queueDatas: z.array(z.object({ content: z.union([panel, wrapped]) })),
});

/** Check public IDs against Music in one request per page. A playable upload can
 * belong to a playlist even though it isn't an official recording. */
export class PublicMusicRecordings {
  private readonly known = new LruCache<CatalogVideoKind>(2048, 30 * 60_000);
  constructor(private readonly transport: typeof fetch) {}

  async classify(
    ids: string[],
    signal: AbortSignal,
  ): Promise<Map<string, CatalogVideoKind>> {
    const classified = new Map<string, CatalogVideoKind>();
    const pending = new Set<string>();
    for (const id of ids) {
      const cached = this.known.get(id);
      if (cached === undefined) pending.add(id);
      else classified.set(id, cached);
    }
    if (!pending.size) return classified;
    const client = Constants.CLIENTS.YTMUSIC;
    let response: Response;
    const requestSignal = AbortSignal.any([signal, AbortSignal.timeout(6500)]);
    try {
      response = await this.transport(
        'https://music.youtube.com/youtubei/v1/music/get_queue?prettyPrint=false',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'omit',
          redirect: 'error',
          signal: requestSignal,
          body: JSON.stringify({
            context: {
              client: {
                clientName: client.NAME,
                clientVersion: client.VERSION,
                hl: 'es',
              },
            },
            videoIds: [...pending],
          }),
        },
      );
    } catch {
      throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    }
    const retry = retryAfterSeconds(response.headers.get('retry-after'));
    if (response.status === 429)
      throw new LinkError(429, 'YOUTUBE_QUOTA', retry);
    if (!response.ok) throw new LinkError(503, 'GOOGLE_UNAVAILABLE', retry);
    let body: unknown;
    try {
      body = await response.json();
    } catch (error) {
      throw new LinkError(
        503,
        error instanceof SyntaxError && !requestSignal.aborted
          ? 'MUSIC_CATALOG_RESPONSE'
          : 'GOOGLE_UNAVAILABLE',
      );
    }
    const result = queue.safeParse(body);
    if (!result.success) throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');

    // Validate the whole batch before accepting or caching individual decisions.
    for (const { content } of result.data.queueDatas) {
      const panels =
        'playlistPanelVideoRenderer' in content
          ? [content]
          : [
              content.playlistPanelVideoWrapperRenderer.primaryRenderer,
              ...(
                content.playlistPanelVideoWrapperRenderer.counterpart ?? []
              ).map((other) => other.counterpartRenderer),
            ];
      for (const { playlistPanelVideoRenderer: video } of panels) {
        const endpoint = video.navigationEndpoint.watchEndpoint;
        if (video.videoId !== endpoint.videoId || !pending.has(video.videoId))
          continue;
        const type =
          endpoint.watchEndpointMusicSupportedConfigs.watchEndpointMusicConfig
            .musicVideoType;
        let kind: CatalogVideoKind = 'other';
        if (!video.unplayableText) {
          if (
            type === 'MUSIC_VIDEO_TYPE_ATV' ||
            type === 'MUSIC_VIDEO_TYPE_OMV'
          ) {
            kind = 'recording';
          } else if (
            type === 'MUSIC_VIDEO_TYPE_UGC' &&
            (video.title?.simpleText?.trim() ||
              video.title?.runs?.some((run) => run.text.trim()))
          ) {
            kind = 'musicUpload';
          }
        }
        this.known.set(video.videoId, kind);
        classified.set(video.videoId, kind);
      }
    }
    // A valid queue may omit unavailable IDs; try them again on a later refresh.
    for (const id of pending)
      if (!classified.has(id)) classified.set(id, 'other');
    return classified;
  }
}
