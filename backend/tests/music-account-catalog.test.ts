import { describe, expect, it, vi } from 'vitest';
import {
  OAuthMusicCatalog,
  parseMusicAccountPage,
} from '../src/infrastructure/youtube/music-account-catalog.js';

function text(value: string) {
  return { runs: [{ text: value }] };
}
function shelf(id: string, kind: string, title: string) {
  return {
    musicTwoRowItemRenderer: {
      title: text(title),
      navigationEndpoint: {
        browseEndpoint: {
          browseId: id,
          browseEndpointContextSupportedConfigs: {
            browseEndpointContextMusicConfig: {
              pageType: 'MUSIC_PAGE_TYPE_' + kind,
            },
          },
        },
      },
    },
  };
}
function song(id: string, kind: string) {
  return {
    musicResponsiveListItemRenderer: {
      playlistItemData: { videoId: id },
      flexColumns: [
        {
          musicResponsiveListItemFlexColumnRenderer: {
            text: {
              runs: [
                {
                  text: 'Canción ' + id,
                  navigationEndpoint: {
                    watchEndpoint: {
                      videoId: id,
                      watchEndpointMusicSupportedConfigs: {
                        watchEndpointMusicConfig: { musicVideoType: kind },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
        {
          musicResponsiveListItemFlexColumnRenderer: { text: text('Artista') },
        },
      ],
    },
  };
}
const track = song('zzzzzzzzzzz', 'MUSIC_VIDEO_TYPE_ATV');
const clip = song('ccccccccccc', 'MUSIC_VIDEO_TYPE_OMV');
const lesson = song('aaaaaaaaaaa', 'MUSIC_VIDEO_TYPE_UGC');
const podcast = song('bbbbbbbbbbb', 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE');
const album = shelf('MPREb_album', 'ALBUM', 'Disco');
const pl = shelf('VLPLrock', 'PLAYLIST', 'Mi lista');
const token = (t: string) => ({
  continuationItemRenderer: {
    continuationEndpoint: { continuationCommand: { token: t } },
  },
});

describe('catálogo de la cuenta de Music', () => {
  it('conserva orden y duplicados de la lista y excluye cursos, podcasts y sugerencias ajenas a la lista', () => {
    const page = parseMusicAccountPage(
      {
        contents: {
          twoColumnBrowseResultsRenderer: {
            tabs: [
              {
                tabRenderer: {
                  selected: true,
                  content: {
                    sectionListRenderer: {
                      contents: [
                        {
                          musicResponsiveHeaderRenderer: {
                            title: text('Mi lista privada'),
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
            secondaryContents: {
              sectionListRenderer: {
                contents: [
                  {
                    musicPlaylistShelfRenderer: {
                      contents: [
                        track,
                        lesson,
                        clip,
                        podcast,
                        track,
                        token('seguir'),
                      ],
                    },
                  },
                  { musicShelfRenderer: { contents: [clip] } },
                  { musicCarouselShelfRenderer: { contents: [clip] } },
                ],
              },
            },
          },
        },
      },
      'playlist',
    );
    expect(page.title).toBe('Mi lista privada');
    expect(page.next).toBe('seguir');
    expect(page.excluded).toBe(2);
    expect(page.items.map((x) => x.id)).toEqual([
      'zzzzzzzzzzz',
      'ccccccccccc',
      'zzzzzzzzzzz',
    ]);
    expect(page.items[0]).toMatchObject({
      kind: 'track',
      playback: 'native',
      artist: 'Artista',
    });
  });
  it('distingue álbumes y playlists; Inicio conserva el orden de sus recomendaciones y el cursor del feed', () => {
    const raw = {
      contents: {
        sectionListRenderer: {
          contents: [
            {
              musicCarouselShelfRenderer: {
                contents: [album, pl, track, token('otra-seccion')],
              },
            },
            token('mas-inicio'),
          ],
        },
      },
    };
    expect(parseMusicAccountPage(raw, 'home')).toMatchObject({
      items: [
        { kind: 'album', id: 'MPREb_album' },
        { kind: 'playlist', id: 'PLrock' },
        { kind: 'track' },
      ],
      next: 'mas-inicio',
    });
    expect(parseMusicAccountPage(raw, 'albums').items.map((x) => x.id)).toEqual(
      ['MPREb_album'],
    );
    expect(
      parseMusicAccountPage(
        {
          onResponseReceivedActions: [
            {
              appendContinuationItemsAction: {
                continuationItems: [lesson, clip],
              },
            },
          ],
        },
        'liked',
      ).items.map((x) => x.id),
    ).toEqual(['ccccccccccc']);
    expect(() =>
      parseMusicAccountPage(
        {
          responseContext: { mainAppWebResponseContext: { loggedOut: true } },
          ...raw,
        },
        'home',
      ),
    ).toThrow();
  });
  it('mantiene el videoclip subido por un usuario y descarta el curso en la misma playlist', async () => {
    const uploaded = song('mmmmmmmmmmm', 'MUSIC_VIDEO_TYPE_UGC');
    const transport = vi.fn<typeof fetch>().mockImplementation(async () =>
      Response.json({
        contents: {
          musicPlaylistShelfRenderer: { contents: [lesson, uploaded, track] },
        },
      }),
    );
    const ctx = {
      access: 'test-account',
      signal: new AbortController().signal,
    };
    const getVideos = vi.fn(async () =>
      ['aaaaaaaaaaa', 'mmmmmmmmmmm'].map((id) => ({
        id,
        isMusicCategory: id === 'mmmmmmmmmmm',
        isRecording: false,
        artistId: undefined,
        availability: 'available' as const,
        title: null,
        channelTitle: null,
        durationSeconds: null,
        thumbnailUrl: null,
      })),
    );
    const api = new OAuthMusicCatalog(transport, { getVideos });
    const page = await api.read(ctx, {
      surface: 'playlist',
      playlistId: 'PLrock',
    });
    expect(getVideos).toHaveBeenCalledWith(ctx, ['aaaaaaaaaaa', 'mmmmmmmmmmm']);
    expect(page.items.map((row) => row.id)).toEqual([
      'mmmmmmmmmmm',
      'zzzzzzzzzzz',
    ]);
    expect(page.excluded).toBe(1);
  });
  it('solo valida Music con identidad positiva, biblioteca privada e Inicio accesibles', async () => {
    const ctx = {
      access: 'test-account',
      signal: new AbortController().signal,
    };
    const page = (auth?: boolean) =>
      Response.json({
        responseContext: {
          mainAppWebResponseContext:
            auth === undefined ? {} : { loggedOut: !auth },
        },
        contents: { sectionListRenderer: { contents: [] } },
      });
    const wire = vi.fn<typeof fetch>();
    const catalog = new OAuthMusicCatalog(wire);
    wire.mockResolvedValueOnce(page(true)).mockResolvedValueOnce(page(true));
    await expect(catalog.verify(ctx)).resolves.toBeUndefined();
    wire.mockResolvedValueOnce(page(true)).mockResolvedValueOnce(page(false));
    await expect(catalog.verify(ctx)).resolves.toBe('privatePlaylists');
    wire.mockResolvedValueOnce(page(true)).mockResolvedValueOnce(page());
    await expect(catalog.verify(ctx)).resolves.toBe('privatePlaylists');
    wire.mockResolvedValueOnce(page(true));
    await expect(
      catalog.verifyCollection(ctx, 'liked'),
    ).resolves.toBeUndefined();
    wire.mockResolvedValueOnce(page(false));
    await expect(catalog.verifyCollection(ctx, 'albums')).rejects.toMatchObject(
      { code: 'MUSIC_ACCESS_DENIED' },
    );
    wire.mockResolvedValueOnce(page()).mockResolvedValueOnce(page());
    await expect(catalog.verify(ctx)).rejects.toMatchObject({
      code: 'MUSIC_CATALOG_RESPONSE',
    });
    wire.mockResolvedValueOnce(
      Response.json(
        { error: { errors: [{ reason: 'quotaExceeded' }] } },
        { status: 403 },
      ),
    );
    await expect(catalog.verify(ctx)).rejects.toMatchObject({
      status: 429,
      code: 'YOUTUBE_QUOTA',
    });
  });
  it('envía la autorización del usuario solo a Music y usa la colección correspondiente a cada vista', async () => {
    const wire = vi
      .fn<typeof fetch>()
      .mockImplementation(async () =>
        Response.json({ contents: { sectionListRenderer: { contents: [] } } }),
      );
    const api = new OAuthMusicCatalog(wire);
    const ctx = {
      access: 'test-account',
      signal: new AbortController().signal,
    };
    for (const surface of [
      'liked',
      'home',
      'albums',
      'songs',
      'playlists',
    ] as const)
      await api.read(ctx, { surface });
    expect(
      wire.mock.calls.map(([url, init]) => [
        new URL(String(url)).origin,
        new Headers(init?.headers).get('authorization'),
        JSON.parse(String(init?.body)).browseId,
      ]),
    ).toEqual(
      [
        'VLLM',
        'FEmusic_home',
        'FEmusic_liked_albums',
        'FEmusic_liked_videos',
        'FEmusic_liked_playlists',
      ].map((id) => ['https://music.youtube.com', 'Bearer test-account', id]),
    );
    wire.mockResolvedValueOnce(new Response(null, { status: 403 }));
    await expect(api.read(ctx, { surface: 'home' })).rejects.toMatchObject({
      code: 'MUSIC_ACCESS_DENIED',
    });
    expect(wire).toHaveBeenCalledTimes(6);
  });
});
