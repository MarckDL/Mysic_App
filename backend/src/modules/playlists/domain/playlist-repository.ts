import type { Track } from '../../catalog/domain/music-provider.js';
import type {
  PlaylistDetail,
  PlaylistInput,
  PlaylistSummary,
  PlaylistUpdate,
} from './playlist.js';

export interface PlaylistRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  listOwned(ownerId: string): Promise<PlaylistSummary[]>;
  findAccessible(
    ownerId: string,
    playlistId: string,
  ): Promise<PlaylistDetail | null>;
  create(ownerId: string, input: PlaylistInput): Promise<PlaylistDetail>;
  updateOwned(
    ownerId: string,
    playlistId: string,
    input: PlaylistUpdate,
  ): Promise<PlaylistDetail | null>;
  deleteOwned(ownerId: string, playlistId: string): Promise<boolean>;
  addTrackOwned(
    ownerId: string,
    playlistId: string,
    track: Track,
    maximumItems: number,
  ): Promise<PlaylistDetail | null>;
  removeTrackOwned(
    ownerId: string,
    playlistId: string,
    itemId: string,
  ): Promise<PlaylistDetail | null>;
  reorderOwned(
    ownerId: string,
    playlistId: string,
    itemIds: readonly string[],
  ): Promise<PlaylistDetail | null>;
}
