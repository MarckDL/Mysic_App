export const playbackClients = [
  'YTMUSIC',
  'WEB',
  'VISIONOS',
  'TV_SIMPLY',
] as const;

export type PlaybackClient = (typeof playbackClients)[number];

export type ResolvedPlaybackSource = Readonly<{
  sourceId: string;
  client: PlaybackClient;
  itag: number;
  privateUrl: string;
  mimeType: string;
  contentLength: number;
  durationMs: number;
  expiresAtMs: number;
}>;

export interface PlaybackSourceResolver {
  resolve(
    sourceId: string,
    signal?: AbortSignal,
  ): Promise<ResolvedPlaybackSource>;
  invalidate(sourceId: string): void;
  close(): Promise<void>;
}
