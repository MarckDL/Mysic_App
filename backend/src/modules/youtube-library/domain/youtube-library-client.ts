import type { YoutubeLibrarySnapshot } from './youtube-library.js';

export interface YoutubeLibraryClient {
  fetchSnapshot(accessToken: string): Promise<YoutubeLibrarySnapshot>;
}
