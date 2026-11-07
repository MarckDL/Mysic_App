import type { Innertube } from 'youtubei.js';
import { describe, expect, it, vi } from 'vitest';
import { YoutubeProvider } from '../src/infrastructure/music/youtube-provider.js';
import {
  ProviderTimeoutError,
  ProviderUnavailableError,
} from '../src/modules/catalog/domain/music-provider.js';

function fixture() {
  const search = vi.fn().mockResolvedValue({
    contents: {
      length: 1,
      filterType: () => [
        { contents: [{ item_type: 'song', id: 'abcdefghijk', title: 'Song' }] },
      ],
    },
  });
  const getBasicInfo = vi.fn().mockResolvedValue({
    basic_info: { id: 'abcdefghijk', title: 'Song', author: 'Artist' },
    playability_status: { status: 'UNPLAYABLE' },
  });
  const create = vi.fn(
    async () => ({ music: { search }, getBasicInfo }) as unknown as Innertube,
  );
  return {
    provider: new YoutubeProvider(create),
    search,
    getBasicInfo,
    create,
  };
}

describe('adaptador YoutubeProvider', () => {
  it('filtra canciones y solo devuelve el contrato propio', async () => {
    const { provider, search } = fixture();
    const tracks = await provider.search('artist');
    expect(search).toHaveBeenCalledWith('artist', { type: 'song' });
    expect(tracks[0]).toMatchObject({
      id: 'youtube:abcdefghijk',
      source: 'youtube',
      title: 'Song',
    });
  });
  it('consulta detalle independiente y no afirma reproducción con UNPLAYABLE', async () => {
    const { provider, getBasicInfo, search } = fixture();
    expect((await provider.getTrack('abcdefghijk'))?.title).toBe('Song');
    expect(getBasicInfo).toHaveBeenCalledWith('abcdefghijk', {
      client: 'YTMUSIC',
    });
    expect(search).not.toHaveBeenCalled();
    expect(
      (await provider.resolvePlayback('abcdefghijk')).availabilityVerified,
    ).toBe(false);
  });
  it('rechaza respuestas malformadas sin convertirlas en vacíos válidos', async () => {
    const { provider, search } = fixture();
    search.mockResolvedValueOnce({});
    await expect(provider.search('q')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
  });
  it('controla restricciones externas y descarta detalles de otra pista', async () => {
    const { provider, getBasicInfo } = fixture();
    getBasicInfo
      .mockRejectedValueOnce(new Error('login required - private data'))
      .mockResolvedValueOnce({
        basic_info: { id: 'abcdefghijk', title: 'Song', author: 'Artist' },
      });
    await expect(provider.getTrack('abcdefghijk')).resolves.toMatchObject({
      title: 'Song',
    });
    expect(getBasicInfo).toHaveBeenLastCalledWith('abcdefghijk', {
      client: 'TV',
    });
    getBasicInfo.mockReset().mockResolvedValue({
      basic_info: { id: '12345678901', title: 'Other' },
    });
    await expect(provider.getTrack('abcdefghijk')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
  });
  it('respeta abort y no hace peticiones con URLs arbitrarias', async () => {
    const { provider, create } = fixture();
    const controller = new AbortController();
    controller.abort();
    await expect(
      provider.search('q', controller.signal),
    ).rejects.toBeInstanceOf(ProviderTimeoutError);
    await expect(provider.getTrack('https://evil.test')).rejects.toBeInstanceOf(
      ProviderUnavailableError,
    );
    expect(create).not.toHaveBeenCalled();
  });
});
