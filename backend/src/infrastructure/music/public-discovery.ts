import type { DiscoveryRequest } from '../../modules/catalog/application/discovery-service.js';
import type {
  AccountPageResult,
  MusicItem,
} from '../../modules/integrations/youtube-music/provider.js';
import { ProviderUnavailableError } from '../../modules/catalog/domain/music-provider.js';
import { createYoutubeClient } from './youtube-provider.js';
import { LruCache } from '../cache/lru-cache.js';
import {
  albums,
  artists,
  array,
  artwork,
  group,
  heading,
  kindOf,
  object,
  order,
  row,
  searchGroups,
  shelves,
  text,
} from './discovery-mapper.js';

function page(items: MusicItem[], title?: string): AccountPageResult {
  return {
    items,
    nextCursor: null,
    excludedCount: 0,
    title: title || undefined,
  };
}
function topResult(raw: unknown): MusicItem | undefined {
  const data = object(raw);
  const kind = kindOf(data);
  if (kind) return row(data.song ?? data, kind, 'Mejor coincidencia');
  const endpoint = object(
    object(object(data.title).endpoint ?? data.on_tap).payload,
  );
  if (endpoint.videoId)
    return row(
      {
        id: endpoint.videoId,
        title: data.title,
        artist: text(data.subtitle).split('•')[1]?.trim(),
        thumbnail: data.thumbnail,
      },
      'song',
      'Mejor coincidencia',
    );
  const id = text(endpoint.browseId);
  if (!id) return;
  const browseKind = artists.test(id)
    ? 'artist'
    : albums.test(id)
      ? 'album'
      : id.startsWith('VL')
        ? 'playlist'
        : undefined;
  if (browseKind)
    return row(
      {
        id,
        title: data.title,
        subtitle: data.subtitle,
        thumbnail: data.thumbnail,
      },
      browseKind,
      'Mejor coincidencia',
    );
}
function publicTracks(
  values: unknown,
  defaults: { artist?: string; thumbnail?: unknown } = {},
  shelfTitle?: string,
) {
  return array(values).flatMap((value) => {
    const data = object(value);
    const kind = kindOf(value);
    if (data.item_type && kind !== 'song' && kind !== 'video') return [];
    const artist =
      text(data.artist) ||
      (!array(data.artists).length && !data.author
        ? defaults.artist
        : undefined);
    const item = row(
      {
        id: data.id ?? data.video_id,
        title: data.title,
        artist,
        artists: data.artists,
        authors: data.authors,
        author: data.author,
        artistId: data.artistId,
        duration: data.duration,
        durationSeconds: data.durationSeconds,
        thumbnail:
          artwork(data.thumbnail ?? data.thumbnails) ?? defaults.thumbnail,
      },
      kind === 'video' ? 'video' : 'song',
      shelfTitle,
    );
    return item ? [item] : [];
  });
}

interface RecommendationCatalog {
  getRelated(videoId: string): Promise<unknown>;
  getUpNext(videoId: string, automix: boolean): Promise<unknown>;
}

export async function relatedPage(
  music: RecommendationCatalog,
  seed: string,
  signal: AbortSignal,
) {
  let items: MusicItem[] = [];
  try {
    const result = await music.getRelated(seed);
    items = shelves(array(object(result).contents)).filter(
      (item) => item.kind !== 'track' || item.id !== seed,
    );
  } catch {
    signal.throwIfAborted();
  }
  if (!items.some((item) => item.kind === 'track')) {
    try {
      const radio = await music.getUpNext(seed, true);
      items.push(
        ...publicTracks(
          object(radio).contents,
          {},
          'Radio de la canción',
        ).filter((item) => item.id !== seed),
      );
    } catch (error) {
      signal.throwIfAborted();
      if (!items.length) throw error;
    }
  }
  if (!items.length) throw new ProviderUnavailableError();
  return page(items);
}

