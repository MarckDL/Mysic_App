export type PlaybackResult =
  | {
      mode: 'direct';
      delivery: 'asset';
      assetPath: string;
      contentType: 'audio/wav';
      durationSeconds: number;
    }
  | {
      mode: 'direct';
      delivery: 'api-stream';
      path: string;
      sourceId: string;
      contentType: 'audio/mp4';
      seekable: false;
      availabilityVerified: false;
    }
  | { mode: 'embedded'; url: string }
  | { mode: 'unavailable'; reason: string };

export const demoSourceId = 'mysic-tone-v1';
export const demoAssetPath = 'assets/audio/mysic-demo.wav';
