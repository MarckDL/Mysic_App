export type PlaybackAttestationLease = Readonly<{
  sourceId: string;
  expiresAtMs: number;
}>;

export interface PlaybackTokenBroker {
  prepare(
    sourceId: string,
    signal?: AbortSignal,
  ): Promise<PlaybackAttestationLease>;
  invalidate(sourceId: string): void;
  close(): Promise<void>;
}
