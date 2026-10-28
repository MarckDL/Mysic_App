import type {
  MusicProvider,
  Track,
  PlaybackResult,
} from '../../modules/catalog/domain/music-provider.js';
import {
  demoAssetPath,
  demoSourceId,
} from '../../modules/playback/domain/playback-result.js';

export class AuthorizedDemoProvider implements MusicProvider {
  async search(): Promise<Track[]> {
    return [];
  }
  async getTrack(id: string): Promise<Track | null> {
    return id === demoSourceId
      ? {
          id: `demo:${demoSourceId}`,
          source: 'demo',
          sourceId: demoSourceId,
          title: 'Prueba de audio Mysic',
          artistName: 'Mysic · audio sintético propio',
          durationSeconds: 8,
          thumbnailUrl: null,
        }
      : null;
  }
  async resolvePlayback(id: string): Promise<PlaybackResult> {
    return id === demoSourceId
      ? {
          mode: 'direct',
          delivery: 'asset',
          assetPath: demoAssetPath,
          contentType: 'audio/wav',
          durationSeconds: 8,
        }
      : { mode: 'unavailable', reason: 'La fuente de demostración no existe.' };
  }
}
