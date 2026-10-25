import type { Track } from '../../modules/catalog/domain/music-provider.js';

export const youtubeSourceIdPattern = /^[A-Za-z0-9_-]{11}$/;

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function text(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, maxLength) : null;
}

function thumbnail(value: unknown): string | null {
  if (!Array.isArray(value)) return null;
  for (const item of value) {
    const candidate = text(record(item).url, 2048);
    if (!candidate) continue;
    try {
      const url = new URL(candidate);
      // Solo imágenes del proveedor, sin URLs arbitrarias suministradas al móvil.
      if (
        url.protocol === 'https:' &&
        !url.username &&
        !url.password &&
        (url.hostname === 'ytimg.com' ||
          url.hostname.endsWith('.ytimg.com') ||
          url.hostname === 'googleusercontent.com' ||
          url.hostname.endsWith('.googleusercontent.com') ||
          url.hostname === 'ggpht.com' ||
          url.hostname.endsWith('.ggpht.com'))
      )
        return candidate;
    } catch {
      /* Miniatura inválida: usar fallback. */
    }
  }
  return null;
}

function duration(value: unknown): number | null {
  return typeof value === 'number' &&
    Number.isSafeInteger(Math.floor(value)) &&
    value >= 1
    ? Math.floor(value)
    : null;
}

function track(
  sourceId: unknown,
  titleValue: unknown,
  artistValue: unknown,
  seconds: unknown,
  thumbnails: unknown,
): Track | null {
  if (typeof sourceId !== 'string' || !youtubeSourceIdPattern.test(sourceId))
    return null;
  const title = text(titleValue, 500);
  // No convertir un cambio de formato externo en una canción inventada.
  if (!title) return null;
  return {
    id: `youtube:${sourceId}`,
    source: 'youtube',
    sourceId,
    title,
    artistName: text(artistValue, 255) ?? 'Artista no disponible',
    durationSeconds: duration(seconds),
    thumbnailUrl: thumbnail(thumbnails),
  };
}

export function normalizeYoutubeSong(value: unknown): Track | null {
  const item = record(value);
  if (item.item_type !== 'song') return null;
  const artists = Array.isArray(item.artists)
    ? item.artists
        .map((artist) => text(record(artist).name, 255))
        .filter(Boolean)
        .join(', ')
    : null;
  return track(
    item.id,
    item.title,
    artists,
    record(item.duration).seconds,
    item.thumbnails,
  );
}

export function normalizeYoutubeDetail(value: unknown): Track | null {
  const info = record(value);
  return track(
    info.id,
    info.title,
    info.author,
    info.is_live ? null : info.duration,
    info.thumbnail,
  );
}

export function normalizeYoutubeSongs(
  items: readonly unknown[],
  limit = 20,
): Track[] {
  if (limit <= 0) return [];
  const seen = new Set<string>();
  const tracks: Track[] = [];
  for (const item of items) {
    const normalized = normalizeYoutubeSong(item);
    if (!normalized || seen.has(normalized.id)) continue;
    seen.add(normalized.id);
    tracks.push(normalized);
    if (tracks.length >= limit) break;
  }
  return tracks;
}
