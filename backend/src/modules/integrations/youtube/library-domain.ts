export interface ConnectedPlaylist {
  id: string;
  title: string;
  itemCount: number | null;
  thumbnailUrl: string | null;
  visibility: 'public' | 'unlisted' | 'private' | null;
}
export interface PlaylistEntry {
  playlistItemId: string;
  position: number;
  videoId: string | null;
  title: string | null;
}
export type CatalogVideoKind = 'recording' | 'musicUpload' | 'other';
export interface VideoDetails {
  catalogKind?: CatalogVideoKind;
  isRecording?: boolean;
  isMusicCategory?: boolean;
  artistId?: string;
  id: string;
  title: string | null;
  channelTitle: string | null;
  durationSeconds: number | null;
  thumbnailUrl: string | null;
  availability: 'available' | 'unavailable' | 'unknown';
}
export function isLibraryTrack(
  video: VideoDetails | undefined,
  includeUploads: boolean,
): video is VideoDetails {
  if (!video || video.availability === 'unavailable') return false;
  if (video.catalogKind) {
    return (
      video.catalogKind === 'recording' ||
      (includeUploads && video.catalogKind === 'musicUpload')
    );
  }
  return video.isRecording === true && video.availability === 'available';
}
export interface GooglePage<T> {
  items: T[];
  nextPageToken?: string;
}
export interface ReadContext {
  access: string;
  signal: AbortSignal;
}
export interface PageRequest {
  maxResults: number;
  pageToken?: string;
}
export interface ConnectedLibraryProvider {
  listChannels(
    context: ReadContext,
  ): Promise<GooglePage<{ id: string; title: string }>>;
  listPlaylists(
    context: ReadContext,
    page: PageRequest,
  ): Promise<GooglePage<ConnectedPlaylist & { channelId: string }>>;
  playlistOwner(context: ReadContext, id: string): Promise<string | null>;
  listPlaylistItems(
    context: ReadContext,
    playlistId: string,
    page: PageRequest,
  ): Promise<GooglePage<PlaylistEntry>>;
  getVideos(context: ReadContext, ids: string[]): Promise<VideoDetails[]>;
}
