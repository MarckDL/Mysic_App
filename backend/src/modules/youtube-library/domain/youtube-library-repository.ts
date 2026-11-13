import type {
  YoutubeConnectionStatus,
  YoutubeLibrarySnapshot,
} from './youtube-library.js';

export interface YoutubeLibraryView {
  likes: Array<
    YoutubeLibrarySnapshot['likes'][number] & {
      origin: 'youtube';
      readOnly: true;
    }
  >;
  playlists: Array<{
    id: string;
    externalId: string;
    title: string;
    thumbnailUrl: string | null;
    itemCount: number;
    origin: 'youtube';
    readOnly: true;
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
    origin: 'mysic';
    readOnly: false;
  } | null>;
  disconnect(ownerId: string): Promise<boolean>;
}
