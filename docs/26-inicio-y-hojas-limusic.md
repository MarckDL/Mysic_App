# 26 — Inicio y hojas de opciones al estilo de Limusic Android

El Inicio y las hojas inferiores (lo que se abre al mantener pulsado un
elemento) reproducen los de Limusic Android (`SimoHypers/limusic-android`, rama
`dev`, commit `7de0ded`), leídos de su código fuente abierto. El collage
«Accesos directos» de Mysic se conserva.

Código (en `mobile/lib/features/connected_library/`):

- `presentation/track_sheet.dart` — las hojas: canción, playlist o álbum,
  artista, atajo y «Guardar en playlist».
- `presentation/home_sheets.dart` — «Añadir atajo» y «Editar inicio».
- `presentation/music_mode_screen.dart` — el Inicio.
- `domain/shortcut.dart` — `Shortcut` y `HomeLayout`.
- `../search/presentation/item_sheet.dart` — el marco común de las hojas.
- `../ytm/data/ytm_client.dart` — los cambios en la cuenta de YouTube Music.

Pruebas: `test/item_menus_test.dart`.

## 1. Hojas al mantener pulsado

Una función, `showItemMenu`, abre la hoja que corresponde al elemento desde
cualquier pantalla (Inicio, Buscar, Biblioteca, géneros, artista, álbum).

| Elemento | Limusic | Contenido en Mysic |
| --- | --- | --- |
| Canción | `NowPlayingBottomSheet` | Cabecera con corazón (Me gusta). Cuatro acciones: A continuación, Añadir a la cola, Guardar en playlist, Descargar. Lista: Iniciar radio, Ir al artista, Ir al álbum, No me gusta, Compartir. En una playlist propia, Quitar de la playlist |
| Playlist o álbum | `PlaylistBottomSheet` | Reproducir con Aleatorio, A continuación, Añadir a la cola, Iniciar radio, Guardar en playlist, Compartir, Añadir a o Quitar de atajos. En una playlist propia, Editar y Eliminar |
| Artista | `ArtistBottomSheet` | Iniciar radio, Seguir o Dejar de seguir, Compartir |
| Atajo de colección | `ItemMenu` | Quitar de atajos |

Mysic añade a la de canción lo suyo: vincular o retirar un archivo de audio y
quitar la descarga.

Detalles copiados: la hoja se abre al instante y lo que necesita datos los
espera (Editar y Eliminar aparecen cuando se sabe que la playlist es de la
cuenta; Seguir está apagada hasta saber si ya se sigue); «Descargar» y «No me
gusta» dejan la hoja abierta, porque el cambio del icono es la respuesta.

Lo que Limusic solo muestra desde el reproductor o desde la cola
(temporizador, velocidad y tono, información de la canción, mover en la cola)
no aparece en estas hojas, igual que allí.

## 2. Cambios en la cuenta

Todo va directo a YouTube Music con la sesión del teléfono (`YtmClient`):

| Acción | Petición |
| --- | --- |
| Me gusta, No me gusta | `like/like`, `like/dislike`, `like/removelike` |
| Guardar en playlist, quitar de ella, editar | `browse/edit_playlist` |
| Nueva playlist (privada) | `playlist/create` |
| Eliminar playlist | `playlist/delete` |
| Seguir, dejar de seguir | `subscription/subscribe`, `subscription/unsubscribe` |
| Radio de una playlist | `next` con `RDAMPL<id>` |

Eliminar pide confirmación. Que una playlist es de la cuenta se sabe por su
página (`musicEditablePlaylistDetailHeaderRenderer`).

Aproximaciones: la radio de un álbum arranca de su primera canción y la de un
artista, de sus canciones destacadas; después sigue la radio automática de la
cola.

Compartir abre el menú del sistema (canal nativo `com.mysic/share`); si no
está, copia el enlace.

## 3. Atajos

La sección «De one pe» de Inicio pasa a ser la de atajos de Limusic
(`Shortcuts.kt`): hasta ocho, dos por fila.

- Se fijan desde «Añadir» (hoja con la Biblioteca: colecciones, playlists y
  álbumes; se queda abierta para fijar varios) o desde la hoja de cualquier
  playlist o álbum.
- Mantener pulsado un atajo abre la hoja de su playlist o álbum, con «Quitar de
  atajos».
- Mientras el usuario no fije ni quite nada se ven los de fábrica (Me gusta,
  Artistas, Recientes y las primeras playlists). El primer cambio parte de
  ellos.
- Se guardan por cuenta.
- Mysic añade la **canción** como atajo: se fija desde su hoja y al tocarla
  suena con su radio.
- Con los ocho ocupados, «Añadir a atajos» no se esconde: se ve apagada y dice
  que hay que quitar uno primero.

Las páginas de álbum y de playlist llevan arriba a la derecha un botón de tres
puntos que abre la misma hoja que mantener pulsado el elemento.

## 4. Inicio

- **Ambientes**: «Todo», Relax, Dormir, Energía, Tristeza, Romance, Buen ánimo,
  Entreno, Fiesta, Trayecto y Concentración cargan el Inicio de YouTube Music
  con la clave de cada uno (antes eran búsquedas de texto).
- **Editar inicio** (botón al principio de la fila): mostrar u ocultar los
  ambientes, el fondo con la carátula, los atajos y «Accesos directos». Se
  guarda por cuenta.
- **Saludo** con el nombre de pila de la cuenta.
- **Reproducir todo** en «Sigue escuchando».

## 5. Lo que no se replicó

- La cabecera propia del Inicio de Limusic (avatar y saludo en la barra, que se
  esconde al bajar): se mantiene la cabecera común de las tres pestañas.
- En «Editar inicio», reordenar secciones y el tamaño de las tarjetas.
- Selección múltiple de canciones, podcasts y Listen Together.
