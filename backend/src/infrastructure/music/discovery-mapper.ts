import type { DiscoveryType } from '../../modules/catalog/application/discovery-service.js';
import type { MusicItem } from '../../modules/integrations/youtube-music/provider.js';
import {
  youtubeSourceIdPattern,
  youtubeThumbnail,
} from './youtube-normalizer.js';

type Data = Record<string, unknown>;
export const object = (value: unknown): Data =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Data)
    : {};
export const array = (value: unknown): unknown[] =>
  Array.isArray(value) ? value : [];
export function text(value: unknown): string {
  if (typeof value === 'string') return value.trim();
  const data = object(value);
  if (typeof data.text === 'string') return data.text.trim();
  return array(data.runs)
    .map((run) =>
      typeof object(run).text === 'string' ? object(run).text : '',
    )
    .join('')
    .trim();
}
export const albums = /^(?:MPLA)?MPRE[\w-]{1,140}$/;
export const artists = /^UC[\w-]{22}$/;
export const playlists = /^[\w-]{2,145}$/;
const groupLabels = {
  song: 'Canciones',
  video: 'Vídeos',
  artist: 'Artistas',
  album: 'Álbumes',
  playlist: 'Playlists',
};
type Kind = keyof typeof groupLabels;
export const order = ['song', 'video', 'artist', 'album'] as const;
export function heading(value: unknown) {
  const t = text(value);
  switch (t.toLowerCase()) {
    case 'new albums & singles':
      return 'Álbumes y sencillos nuevos';
    case 'trending':
      return 'Tendencias';
    case 'new music videos':
      return 'Vídeos musicales nuevos';
    case 'songs':
      return 'Canciones';
    case 'videos':
      return 'Vídeos';
    case 'albums':
      return 'Álbumes';
    case 'singles':
      return 'Sencillos';
    default:
      return t;
  }
}
export function kindOf(value: unknown): Kind | undefined {
  const item = object(value),
    kind = text(item.item_type ?? item.kind);
  return Object.hasOwn(groupLabels, kind) ? (kind as Kind) : undefined;
}
export function artwork(source: unknown) {
  const thumbnails =
    typeof source === 'string'
      ? [{ url: source }]
      : Array.isArray(source)
        ? source
        : object(source).contents;
  const byWidth = [...array(thumbnails)].sort(
    (a, b) => (Number(object(b).width) || 0) - (Number(object(a).width) || 0),
  );
  return youtubeThumbnail(byWidth) ?? undefined;
}

export function row(
  value: unknown,
  kind: Kind,
  shelfTitle?: string,
): MusicItem | undefined {
  const data = object(value),
    id = text(data.id ?? data.video_id),
    title = text(data.title) || text(data.name);
  if (!title || !id) return;
  const thumbnailUrl = artwork(data.thumbnail ?? data.thumbnails);
  const authors = array(data.artists ?? data.authors).map(object);
  if (!authors.length && data.author) authors.push(object(data.author));
  const artist =
    text(data.artist) ||
    text(data.author) ||
    authors
      .map((entry) => text(entry.name))
      .filter(Boolean)
      .join(', ');
  const meta = { title: title.slice(0, 500), thumbnailUrl, shelfTitle };
  const rawSubtitle = text(data.subtitle).replace(
    /^(?:album|álbum|artist|artista|playlist|lista de reproducción|single|sencillo|ep)(?:\s*[•·]\s*|$)/iu,
    '',
  );
  if (kind === 'artist') {
    const subtitle = rawSubtitle || text(data.subscribers);
    return artists.test(id)
      ? { kind, id, ...meta, subtitle: subtitle.slice(0, 300) || undefined }
      : undefined;
  }
  if (kind === 'album') {
    const yearText =
      typeof data.year === 'number' ? String(data.year) : text(data.year);
    const year = /\b(?:19|20)\d{2}\b/.exec(yearText || rawSubtitle)?.[0];
    const subtitle = artist
      ? [artist, year].filter(Boolean).join(' · ')
      : rawSubtitle || year;
    return albums.test(id)
      ? {
          kind,
          id: id.replace(/^MPLA/, ''),
          ...meta,
          subtitle: subtitle?.slice(0, 300) || undefined,
        }
      : undefined;
  }
  if (kind === 'playlist') {
    const playlist = id.replace(/^VL/, '');
    const subtitle = artist || rawSubtitle;
    return playlists.test(playlist)
      ? {
          kind,
          id: playlist,
          private: false,
          ...meta,
          subtitle: subtitle.slice(0, 300) || undefined,
        }
      : undefined;
  }
  if (!youtubeSourceIdPattern.test(id)) return;
  if (
    kind === 'video' &&
    /(?:^|\s)#(?:shorts|ytshorts|youtubeshorts)\b/iu.test(title)
  )
    return;
  const artistId = text(data.artistId ?? authors[0]?.channel_id);
  const duration = data.durationSeconds ?? object(data.duration).seconds;
  return {
    kind: 'track',
    id,
    ...meta,
    mediaType: kind,
    artist: artist || 'Artista desconocido',
    artistId: artists.test(artistId) ? artistId : undefined,
    durationSeconds:
      typeof duration === 'number' && Number.isFinite(duration) && duration > 0
        ? Math.min(86400, Math.floor(duration))
        : 0,
    playback: 'native',
  };
}

export function group(
  values: unknown[],
  kind: Kind,
  shelfTitle?: string,
  limit = Number.POSITIVE_INFINITY,
) {
  const items: MusicItem[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    const item = row(value, kind, shelfTitle);
    if (item && !seen.has(item.id)) {
      items.push(item);
      seen.add(item.id);
    }
    if (items.length >= limit) break;
  }
  return items;
}
export function searchGroups(
  groups: Map<string, unknown[]>,
  type: DiscoveryType,
  top?: MusicItem,
): MusicItem[] {
  if (type !== 'all') return group(groups.get(type) ?? [], type, undefined, 40);
  const items: MusicItem[] = top ? [top] : [];
  for (const kind of order)
    items.push(...group(groups.get(kind) ?? [], kind, groupLabels[kind], 8));
  return items;
}
export function shelves(sections: unknown[]) {
  const items: MusicItem[] = [];
  for (const value of sections) {
    const shelf = object(value);
    const title = heading(object(shelf.header).title ?? shelf.title);
    for (const element of array(shelf.contents ?? shelf.items)) {
      const kind = kindOf(element);
      if (!kind) continue;
      // The desktop payload uses 'song' for the tracks in its music-video rail.
      const media =
        kind === 'song' && /(?:music videos|v[ií]deos musicales)/iu.test(title)
          ? 'video'
          : kind;
      const item = row(element, media, title || undefined);
      if (item) items.push(item);
    }
  }
  return items;
}