// Solo la inicialización del visitante público se reutiliza entre solicitudes.
// Cada consulta conserva su propio AbortSignal y la caché vive en memoria.
const bootstrap = new LruCache<ArrayBuffer>(2, 30 * 60_000);
const catalogCache = {
  cache_dir: '',
  get: async (key: string) => bootstrap.get(key),
  set: async (key: string, value: ArrayBuffer) => bootstrap.set(key, value),
  remove: async (key: string) => bootstrap.delete(key),
};
export async function loadYoutubeDiscovery(
  request: DiscoveryRequest,
  signal: AbortSignal,
) {
  const { music } = await createYoutubeClient(signal, 'es', catalogCache);
  if (request.view === 'explore') {
    const result = await music.getExplore(),
      items = shelves(result.sections);
    if (!items.length) throw new ProviderUnavailableError();
    return page(items);
  }
  if (request.view === 'search') {
    const result = await music.search(
      request.query,
      request.type === 'all' ? undefined : { type: request.type },
    );
    if (!Array.isArray(result.contents)) throw new ProviderUnavailableError();
    const groups = new Map<string, unknown[]>();
    let top: MusicItem | undefined;
    for (const shelf of result.contents) {
      if (shelf.type === 'MusicCardShelf') top ??= topResult(shelf);
      for (const item of array(object(shelf).contents)) {
        const kind = kindOf(item);
        if (!kind) continue;
        const contents = groups.get(kind) ?? [];
        contents.push(item);
        groups.set(kind, contents);
      }
    }
    // YouTube can return a different shelf for a typed video request. Its public
    // desktop endpoint also supports the Music video's specific search filter.
    if (
      request.type === 'video' &&
      !groups.get('video')?.length &&
      !result.message
    )
      throw new ProviderUnavailableError();
    return page(searchGroups(groups, request.type, top));
  }
  if (request.view === 'related') return relatedPage(music, request.id, signal);
  if (request.view === 'artist') {
    const artist = await music.getArtist(request.id);
    const items = shelves(artist.sections);
    if (!items.length) throw new ProviderUnavailableError();
    return page(items, text(artist.header?.title));
  }
  if (request.view === 'album') {
    const album = await music.getAlbum(request.id),
      title = text(album.header?.title);
    const h = object(album.header);
    return page(
      publicTracks(album.contents, {
        artist: text(h.strapline_text_one) || text(object(h.author).name),
        thumbnail:
          artwork(h.thumbnail ?? h.thumbnails) ?? artwork(album.background),
      }),
      title,
    );
  }
  const playlist = await music.getPlaylist(request.id);
  if (!Array.isArray(playlist.items)) throw new ProviderUnavailableError();
  // Preserve the provider's queue order, including intentional repeats.
  const items = publicTracks(playlist.items);
  let more = playlist;
  for (let i = 0; i < 19 && more.has_continuation && items.length < 1000; i++) {
    signal.throwIfAborted();
    more = await more.getContinuation();
    items.push(...publicTracks(more.items));
  }
  const header = object(playlist.header);
  return page(items, text(header.title ?? object(header.header).title));
}

const original = 'https://myslc.duckdns.org/api/youtube/';
export function originalDiscovery(transport: typeof fetch = fetch) {
  return async (
    request: DiscoveryRequest,
    signal: AbortSignal,
  ): Promise<AccountPageResult> => {
    async function get(path: string, params?: Record<string, string>) {
      const url = new URL(path, original);
      for (const [key, value] of Object.entries(params ?? {}))
        url.searchParams.set(key, value);
      const result = await transport(url, {
        headers: { Accept: 'application/json' },
        credentials: 'omit',
        redirect: 'error',
        signal,
      });
      if (!result.ok) throw new ProviderUnavailableError();
      return object(await result.json());
    }
    if (request.view === 'explore') {
      const items = shelves(array((await get('explore')).shelves));
      if (!items.length) throw new ProviderUnavailableError();
      return page(items);
    }
    if (request.view === 'search') {
      const args = { q: request.query, type: request.type };
      const data = await get('search', args);
      if (data.type !== request.type) throw new ProviderUnavailableError();
      if (request.type !== 'all') {
        if (!Array.isArray(data.items)) throw new ProviderUnavailableError();
        return page(group(data.items, request.type));
      }
      const groups = new Map<string, unknown[]>();
      for (const kind of order) groups.set(kind, array(data[kind + 's']));
      // The general desktop search omits its videos section. Preserve its songs,
      // artists and albums if the complementary video search is unavailable.
      if (!groups.get('video')?.length) {
        try {
          const videos = await get('search', { ...args, type: 'video' });
          if (videos.type === 'video') groups.set('video', array(videos.items));
        } catch {
          signal.throwIfAborted();
        }
      }
      return page(searchGroups(groups, 'all', topResult(data.top)));
    }
    // El escritorio reserva estas rutas para su propia sesión.
    if (request.view === 'related') throw new ProviderUnavailableError();
    const data = await get(request.view + '/' + request.id);
    if (request.view === 'artist') {
      if (!Array.isArray(data.topSongs) && !Array.isArray(data.shelves))
        throw new ProviderUnavailableError();
      return page(
        [
          ...publicTracks(
            data.topSongs,
            { artist: text(data.name), thumbnail: data.thumbnail },
            'Canciones',
          ),
          ...array(data.shelves).flatMap((raw) => {
            // Los estantes de artista del escritorio tipan cada disco como
            // álbum, single o EP para mostrar su formato de lanzamiento.
            const shelf = object(raw);
            return group(
              array(shelf.items),
              'album',
              text(shelf.title) ? heading(shelf.title) : 'Álbumes',
            );
          }),
        ],
        text(data.name),
      );
    }
    const values = request.view === 'album' ? data.tracks : data.songs;
    if (!Array.isArray(values)) throw new ProviderUnavailableError();
    return page(
      publicTracks(values, {
        artist: text(data.artist),
        thumbnail: data.thumbnail,
      }),
      text(data.title),
    );
  };
}
export const loadOriginalDiscovery = originalDiscovery();
