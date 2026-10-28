export interface Track {
  id: string;
  source: 'youtube' | 'demo';
  sourceId: string;
  title: string;
  artistName: string;
  durationSeconds: number | null;
  thumbnailUrl: string | null;
}

export type { PlaybackResult } from '../../playback/domain/playback-result.js';
import type { PlaybackResult } from '../../playback/domain/playback-result.js';

export interface MusicProvider {
  search(query: string, signal?: AbortSignal): Promise<Track[]>;
  getTrack(sourceId: string, signal?: AbortSignal): Promise<Track | null>;
  resolvePlayback(
    sourceId: string,
    signal?: AbortSignal,
  ): Promise<PlaybackResult>;
}

export class ProviderUnavailableError extends Error {}
export class ProviderTimeoutError extends Error {}
