# 25 — Buscar al estilo de Limusic Android y cabecera común

La pestaña Buscar de la app móvil reproduce la de Limusic Android
(`SimoHypers/limusic-android`, rama `dev`, commit `7de0ded`), leída de su código
fuente abierto. Las tres pestañas comparten además una sola cabecera.

Código (en `mobile/lib/features/connected_library/`):

- `presentation/search_screen.dart` — la pestaña. `MusicModeSurface` la monta
  cuando la superficie es `MusicSurface.search`.
- `presentation/mood_screen.dart` — la página de un ambiente o género
  (ruta `/music/mood`).
- `presentation/tab_top_bar.dart` — la cabecera común.
- `presentation/cover_art.dart` — carátula que llena una caja no cuadrada.
- `domain/music_search.dart` — `SearchResults`, `SearchSuggestions`,
  `MoodSection`.
- `../ytm/data/ytm_parser.dart` y `ytm_client.dart` — lectura de `search`,
  `music/get_search_suggestions` y `FEmusic_moods_and_genres`.

Pruebas: `test/search_screen_test.dart`, `test/ytm_search_parser_test.dart`.

## 1. De dónde salen los datos

Antes Buscar preguntaba al catálogo público (`/api/youtube/search`), que solo
da canciones, artistas o álbumes. Ahora habla directo con YouTube Music desde el
teléfono, con la sesión de la cuenta, igual que el resto de la app:

| Qué | Petición InnerTube |
| --- | --- |
| Resultados | `search` sin filtro + filtro de canciones + filtro de vídeos, las tres a la vez |
| Lista completa de álbumes, artistas o playlists | `search` con su filtro, al abrir el chip |
| Sugerencias | `music/get_search_suggestions` |
| Ambientes y géneros | `browse` de `FEmusic_moods_and_genres` |
| Página y portada de una categoría | `browse` de `FEmusic_moods_and_genres_category` |

Si YouTube Music no responde a ninguna de las tres búsquedas, se prueba el
catálogo público (solo canciones). Con «solo canciones descargadas» nada sale a
la red.

## 2. Estados de la pantalla

Como `SearchUIType` de Limusic, según el campo:

- **Vacío**: búsquedas recientes (fila horizontal, cada una con su aspa y un
  «Borrar» general) y las secciones de YouTube Music: «Para ti» en una fila de
  teselas anchas, «Ambientes» y «Géneros» en cuadrícula de dos columnas. Cada
  familia de tesela coloca la portada a su manera (panel, disco, funda
  inclinada), como `MoodCategoryCard.kt`. Si las categorías no llegan y no hay
  copia guardada, se muestran los géneros fijos de antes.
- **Escribiendo**: elementos directos (miniatura de 40 dp) y consultas
  sugeridas, con una flecha que lleva la sugerencia al campo.
- **Tras buscar**: chips Todo, Canciones, Vídeos, Álbumes, Artistas y
  Playlists. En Todo: resultado principal (tarjeta iluminada por su carátula,
  con botón de reproducir y las canciones emparejadas), cinco canciones y un
  estante por tipo con «Ver todo». Los demás chips muestran su lista: filas
  para canciones y vídeos, dos columnas para álbumes y playlists, tres para
  artistas.

Otros comportamientos copiados: la lupa se vuelve flecha con el panel de
sugerencias abierto, el botón Atrás cierra ese panel antes de salir, el texto de
ayuda rota cada 3 s, tirar para actualizar repite la búsqueda, y volver a tocar
la pestaña Buscar empieza una búsqueda nueva. Tocar una canción arma la cola con
su radio; mantener pulsado abre la hoja de opciones.

## 3. Velocidad

- Las categorías se guardan en disco y se pintan al instante en la siguiente
  apertura; la red las refresca por detrás.
- La portada de cada categoría se pide solo cuando su tesela entra en
  pantalla, cuatro a la vez como mucho, y se guarda una semana.
- Las sugerencias esperan 120 ms sin teclas: una petición por pausa.
- Un chip ya abierto no repite su petición.
- Las filas de canción adelantan el audio al detenerse en ellas y al tocarlas.
- Las búsquedas recientes (20 como mucho) se guardan por cuenta.

## 4. Cabecera común

`TabTopBar` es la cabecera de Limusic (`LimusicTabTopBar`): fila de 64 dp con
el título a 16 dp y las acciones al final, y debajo lo que añada la pestaña.

| Pestaña | Acciones | Debajo | Fondo |
| --- | --- | --- | --- |
| Inicio | Actualizar, Recientes, Cuenta | — | Transparente arriba; al desplazar, velo opaco sin desenfoque |
| Buscar | Cuenta | Campo y chips de tipo | Desenfoque fijo |
| Biblioteca | Actualizar, Recientes, Cuenta | Chips | Desenfoque fijo |

Inicio no desenfoca a propósito: sobre sus pastillas el desenfoque se veía como
una mancha. Por unificar, Inicio ya no lleva el logotipo junto al título y
Buscar usa esta cabecera en lugar del título grande que se pliega de Limusic.

## 5. Lo que no se replicó

Podcasts, selección múltiple de canciones y abrir un enlace de YouTube pegado
en el campo: Mysic no tiene esas funciones.
