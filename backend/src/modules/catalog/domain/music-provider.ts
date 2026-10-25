export interface Track {
  id: string;
  source: 'youtube';
  sourceId: string;
  title: string;
  artistName: string;
  durationSeconds: number | null;
  thumbnailUrl: string | null;
}

export interface PlaybackResult {
  mode: 'direct' | 'embedded' | 'unavailable';
  url?: string;
  expiresAt?: string;
  reason?: string;
}

export interface MusicProvider {
  search(query: string, signal?: AbortSignal): Promise<Track[]>;
  getTrack(sourceId: string, signal?: AbortSignal): Promise<Track | null>;
  resolvePlayback(sourceId: string): Promise<PlaybackResult>;
}

export class ProviderUnavailableError extends Error {}
export class ProviderTimeoutError extends Error {}
