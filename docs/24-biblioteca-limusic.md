# 24 — Biblioteca al estilo de Limusic Android

La pestaña Biblioteca de la app móvil reproduce la de Limusic Android
(`SimoHypers/limusic-android`, rama `dev`, commit `7de0ded`). El análisis se hizo
leyendo su código fuente, que es abierto; no hizo falta descompilar nada.

Código: `mobile/lib/features/connected_library/presentation/library_screen.dart`.
`MusicModeSurface` la monta cuando la superficie es `MusicSurface.songs`.
Pruebas: `mobile/test/library_screen_test.dart`.

## 1. Estructura

| Parte | Limusic (`ui/screen/library`, `ui/component`) | Mysic |
| --- | --- | --- |
| Barra | `LimusicTabTopBar` + fila de chips sobre desenfoque Haze | `TabTopBar` (la cabecera común, ver doc 25): barra de estado + 64 dp de título + 44 dp de chips, `BackdropFilter` (opaca con «Reducir efectos») |
| Chips | `ChipGroup.kt`: píldora, icono 18 dp, sin marca; borde `outlineVariant` o relleno `primary` | `LibraryChip`, mismas medidas; separación 4, margen 15, inferior 8 |
| Cambio de pestaña | `Crossfade` | `AnimatedSwitcher` de 300 ms |
| Teselas | `LibraryTilingBox` 2×2 | `LibraryTiles` (ya existía) |
| Título de sección | `LibrarySectionHeader`: icono 22 al 70 %, «See all» + flecha 11 | `LibrarySectionHeader` |
| Estante de playlists | `PlaylistShelf`, miniatura 120 dp, 4 esqueletos | `_PlaylistShelf` |
| Cuadrícula | `LibraryGridCells`: columnas = ancho / 170, mínimo 3; 12 esqueletos | `_grid` |
| Tarjeta | `HomeItemContentPlaylist`: relleno 10/10/10/6, radio 10 | `_CoverTile` |
| Descargas | `DownloadsRow`: tarjeta radio 18, mínimo 64, cuadro de icono 40 | `_StatusRow` |

## 2. Pestañas

Salen solo las que la cuenta puede llenar (`connection.capabilities`):

- **Todo**: teselas (Me gusta, Descargas, Lo más oído, Artistas), estante de
  playlists con «Ver todo» y «Añadido recientemente» (primera página de Me
  gusta). Tocar una canción arma una cola de una canción más su radio, igual que
  el `PlaylistType.RADIO` de Limusic. La tesela Artistas y «Ver todo» cambian de
  pestaña en vez de abrir otra pantalla.
- **Playlists** y **Álbumes**: cuadrícula.
- **Canciones**: lista a todo el ancho.
- **Artistas**: fotos en filas de tres (`ArtistPhotoTile`), la vista que Mysic
  ya tenía; se conserva a petición en lugar de las filas de Limusic.
- **Descargas**: interruptor «Solo canciones descargadas», estado de la cola de
  descarga, fallos y las canciones guardadas.

En todas, mantener pulsado abre la hoja de opciones del elemento.

## 3. Velocidad

- Cada pestaña pide sus datos la primera vez que se muestra, no al abrir la
  Biblioteca. Volver a una pestaña ya vista no repite la petición.
- Lo ya visto en la sesión (`recalledPage`) o guardado en disco
  (`rememberedPage`) se pinta al instante y se refresca por detrás.
- Al actualizar se conserva la lista anterior en pantalla; los esqueletos solo
  aparecen en la primera carga, con el mismo tamaño que el contenido real para
  que nada salte.
- La página siguiente se pide al pintar las últimas celdas (a 5 del final en las
  listas), una petición a la vez. Si falla no se reintenta sola: espera a que el
  usuario desplace o actualice.
- Al volver a la app desde segundo plano se refresca la pestaña visible.

## 4. Lo que no se replicó

Mysic no tiene esas funciones, así que sus botones no existen: crear playlist,
sincronización con contador, notificaciones, Listen Together y podcasts. El
botón de la barra «Actualizar» ocupa el lugar del de sincronizar.
