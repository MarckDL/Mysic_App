import { YoutubeDataLibraryProvider } from './youtube-data-library-provider.js';
import { Constants } from 'youtubei.js';
import { LinkError } from '../../modules/integrations/youtube/domain.js';
import type { ReadContext } from '../../modules/integrations/youtube/library-domain.js';
import type {
  MusicItem,
  MusicPageRequest,
} from '../../modules/integrations/youtube-music/provider.js';

type Json = Record<string, unknown>;
const obj = (value: unknown): Json =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Json)
    : {};
const list = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);
const str = (value: unknown): string =>
  typeof value === 'string' ? value : '';
function at(value: unknown, ...keys: string[]): Json {
  return keys.reduce((node, key) => obj(node[key]), obj(value));
}
function label(value: unknown): string {
  const data = obj(value);
  return (
    str(data.simpleText) ||
    list(data.runs)
      .map((run) => str(obj(run).text))
      .join('')
  );
}
function browse(endpoint: Json) {
  return obj(endpoint.browseEndpoint);
}
function pageType(endpoint: Json) {
  return str(
    at(
      browse(endpoint),
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig',
    ).pageType,
  );
}
const videoId = /^[\w-]{11}$/;
const resourceId = /^[\w-]{1,150}$/;
export type AccountSurface = Pick<
  MusicPageRequest,
  'surface' | 'playlistId' | 'artistId' | 'query'
>;
export interface AccountMusicPage {
  items: MusicItem[];
  next?: string;
  title?: string;
  excluded: number;
}
export interface MusicAccountCatalog {
  verify(ctx: ReadContext): Promise<'privatePlaylists' | 'personalHome' | void>;
  verifyCollection?(
    ctx: ReadContext,
    surface: 'liked' | 'albums' | 'artists',
  ): Promise<void>;
  read(
    ctx: ReadContext,
    request: AccountSurface,
    continuation?: string,
  ): Promise<AccountMusicPage>;
}

