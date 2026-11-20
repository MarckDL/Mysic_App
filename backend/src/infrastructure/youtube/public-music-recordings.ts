import { Constants } from 'youtubei.js';
import { z } from 'zod';
import { LruCache } from '../cache/lru-cache.js';

const queuePanel = z.object({
  videoId: z.string(),
  unplayableText: z.unknown().optional(),
  navigationEndpoint: z.object({
    watchEndpoint: z.object({
      videoId: z.string(),
      watchEndpointMusicSupportedConfigs: z.object({
        watchEndpointMusicConfig: z.object({ musicVideoType: z.string() }),
      }),
    }),
  }),
});
const panel = z.object({ playlistPanelVideoRenderer: z.unknown().optional() });
const content = panel.extend({
  playlistPanelVideoWrapperRenderer: z
    .object({
      primaryRenderer: panel.optional(),
      counterpart: z
        .array(z.object({ counterpartRenderer: panel.optional() }))
        .optional(),
    })
    .optional(),
});
const queue = z.object({
  queueDatas: z.array(z.object({ content: z.unknown().optional() })),
});

/** A channel upload's category is chosen by its uploader. Check ambiguous
 * public IDs against Music's own song/video types in one request per page. */
export class PublicMusicRecordings {
  private readonly known = new LruCache<boolean>(2048, 30 * 60_000);
  constructor(private readonly transport: typeof fetch) {}

  async confirm(ids: string[], signal: AbortSignal): Promise<Set<string>> {
    const verified = new Set<string>();
    const pending = new Set<string>();
    for (const id of ids) {
      const cached = this.known.get(id);
      if (cached === true) verified.add(id);
      if (cached === undefined) pending.add(id);
    }
    if (!pending.size) return verified;
    const client = Constants.CLIENTS.YTMUSIC;
    try {
      const response = await this.transport(
        'https://music.youtube.com/youtubei/v1/music/get_queue?prettyPrint=false',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'omit',
          redirect: 'error',
          signal: AbortSignal.any([signal, AbortSignal.timeout(6500)]),
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
      if (!response.ok) return verified;
      const result = queue.safeParse(await response.json());
      if (!result.success) return verified;
      for (const item of result.data.queueDatas) {
        const parsed = content.safeParse(item.content);
        if (!parsed.success) continue;
        const wrapper = parsed.data.playlistPanelVideoWrapperRenderer;
        const panels = [
          parsed.data,
          wrapper?.primaryRenderer,
          ...(wrapper?.counterpart ?? []).map(
            (other) => other.counterpartRenderer,
          ),
        ];
        for (const row of panels) {
          const candidate = queuePanel.safeParse(
            row?.playlistPanelVideoRenderer,
          );
          if (!candidate.success) continue;
          const video = candidate.data;
          const endpoint = video.navigationEndpoint.watchEndpoint;
          if (video.videoId !== endpoint.videoId || !pending.has(video.videoId))
            continue;
          const type =
            endpoint.watchEndpointMusicSupportedConfigs.watchEndpointMusicConfig
              .musicVideoType;
          const recording =
            !video.unplayableText &&
            (type === 'MUSIC_VIDEO_TYPE_ATV' ||
              type === 'MUSIC_VIDEO_TYPE_OMV');
          this.known.set(video.videoId, recording);
          if (recording) verified.add(video.videoId);
        }
      }
    } catch {
      // The caller checks cancellation. A temporary catalog failure leaves only
      // confirmed recordings visible and does not cache a negative verdict.
    }
    return verified;
  }
}
