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

## 3. Otros cambios de esta tanda

- **Collage del Inicio en tres páginas que se deslizan**, como el de YouTube
  Music: 27 elementos, 9 por página, con puntos.
- **Mini reproductor en todas las páginas** que se abren sobre las pestañas
  (álbum, playlist, artista, género, Recientes, Descargas…), con
  `WithMiniPlayer`.
- **Barra ondulada del reproductor recuperada**: forma de onda y tirador de
  aguja.