function card(
  value: Json,
  surface: MusicPageRequest['surface'],
  musicVideos: ReadonlySet<string>,
  unclassified?: Set<string>,
): MusicItem | undefined {
  const columns = list(value.flexColumns).map((col) =>
    at(col, 'musicResponsiveListItemFlexColumnRenderer', 'text'),
  );
  const titleText = value.title ?? columns[0];
  const title = label(titleText).trim();
  if (!title || str(value.musicItemRendererDisplayPolicy).includes('GREY_OUT'))
    return;
  const titleEndpoint = at(list(obj(titleText).runs)[0], 'navigationEndpoint');
  const root = obj(value.navigationEndpoint);
  const thumb = at(
    value.thumbnail ?? value.thumbnailRenderer,
    'musicThumbnailRenderer',
    'thumbnail',
  );
  const thumbnailUrl = list(thumb.thumbnails)
    .map((t) => str(obj(t).url))
    .filter((url) => /^https:\/\//.test(url))
    .at(-1);
  const endpoint = root.browseEndpoint ? root : titleEndpoint;
  const type = pageType(endpoint);
  const id = str(browse(endpoint).browseId);
  if (type.includes('PODCAST') || type.includes('NON_MUSIC')) return;
  if (id && resourceId.test(id)) {
    if (
      (type === 'MUSIC_PAGE_TYPE_ALBUM' || (!type && surface === 'albums')) &&
      /^(?:MPLA)?MPRE/.test(id)
    )
      return {
        kind: 'album',
        id: id.replace(/^MPLA/, ''),
        title,
        thumbnailUrl,
      };
    // Music shelves can send the playlist ID directly or its VL browse ID.
    const playlistId = id.replace(/^VL/, '');
    if (
      playlistId &&
      ((type === 'MUSIC_PAGE_TYPE_PLAYLIST' &&
        (id.startsWith('VL') || /^(?:PL|RD|OLAK5uy_)[\w-]+$/.test(id))) ||
        (!type && surface === 'playlists' && id.startsWith('VL')))
    )
      return {
        kind: 'playlist',
        id: playlistId,
        title,
        private: false,
        thumbnailUrl,
      };
    if (type === 'MUSIC_PAGE_TYPE_ARTIST' && /^UC[\w-]{22}$/.test(id))
      return { kind: 'artist', id, title, thumbnailUrl };
    return;
  }
  const overlay = at(
    value.overlay ?? value.thumbnailOverlay,
    'musicItemThumbnailOverlayRenderer',
    'content',
    'musicPlayButtonRenderer',
    'playNavigationEndpoint',
  );
  const endpoints = [titleEndpoint, root, overlay];
  if (endpoints.some((endpoint) => endpoint.reelWatchEndpoint)) return;
  const watch = endpoints.map((endpoint) => obj(endpoint.watchEndpoint));
  const trackId =
    str(obj(value.playlistItemData).videoId) ||
    watch.map((w) => str(w.videoId)).find(Boolean) ||
    '';
  if (!videoId.test(trackId)) return;
  const kinds = watch
    .filter((w) => !w.videoId || w.videoId === trackId)
    .map((w) =>
      str(
        at(w, 'watchEndpointMusicSupportedConfigs', 'watchEndpointMusicConfig')
          .musicVideoType,
      ),
    )
    .filter(Boolean);
  const detailRuns = [...columns.slice(1), obj(value.subtitle)]
    .flatMap((column) => list(column.runs))
    .map(obj);
  const userVideo = kinds.includes('MUSIC_VIDEO_TYPE_UGC');
  if (userVideo) unclassified?.add(trackId);
  const album = detailRuns.some(
    (run) => pageType(obj(run.navigationEndpoint)) === 'MUSIC_PAGE_TYPE_ALBUM',
  );
  if (!(
    kinds.includes('MUSIC_VIDEO_TYPE_ATV') ||
    kinds.includes('MUSIC_VIDEO_TYPE_OMV') ||
    (userVideo && musicVideos.has(trackId)) ||
    (!kinds.length && (album || surface === 'album'))
  ))
    return;
  const artists = detailRuns.filter((run) =>
    /^UC[\w-]{22}$/.test(str(browse(obj(run.navigationEndpoint)).browseId)),
  );
  const durationText = [
    ...list(value.fixedColumns).map((c) =>
      label(at(c, 'musicResponsiveListItemFixedColumnRenderer', 'text')),
    ),
    ...detailRuns.map((r) => str(r.text)),
  ].find((s) => /^\d{1,3}(?::\d{2}){1,2}$/.test(s));
  const artist =
    artists
      .map((r) => str(r.text))
      .filter(Boolean)
      .join(', ') ||
    label(columns[1]).split(/\s[•·]\s/)[0] ||
    '';
  return {
    kind: 'track',
    id: trackId,
    title,
    artist,
    artistId: artists.length
      ? str(browse(obj(artists[0]!.navigationEndpoint)).browseId)
      : undefined,
    thumbnailUrl,
    durationSeconds:
      durationText?.split(':').reduce((n, s) => n * 60 + Number(s), 0) ?? 0,
    playback: 'native',
    entryId: str(obj(value.playlistItemData).playlistSetVideoId) || undefined,
  };
}

const only: Partial<Record<MusicPageRequest['surface'], MusicItem['kind']>> = {
  songs: 'track',
  liked: 'track',
  playlist: 'track',
  album: 'track',
  search: 'track',
  artist: 'track',
  playlists: 'playlist',
  albums: 'album',
  artists: 'artist',
};
export function parseMusicAccountPage(
  raw: unknown,
  surface: MusicPageRequest['surface'],
  musicVideos: ReadonlySet<string> = new Set(),
  unclassified?: Set<string>,
): AccountMusicPage {
  const data = obj(raw);
  const ctx = obj(data.responseContext);
  if (
    at(ctx, 'mainAppWebResponseContext').loggedOut === true ||
    list(ctx.serviceTrackingParams).some((group) =>
      list(obj(group).params).some(
        (p) => obj(p).key === 'logged_in' && obj(p).value === '0',
      ),
    )
  )
    throw new LinkError(403, 'MUSIC_ACCESS_DENIED');
  const page: AccountMusicPage = { items: [], excluded: 0 };
  const detail = surface === 'playlist' || surface === 'album';
  let primary = false;
  function visit(value: unknown, shelfTitle?: string): void {
    if (Array.isArray(value)) {
      value.forEach((item) => visit(item, shelfTitle));
      return;
    }
    const node = obj(value);
    for (const [key, child] of Object.entries(node)) {
      const r = obj(child);
      if (key === 'tabRenderer') {
        if (r.selected !== false) visit(r.content, shelfTitle);
        continue;
      }
      if (key === 'tabs') {
        const tabs = list(child);
        const selected = tabs.filter(
          (t) => at(t, 'tabRenderer').selected === true,
        );
        visit(selected.length ? selected : tabs.slice(0, 1), shelfTitle);
        continue;
      }
      if (
        [
          'musicResponsiveHeaderRenderer',
          'musicDetailHeaderRenderer',
          'musicImmersiveHeaderRenderer',
        ].includes(key)
      ) {
        page.title ||= label(r.title);
        continue;
      }
      if (key === 'musicEditablePlaylistDetailHeaderRenderer') {
        visit(r.header);
        continue;
      }
      if (
        key === 'musicCarouselShelfRenderer' ||
        (surface === 'home' && key === 'musicShelfRenderer')
      ) {
        // Shelf continuations are local to the shelf. Only the outer feed advances Home.
        if (!detail) {
          const heading =
            surface === 'home'
              ? label(
                  at(r, 'header', 'musicCarouselShelfBasicHeaderRenderer')
                    .title ?? r.title,
                ).trim()
              : '';
          visit(
            list(r.contents).filter(
              (item) => !obj(item).continuationItemRenderer,
            ),
            heading || shelfTitle,
          );
        }
        continue;
      }
      if (
        surface === 'playlist' &&
        (key === 'musicShelfRenderer' || key === 'musicShelfContinuation')
      )
        continue;
      if (
        key === 'musicResponsiveListItemRenderer' ||
        key === 'musicTwoRowItemRenderer'
      ) {
        const item = card(r, surface, musicVideos, unclassified);
        if (
          item &&
          (!only[surface] || item.kind === only[surface]) &&
          !(surface === 'playlists' && ['LM', 'SE'].includes(item.id))
        )
          page.items.push(shelfTitle ? { ...item, shelfTitle } : item);
        else page.excluded++;
        continue;
      }
      if (key === 'continuationItemRenderer') {
        page.next ||=
          str(at(r, 'continuationEndpoint', 'continuationCommand').token) ||
          undefined;
        continue;
      }
      if (key === 'continuations') {
        page.next ||= list(child)
          .map(
            (v) =>
              str(at(v, 'nextContinuationData').continuation) ||
              str(at(v, 'nextRadioContinuationData').continuation),
          )
          .find(Boolean);
        continue;
      }
      if (
        [
          'contents',
          'content',
          'items',
          'tabs',
          'sectionListRenderer',
          'singleColumnBrowseResultsRenderer',
          'twoColumnBrowseResultsRenderer',
          'tabbedSearchResultsRenderer',
          'secondaryContents',
          'gridRenderer',
          'musicShelfRenderer',
          'musicShelfContinuation',
          'gridContinuation',
          'musicPlaylistShelfRenderer',
          'musicPlaylistShelfContinuation',
          'sectionListContinuation',
          'musicCarouselShelfRenderer',
          'onResponseReceivedActions',
          'onResponseReceivedCommands',
          'appendContinuationItemsAction',
          'reloadContinuationItemsCommand',
          'continuationItems',
          'continuationContents',
          'header',
          'musicEditablePlaylistDetailHeaderRenderer',
        ].includes(key)
      ) {
        primary = true;
        visit(child, shelfTitle);
      }
    }
  }
  visit(data);
  if (!primary) throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');
  return page;
}
const pages: Partial<Record<MusicPageRequest['surface'], string>> = {
  home: 'FEmusic_home',
  liked: 'VLLM',
  songs: 'FEmusic_liked_videos',
  playlists: 'FEmusic_liked_playlists',
  albums: 'FEmusic_liked_albums',
  artists: 'FEmusic_library_corpus_artists',
};
export class OAuthMusicCatalog implements MusicAccountCatalog {
  constructor(
    private readonly transport: typeof fetch = fetch,
    private readonly videoDetails: Pick<
      YoutubeDataLibraryProvider,
      'getVideos'
    > = new YoutubeDataLibraryProvider(transport, { verifyMusic: true }),
  ) {}
  // Home and the private playlists shelf can be granted independently.
  async verify(ctx: ReadContext) {
    const probe = async (surface: 'playlists' | 'home') => {
      try {
        await this.verifyCollection(ctx, surface);
        return 'granted';
      } catch (error) {
        if (!(error instanceof LinkError)) throw error;
        if (
          error.code === 'MUSIC_ACCESS_DENIED' ||
          error.code === 'MUSIC_PLAYLIST_NOT_FOUND'
        )
          return 'denied';
        if (error.code === 'MUSIC_CATALOG_RESPONSE') return 'unknown';
        throw error;
      }
    };
    const [playlists, home] = await Promise.allSettled([
      probe('playlists'),
      probe('home'),
    ]);
    const playlistAccess =
      playlists.status === 'fulfilled' && playlists.value === 'granted';
    const homeAccess = home.status === 'fulfilled' && home.value === 'granted';
    if (playlistAccess && homeAccess) return;
    if (homeAccess) return 'personalHome' as const;
    if (playlistAccess) return 'privatePlaylists' as const;
    if (playlists.status === 'rejected') throw playlists.reason;
    if (home.status === 'rejected') throw home.reason;
    if (playlists.value === 'unknown' || home.value === 'unknown') {
      throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');
    }
    throw new LinkError(403, 'MUSIC_ACCESS_DENIED');
  }
  private signedIn(data: unknown) {
    const context = obj(obj(data).responseContext);
    return (
      at(context, 'mainAppWebResponseContext').loggedOut === false ||
      list(context.serviceTrackingParams).some((g) =>
        list(obj(g).params).some(
          (p) => obj(p).key === 'logged_in' && obj(p).value === '1',
        ),
      )
    );
  }
  async verifyCollection(
    ctx: ReadContext,
    surface: 'home' | 'playlists' | 'liked' | 'albums' | 'artists',
  ) {
    const data = await this.request(ctx, { surface });
    const page = parseMusicAccountPage(data, surface);
    if (!this.signedIn(data) || (surface === 'home' && !page.items.length))
      throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');
  }
  private async request(
    ctx: ReadContext,
    request: AccountSurface,
    continuation?: string,
  ): Promise<unknown> {
    const search = request.surface === 'search';
    const id =
      request.surface === 'playlist' && request.playlistId
        ? `VL${request.playlistId}`
        : request.surface === 'album'
          ? request.playlistId
          : request.surface === 'artist'
            ? request.artistId
            : pages[request.surface];
    if (!search && (!id || !resourceId.test(id)))
      throw new LinkError(400, 'INVALID_REQUEST');
    const url = new URL(
      'https://music.youtube.com/youtubei/v1/' + (search ? 'search' : 'browse'),
    );
    url.searchParams.set('prettyPrint', 'false');
    const body = continuation
      ? { continuation }
      : search
        ? { query: request.query, params: 'EgWKAQIIAQ%3D%3D' }
        : { browseId: id };
    let response: Response;
    try {
      response = await this.transport(url, {
        method: 'POST',
        redirect: 'error',
        signal: ctx.signal,
        headers: {
          'Content-Type': 'application/json',
          Origin: url.origin,
          'X-Goog-Request-Time': String(Math.floor(Date.now() / 1000)),
          Authorization: `Bearer ${ctx.access}`,
        },
        body: JSON.stringify({
          context: {
            user: {},
            client: {
              clientName: Constants.CLIENTS.YTMUSIC.NAME,
              clientVersion: Constants.CLIENTS.YTMUSIC.VERSION,
              hl: 'es',
            },
          },
          ...body,
        }),
      });
    } catch {
      throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    }
    if (response.status === 401)
      throw new LinkError(403, 'MUSIC_ACCESS_DENIED');
    if (response.status === 403) {
      const error = obj(obj(await response.json().catch(() => null)).error);
      const reasons = [...list(error.errors), ...list(error.details)].map(
        (detail) => str(obj(detail).reason),
      );
      if (
        error.status === 'RESOURCE_EXHAUSTED' ||
        reasons.some((reason) =>
          [
            'quotaExceeded',
            'dailyLimitExceeded',
            'rateLimitExceeded',
            'userRateLimitExceeded',
            'RATE_LIMIT_EXCEEDED',
            'QUOTA_EXCEEDED',
          ].includes(reason),
        )
      )
        throw new LinkError(429, 'YOUTUBE_QUOTA');
      throw new LinkError(403, 'MUSIC_ACCESS_DENIED');
    }
    if (response.status === 404)
      throw new LinkError(404, 'MUSIC_PLAYLIST_NOT_FOUND');
    if (response.status === 429) throw new LinkError(429, 'TOO_MANY_REQUESTS');
    if (!response.ok) throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    return response.json().catch(() => {
      throw new LinkError(503, 'MUSIC_CATALOG_RESPONSE');
    });
  }
  async read(ctx: ReadContext, request: AccountSurface, continuation?: string) {
    const json = await this.request(ctx, request, continuation);
    if (request.surface === 'home' && !continuation && !this.signedIn(json)) {
      // Verification is cached; never serve an anonymous Home as this user's feed.
      throw new LinkError(403, 'MUSIC_ACCESS_DENIED');
    }
    const candidates = new Set<string>();
    const confirmed = new Set<string>();
    const first = parseMusicAccountPage(
      json,
      request.surface,
      confirmed,
      candidates,
    );
    if (!candidates.size) return first;
    const ids = [...candidates];
    for (let start = 0; start < ids.length; start += 50) {
      const details = await this.videoDetails.getVideos(
        ctx,
        ids.slice(start, start + 50),
      );
      for (const video of details)
        if (video.isRecording && video.availability === 'available')
          confirmed.add(video.id);
    }
    return confirmed.size
      ? parseMusicAccountPage(json, request.surface, confirmed)
      : first;
  }
}
