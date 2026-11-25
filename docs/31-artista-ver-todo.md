# 31 · Página de artista: «Ver todo» y contenido completo

## Qué faltaba y por qué

La página de artista de la app Android (`ArtistScreen`) se alimenta del catálogo
público de Mysic (`https://myslc.duckdns.org/api/youtube/artist/:id`). Ese servicio
ya entregaba mucho más de lo que la app pintaba:

| Dato del servicio | Antes | Ahora |
| --- | --- | --- |
| `topSongs` (5) | se pintaban, sin «Ver todo» | «Ver todo» → **todas las canciones** (`/songs`, p. ej. 141) |
| `shelves` (Álbumes, Sencillos y EP) | solo los primeros (p. ej. 10 álbumes; `releasesComplete: false`) | «Ver todo» → **discografía completa** (`/releases`, p. ej. 26 álbumes + 5 sencillos) |
| `videos` (p. ej. 16) | **descartados** | estante de **Vídeos** (miniaturas 16:9) y «Ver todo» |
| `playlists` («Featured on», «Playlists by …») | **descartadas** | estantes **Aparece en** y **Playlists de …** |

`OriginalMusicCatalog.artistProfile` solo recogía `topSongs` y los estantes de
álbumes; ahora también `videos` y `playlists` (`ArtistProfile.videos`,
`ArtistProfile.playlistShelves`). Las rutas `/songs` y `/releases` existían en el
servidor pero la app nunca las llamaba.

## Piezas

- `PublicCatalogClient.artistSongs` / `artistReleases` (+ `MusicModeController`):
  piden `/youtube/artist/:id/songs` y `/releases` (sin credenciales; el id se valida
  como canal `UC…`). Los parsers son `OriginalMusicCatalog.artistSongs` /
  `artistReleases`.
- Los títulos de los estantes se traducen (`shelfTitle`): «Featured on» → «Aparece
  en», «Playlists by X» → «Playlists de X», «Videos» → «Vídeos».
- `LibrarySectionHeader` (el encabezado con «Ver todo» de la Biblioteca) se recicla
  para cada bloque de la página de artista.
- `ArtistMoreScreen` (ruta `/artist/:id/more/:kind`, `kind` = `songs` | `releases` |
  `videos`): lista de canciones o vídeos con Reproducir y Aleatorio, o la
  discografía en cuadrícula de **3 por fila** (como la Biblioteca y Buscar; al
principio eran 2) por estantes (`CoverCard`, con solo el año en los álbumes).
- Los vídeos se reproducen como canciones (suena su audio): el estante
  `_VideoShelf` usa la misma cola que las canciones.

## Límites

- «Fans might also like» («También te puede gustar») y la biografía no los entrega
  el servicio hoy (`description` llega vacío): la traducción del título ya está
  lista, pero no hay bloque que mostrar.
- Las playlists de «Aparece en» pueden ser mezclas de YouTube Music (`RDCLAK…`);
  se abren con la página de playlist de siempre, que necesita la sesión de YouTube
  Music.
