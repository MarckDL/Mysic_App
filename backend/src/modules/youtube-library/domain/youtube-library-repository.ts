import type {
  YoutubeConnectionStatus,
  YoutubeLibrarySnapshot,
} from './youtube-library.js';

export interface YoutubeLibraryView {
  likes: YoutubeLibrarySnapshot['likes'];
  playlists: Array<{
    id: string;
    externalId: string;
    title: string;
    thumbnailUrl: string | null;
    itemCount: number;
  }>;
  subscriptions: YoutubeLibrarySnapshot['subscriptions'];
}

export interface YoutubeLibraryRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  status(ownerId: string): Promise<YoutubeConnectionStatus>;
  library(ownerId: string): Promise<YoutubeLibraryView>;
  replace(
    ownerId: string,
    snapshot: YoutubeLibrarySnapshot,
  ): Promise<YoutubeConnectionStatus>;
  duplicate(
    ownerId: string,
    remotePlaylistId: string,
  ): Promise<{
    id: string;
    name: string;
    description: string | null;
    visibility: 'private';
    trackCount: number;
    createdAt: string;
    updatedAt: string;
  } | null>;
  disconnect(ownerId: string): Promise<boolean>;
}
