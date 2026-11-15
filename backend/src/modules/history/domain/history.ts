import type { Track } from '../../catalog/domain/music-provider.js';
export interface HistoryInput {
  sessionId: string;
  catalogTrackId: string;
  startedAt: string;
  listenedMs: number;
  completed: boolean;
}
export interface HistoryRepository {
  owner(uid: string): Promise<string | null>;
  save(owner: string, input: HistoryInput, track: Track): Promise<void>;
  list(
    owner: string,
    limit: number,
    cursor?: { startedAt: string; id: string },
  ): Promise<
    {
      id: string;
      startedAt: string;
      listenedMs: number;
      completed: boolean;
      track: Track;
    }[]
  >;
}
export class HistoryConflict extends Error {}
export class HistoryInvalid extends Error {}
