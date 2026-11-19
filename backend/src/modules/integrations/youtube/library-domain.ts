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
export interface VideoDetails {
  id: string;
  title: string | null;
  channelTitle: string | null;
  durationSeconds: number | null;
  thumbnailUrl: string | null;
  availability: 'available' | 'unavailable' | 'unknown';
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
