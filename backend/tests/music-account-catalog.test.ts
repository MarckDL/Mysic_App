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
  it('conserva las tarjetas de mixes y playlists recomendados con su ID de lista canónico', () => {
    const page = parseMusicAccountPage(
      {
        contents: {
          musicCarouselShelfRenderer: {
            contents: [
              shelf('RDTMAK5uy_example', 'PLAYLIST', 'Mi mix'),
              shelf('PLlibrary', 'PLAYLIST', 'Lista recomendada'),
              shelf('VLPLnormal', 'PLAYLIST', 'Otra lista'),
              shelf('RDTMAK5uy_podcast', 'PODCAST_SHOW', 'Un programa'),
            ],
          },
        },
      },
      'home',
    );
    expect(page.items.map(({ kind, id }) => [kind, id])).toEqual([
      ['playlist', 'RDTMAK5uy_example'],
      ['playlist', 'PLlibrary'],
      ['playlist', 'PLnormal'],
    ]);
  });

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
                header: {
                  musicCarouselShelfBasicHeaderRenderer: {
                    title: text('Para ti'),
                  },
                },
                contents: [album, pl, track, token('otra-seccion')],
              },
            },
            {
              musicShelfRenderer: {
                title: text('Escucha de nuevo'),
                contents: [track, token('otra-lista')],
              },
            },
            token('mas-inicio'),
          ],
        },
      },
    };
    expect(parseMusicAccountPage(raw, 'home')).toMatchObject({
      items: [
        { kind: 'album', id: 'MPREb_album', shelfTitle: 'Para ti' },
        { kind: 'playlist', id: 'PLrock', shelfTitle: 'Para ti' },
        { kind: 'track', shelfTitle: 'Para ti' },
        { kind: 'track', shelfTitle: 'Escucha de nuevo' },
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
  it('omite una tarjeta que abre Shorts incluso si contiene un enlace musical', () => {
    const short = {
      musicResponsiveListItemRenderer: {
        ...clip.musicResponsiveListItemRenderer,
        navigationEndpoint: { reelWatchEndpoint: { videoId: 'ccccccccccc' } },
      },
    };
    const raw = {
      contents: { musicShelfRenderer: { contents: [short, track] } },
    };
    expect(parseMusicAccountPage(raw, 'liked')).toMatchObject({
      items: [{ id: 'zzzzzzzzzzz' }],
      excluded: 1,
    });
  });
  it('conserva el artista y el álbum enlazados de una canción', () => {
    const item = song('ddddddddddd', 'MUSIC_VIDEO_TYPE_ATV') as unknown as {
      musicResponsiveListItemRenderer: {
        flexColumns: Array<{
          musicResponsiveListItemFlexColumnRenderer: { text: unknown };
        }>;
      };
    };
    item.musicResponsiveListItemRenderer.flexColumns[1] = {
      musicResponsiveListItemFlexColumnRenderer: {
        text: {
          runs: [
            {
              text: 'Artista',
              navigationEndpoint: {
                browseEndpoint: {
                  browseId: 'UCartist0000000000000001',
                  browseEndpointContextSupportedConfigs: {
                    browseEndpointContextMusicConfig: {
                      pageType: 'MUSIC_PAGE_TYPE_ARTIST',
                    },
                  },
                },
              },
            },
            { text: ' • ' },
            {
              text: 'Disco',
              navigationEndpoint: {
                browseEndpoint: {
                  browseId: 'MPREb_album',
                  browseEndpointContextSupportedConfigs: {
                    browseEndpointContextMusicConfig: {
                      pageType: 'MUSIC_PAGE_TYPE_ALBUM',
                    },
                  },
                },
              },
            },
          ],
        },
      },
    };
    expect(
      parseMusicAccountPage(
        { contents: { musicShelfRenderer: { contents: [item] } } },
        'liked',
      ).items[0],
    ).toMatchObject({
      artistId: 'UCartist0000000000000001',
      albumId: 'MPREb_album',
      albumName: 'Disco',
    });
  });

  it('reutiliza durante la lectura el Inicio crudo verificado para la misma cuenta', async () => {
    const transport = vi.fn<typeof fetch>().mockImplementation(async () =>
      Response.json({
        responseContext: { mainAppWebResponseContext: { loggedOut: false } },
        contents: { musicShelfRenderer: { contents: [track] } },
      }),
    );
    const api = new OAuthMusicCatalog(transport);
    const ctx = {
      access: 'test-account',
      signal: new AbortController().signal,
    };

    await api.verify(ctx, 'user:generation');
    await api.read(ctx, { surface: 'home' }, undefined, 'user:generation');

    const homeCalls = transport.mock.calls.filter(([, init]) =>
      String(init?.body).includes('FEmusic_home'),
    );
    expect(homeCalls).toHaveLength(1);
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
        isMusicCategory: true,
        isRecording: id === 'mmmmmmmmmmm',
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
    const page = (auth?: boolean, entries: unknown[] = [track]) =>
      Response.json({
        responseContext: {
          mainAppWebResponseContext:
            auth === undefined ? {} : { loggedOut: !auth },
        },
        contents: { sectionListRenderer: { contents: entries } },
      });
    const wire = vi.fn<typeof fetch>();
    const catalog = new OAuthMusicCatalog(wire);
    wire.mockResolvedValueOnce(page(true)).mockResolvedValueOnce(page(true));
    await expect(catalog.verify(ctx)).resolves.toBeUndefined();
    wire
      .mockResolvedValueOnce(new Response(null, { status: 403 }))
      .mockResolvedValueOnce(page(true));
    await expect(catalog.verify(ctx)).resolves.toBe('personalHome');
    wire.mockResolvedValueOnce(page()).mockResolvedValueOnce(page(true));
    await expect(catalog.verify(ctx)).resolves.toBe('personalHome');
    wire
      .mockResolvedValueOnce(new Response(null, { status: 403 }))
      .mockResolvedValueOnce(page(true, []));
    await expect(catalog.verify(ctx)).rejects.toMatchObject({
      code: 'MUSIC_CATALOG_RESPONSE',
    });
    wire
      .mockResolvedValueOnce(new Response(null, { status: 503 }))
      .mockResolvedValueOnce(page(true));
    await expect(catalog.verify(ctx)).resolves.toBe('personalHome');
    wire
      .mockResolvedValueOnce(page(true))
      .mockResolvedValueOnce(new Response(null, { status: 503 }));
    await expect(catalog.verify(ctx)).resolves.toBe('privatePlaylists');
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
    const wire = vi.fn<typeof fetch>().mockImplementation(async () =>
      Response.json({
        responseContext: { mainAppWebResponseContext: { loggedOut: false } },
        contents: { sectionListRenderer: { contents: [] } },
      }),
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
    wire.mockResolvedValueOnce(
      Response.json({
        contents: { sectionListRenderer: { contents: [track] } },
      }),
    );
    await expect(api.read(ctx, { surface: 'home' })).rejects.toMatchObject({
      code: 'MUSIC_ACCESS_DENIED',
    });
    expect(wire).toHaveBeenCalledTimes(7);
  });
});
