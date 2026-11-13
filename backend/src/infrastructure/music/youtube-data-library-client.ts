import type { Track } from '../../modules/catalog/domain/music-provider.js';
import type { YoutubeLibraryClient } from '../../modules/youtube-library/domain/youtube-library-client.js';
import {
  YoutubeLibraryQuotaError,
  YoutubeLibraryUnauthorizedError,
  YoutubeLibraryUnavailableError,
  type YoutubeLibrarySnapshot,
} from '../../modules/youtube-library/domain/youtube-library.js';

const api = 'https://www.googleapis.com/youtube/v3';
const pageSize = 50;

interface ApiPage<T> {
  items?: T[];
  nextPageToken?: string;
}

interface ThumbnailSet {
  default?: { url?: string };
  medium?: { url?: string };
  high?: { url?: string };
}

function thumbnail(value?: ThumbnailSet) {
  return value?.high?.url ?? value?.medium?.url ?? value?.default?.url ?? null;
}

function seconds(value?: string): number | null {
  if (!value) return null;
  const match = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(value);
  if (!match) return null;
  return (
    Number(match[1] ?? 0) * 3600 +
    Number(match[2] ?? 0) * 60 +
    Number(match[3] ?? 0)
  );
}

function track(item: {
  id?: string;
  snippet?: {
    title?: string;
    channelTitle?: string;
    thumbnails?: ThumbnailSet;
  };
  contentDetails?: { duration?: string };
}): Track | null {
  if (!item.id || !/^[A-Za-z0-9_-]{11}$/.test(item.id)) return null;
  return {
    id: `youtube:${item.id}`,
    source: 'youtube',
    sourceId: item.id,
    title: item.snippet?.title?.trim() || 'Sin título',
    artistName: item.snippet?.channelTitle?.trim() || 'YouTube',
    durationSeconds: seconds(item.contentDetails?.duration),
    thumbnailUrl: thumbnail(item.snippet?.thumbnails),
  };
}

export class YoutubeDataLibraryClient implements YoutubeLibraryClient {
  constructor(private readonly timeoutMs = 15_000) {}

  private async request<T>(
    path: string,
    token: string,
    parameters: Record<string, string>,
  ) {
    const url = new URL(`${api}/${path}`);
    for (const [key, value] of Object.entries(parameters))
      url.searchParams.set(key, value);
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      signal: AbortSignal.timeout(this.timeoutMs),
    }).catch((cause) => {
      throw new YoutubeLibraryUnavailableError('YouTube no respondió', {
        cause,
      });
    });
    if (response.status === 401) throw new YoutubeLibraryUnauthorizedError();
    if (response.status === 403 || response.status === 429)
      throw new YoutubeLibraryQuotaError();
    if (!response.ok)
      throw new YoutubeLibraryUnavailableError(
        `YouTube respondió ${response.status}`,
      );
    return (await response.json()) as T;
  }

  private async pages<T>(
    path: string,
    token: string,
    parameters: Record<string, string>,
    limit: number,
  ) {
    const values: T[] = [];
    let pageToken: string | undefined;
    while (values.length < limit) {
      const page = await this.request<ApiPage<T>>(path, token, {
        ...parameters,
        maxResults: String(Math.min(pageSize, limit - values.length)),
        ...(pageToken ? { pageToken } : {}),
      });
      values.push(...(page.items ?? []));
      pageToken = page.nextPageToken;
      if (!pageToken) break;
    }
    return values.slice(0, limit);
  }

  private async tracks(token: string, videoIds: string[]) {
    const unique = [
      ...new Set(videoIds.filter((id) => /^[A-Za-z0-9_-]{11}$/.test(id))),
    ];
    const values: Track[] = [];
    for (let index = 0; index < unique.length; index += pageSize) {
      const page = await this.request<ApiPage<Parameters<typeof track>[0]>>(
        'videos',
        token,
        {
          part: 'snippet,contentDetails',
          id: unique.slice(index, index + pageSize).join(','),
        },
      );
      values.push(
        ...(page.items ?? [])
          .map(track)
          .filter((value): value is Track => value !== null),
      );
    }
    return values;
  }

  async fetchSnapshot(accessToken: string): Promise<YoutubeLibrarySnapshot> {
    const channels = await this.request<
      ApiPage<{
        id?: string;
        snippet?: { title?: string; thumbnails?: ThumbnailSet };
        contentDetails?: { relatedPlaylists?: { likes?: string } };
      }>
    >('channels', accessToken, {
      part: 'snippet,contentDetails',
      mine: 'true',
    });
    const channel = channels.items?.[0];
    if (!channel?.id) throw new YoutubeLibraryUnauthorizedError();

    const playlists = await this.pages<{
      id?: string;
      snippet?: { title?: string; thumbnails?: ThumbnailSet };
    }>('playlists', accessToken, { part: 'snippet', mine: 'true' }, 25);

    const importedPlaylists: YoutubeLibrarySnapshot['playlists'] = [];
    for (const playlist of playlists) {
      if (!playlist.id) continue;
      const items = await this.pages<{
        id?: string;
        snippet?: { position?: number; resourceId?: { videoId?: string } };
      }>(
        'playlistItems',
        accessToken,
        { part: 'snippet', playlistId: playlist.id },
        200,
      );
      const videoIds = items.map(
        (item) => item.snippet?.resourceId?.videoId ?? '',
      );
      const details = await this.tracks(accessToken, videoIds);
      const byId = new Map(details.map((value) => [value.sourceId, value]));
      importedPlaylists.push({
        externalId: playlist.id,
        title: playlist.snippet?.title?.trim() || 'Playlist de YouTube',
        thumbnailUrl: thumbnail(playlist.snippet?.thumbnails),
        tracks: items.flatMap((item, index) => {
          const video = byId.get(item.snippet?.resourceId?.videoId ?? '');
          return item.id && video
            ? [
                {
                  ...video,
                  externalItemId: item.id,
                  position: item.snippet?.position ?? index,
                },
              ]
            : [];
        }),
      });
    }

    const likedVideos = await this.pages<Parameters<typeof track>[0]>(
      'videos',
      accessToken,
      { part: 'snippet,contentDetails', myRating: 'like' },
      500,
    );
    const likes = likedVideos
      .map(track)
      .filter((value): value is Track => value !== null);
    const subscriptions = await this.pages<{
      snippet?: {
        title?: string;
        resourceId?: { channelId?: string };
        thumbnails?: ThumbnailSet;
      };
    }>('subscriptions', accessToken, { part: 'snippet', mine: 'true' }, 200);

    return {
      channel: {
        id: channel.id,
        displayName: channel.snippet?.title?.trim() || 'YouTube',
        avatarUrl: thumbnail(channel.snippet?.thumbnails),
      },
      playlists: importedPlaylists,
      likes,
      subscriptions: subscriptions.flatMap((item) => {
        const channelId = item.snippet?.resourceId?.channelId;
        return channelId
          ? [
              {
                channelId,
                title: item.snippet?.title?.trim() || 'Canal de YouTube',
                thumbnailUrl: thumbnail(item.snippet?.thumbnails),
              },
            ]
          : [];
      }),
    };
  }
}
