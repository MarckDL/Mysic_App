# 32 · Guardar en varias playlists y buscador de atajos

## «Guardar en playlist» (`_PlaylistPicker`, `track_sheet.dart`)

Antes: tocar una playlist guardaba la canción en esa y **cerraba** la hoja (había que
volver a abrirla para guardarla en otra), solo se veía la primera página de playlists y
no decía cuántas canciones tenía cada una.

Ahora:

- **Varias a la vez.** Cada playlist lleva una **casilla a la derecha**. Marcarla guarda
  la canción (o las canciones) en ese momento; desmarcarla la quita. La hoja sigue
  abierta. **No hay botón de aceptar**: cada casilla se aplica al tocarla (también se
  puede tocar la fila entera). Mientras cambia, un círculo sustituye a la casilla.
- **Cuántas canciones tiene** cada playlist («36 canciones», «1 canción»): sale de la
  tarjeta de la biblioteca (`MusicPlaylist.trackCount`, leído del subtítulo con
  `songCount`) o del cuadro de YouTube Music, y sube o baja al marcar o desmarcar. Si no
  se sabe, se ve el tipo («Playlist», «Privada»).
- **Las que ya la tienen salen marcadas.** Al abrir se pregunta a YouTube Music
  (`playlist/get_add_to_playlist`, `YtmClient.saveOptions`, parser `parseYtmSaveOptions`)
  qué playlists contienen ya la canción (`containsSelectedVideos`). Desmarcar usa
  `browse/edit_playlist` con `ACTION_REMOVE_VIDEO_BY_VIDEO_ID`
  (`YtmClient.removeVideosFromPlaylist`).
- **Todas las playlists**, no solo la primera página: se piden página a página (tope de 20)
  y la lista crece mientras llegan.
- Si YouTube rechaza un cambio, la casilla vuelve a su estado y el mensaje de error
  sustituye en rojo al recuento en esa fila; volver a tocar lo reintenta.
- «Nueva playlist» sigue siendo la primera fila: crea la playlist con las canciones y
  cierra la hoja.

> Límite verificado: las dos llamadas a YouTube Music (`get_add_to_playlist` y la
> eliminación por id de vídeo) se probaron contra un servidor simulado con la forma de la
> respuesta que esperan, **no contra el servicio real**. Si una no existe o cambia, la
> casilla empieza vacía (membresía) o vuelve con un error (quitar), sin romper el modal.

## «Añadir atajo» (`_ShortcutPicker`, `home_sheets.dart`)

- Se piden **todas** las playlists y los álbumes de la cuenta (antes, solo la primera
  página de cada lista), con el mismo tope de 20 páginas.
- **Buscador básico** fijo bajo el título: una línea (borde inferior) con la **lupa** a la
  izquierda y una «x» para borrar. Filtra a la vez Biblioteca, Playlists y Álbumes por
  título, sin distinguir mayúsculas ni acentos (`foldForSearch`: «cancion» encuentra
  «Canción»). Si nada coincide: «No hay resultados para «…»».
- La hoja sube con el teclado (`_sheetFrame` suma el alto del teclado).
- El número máximo de atajos fijados sigue siendo el de siempre.
