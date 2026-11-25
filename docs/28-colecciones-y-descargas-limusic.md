# 28 — Álbumes, playlists y descargas al estilo de Limusic Android

Continúa los docs 24–27. Se tomó de Limusic Android (`SimoHypers/limusic-android`,
rama `dev`, commit `7de0ded`).

## 1. Cabecera de álbumes y playlists: Descargar y Me gusta

Como `CollectionDownloadButton` y `HeartCheckBox` de Limusic, la cabecera de un
álbum y la de una playlist ya no llevan Reproducir ni Aleatorio. En su lugar
llevan dos botones:

- **Descargar**: descarga todas las canciones. En una playlist larga se cargan
  antes las páginas que falten, hasta 40. Mientras descarga, el botón muestra el
  avance. Si la colección ya está entera en el teléfono, ofrece quitar la
  descarga.
- **Corazón**: guarda o quita la colección de la biblioteca de YouTube Music,
  con `like/like` o `like/removelike`. El destino es la playlist: para un álbum,
  su playlist de audio `OLAK5uy_…`. El botón está apagado hasta saber si ya está
  guardada. Las playlists propias no lo llevan, porque ya son de la biblioteca.

Reproducir y Aleatorio siguen en la hoja de tres puntos y en las propias
canciones.

La hoja de tres puntos de una playlist ajena también tiene «Guardar en tu
biblioteca» o «Quitar de tu biblioteca».

**Cómo se sabe si está guardada.** Como en Limusic, se mira si aparece en la
biblioteca: en `FEmusic_liked_albums` para los álbumes y en
`FEmusic_liked_playlists` para las playlists. Cada lista se lee una vez por
sesión, hasta 20 páginas. El botón de la página del álbum no sirve: YouTube lo
manda siempre como «no guardado».

Código:

- `connected_library/presentation/collection_actions.dart`: `CollectionActions`
  y `libraryState`.
- `toggleLibrary`.

**Limitación observada.** Al guardar el álbum de prueba, YouTube respondió «Se
ha guardado en la biblioteca», pero el álbum no apareció en la lista de álbumes
guardados ni en la de playlists. Hay que confirmarlo en la app oficial.

## 2. Ordenar las descargas

Como `PlaylistSortSheet` y `PlaylistSorting.kt` de Limusic. Un botón de ordenar
abre la hoja «Ordenar por». Está en la pantalla Descargas y en la pestaña
Descargas de la Biblioteca, y se pinta del acento cuando el orden no es el
predeterminado.

| Orden | Qué hace |
| --- | --- |
| Descargadas recientemente | El predeterminado: de la más reciente a la más antigua |
| Título | Alfabético |
| Artista | Alfabético por artista |
| Álbum | Agrupa por álbum. Dentro de cada álbum conserva el orden de descarga. Las canciones sin álbum van al final |

Con el interruptor **Invertir** se invierte cualquier orden. Elegir un orden lo
aplica y cierra la hoja; el interruptor lo aplica y deja la hoja abierta.

Los textos se comparan sin distinguir mayúsculas ni tildes, y los números por
su valor («Track 2» va antes que «Track 10»), como el `Collator` de Limusic.

El orden se guarda en `download_sort.txt` como `album` o `album:desc`, el mismo
formato que Limusic. Con el orden por álbum, cada fila muestra también el
álbum.

Las canciones bajadas desde la página de un álbum guardan ahora el nombre del
álbum. Las que se descargaron antes sin él lo reciben al abrir la página de su
álbum (`DownloadStore.fillAlbum`). Hasta entonces, van al final del orden por
álbum.

No se ofrecen dos opciones de Limusic:

- **Más nuevas** y **Más antiguas**: aquí equivalen al predeterminado y a su
  inverso, porque de cada descarga solo se sabe cuándo se descargó.
- **Más escuchadas**: las descargas no guardan las escuchas.

Código:

- `downloads/domain/download_sort.dart`
- `downloads/application/download_sort_provider.dart`
- `downloads/presentation/download_sort_sheet.dart`

Pruebas: `test/download_sort_test.dart`.

## 2 bis. Álbumes y playlists descargados enteros

Antes solo se guardaban las canciones, sueltas. En Limusic, descargar un álbum o
una playlist guarda además **la colección**: su fila queda marcada como
descargada (`STATE_DOWNLOADED`) con su lista de canciones, y Biblioteca →
Descargas muestra esas colecciones (`getAllDownloadedPlaylist`). Mysic hace lo
mismo:

- Al pulsar Descargar en un álbum o una playlist se guarda la colección (portada,
  nombre, artista y la lista de sus canciones) y las canciones bajan después, una
  a una. El botón se pinta como descargado en cuanto la colección está guardada;
  mientras bajan las canciones, muestra el avance.
- Biblioteca → Descargas lleva una cuadrícula **Álbumes y playlists** sobre la
  lista de canciones. Cada tesela dice «Álbum · artista», o «Álbum · 3 de 9»
  mientras faltan canciones. Tocarla abre **siempre la página propia de lo
  descargado** (`DownloadedCollectionScreen`), con internet o sin él: no pide
  nada a ningún servidor. Antes, con internet se abría la página normal del
  álbum, que usa el catálogo público de Mysic (el servidor del escritorio) y
  fallaba con «No se pudo conectar con el catálogo de Mysic» si este no
  respondía, aunque el álbum estuviera en el teléfono. Desde los tres puntos de
  esa página, con internet, se puede abrir la página normal. Mantener pulsada
  la tarjeta abre las mismas opciones que en el resto de la app.
- Pulsar Descargar en una colección ya descargada pregunta: **Quitar descarga**
  o, si faltan canciones, **Bajar las que faltan** (Limusic: `downloadMissing`).
- **Quitar la descarga** suelta la colección y borra sus canciones, salvo las que
  también guarde otra colección (Limusic: `releaseDownloads`). Una canción
  descargada suelta, desde su propio menú, sigue funcionando como antes.
- Un álbum que ya estaba entero en el teléfono, bajado canción a canción antes de
  este cambio, pasa a ser un álbum descargado al abrir su página.

Se guarda en `collections.json`, junto al índice de las canciones.

Código:

- `downloads/data/downloaded_collection.dart`
- `DownloadStore.keepCollection`, `releaseCollection`, `collections`, `tracksOf`.
- `connected_library/presentation/collection_actions.dart`
- `connected_library/presentation/library_screen.dart` (`_collectionsGrid`).

Pruebas: `test/downloaded_collection_test.dart`.

## 3. Otros cambios de esta tanda

- **Collage del Inicio («Accesos directos»)**: tres páginas de 3×3 que se
  deslizan (27 casillas, 9 por página, con puntos). Con pocos datos salía una
  segunda página con tres casillas y un hueco debajo; ahora:
  - el collage se llena también con canciones de los demás estantes del Inicio
    (se quedan en su estante), y con 9 playlists en vez de 8;
  - solo se muestran **páginas completas** (`SpeedDialGrid.wholePages`): 9, 18 o
    27; con menos de 9, una sola con filas de tres;
  - un collage guardado más pobre que el de ahora se reemplaza.
- **Mini reproductor en todas las páginas** que se abren sobre las pestañas
  (álbum, playlist, artista, género, Recientes, Descargas…), con
  `WithMiniPlayer`.
- **Barra ondulada del reproductor recuperada**: forma de onda y tirador de
  aguja.
