# 29 — Sesión de YouTube Music, importar de Spotify y almacenado de descargas

Continúa los docs 24–28. Limusic Android se leyó en `SimoHypers/limusic-android`
(rama `dev`, commit `7de0ded`). Es código fuente abierto, así que se leyó
directamente; REA sirve para programas ya compilados.

## 1. Cómo mantiene Limusic el inicio de sesión

Archivos: `viewModel/YouTubeAccounts.kt`, `YouTubeAccounts.android.kt`,
`DataStoreManagerImpl.kt` y `Ytmusic.kt` (`authRejected`).

- **Qué se guarda.** Tras iniciar sesión en una vista web, la cookie entera de
  `music.youtube.com` se guarda en el `DataStore` (clave `cookie`), junto con el
  canal elegido (`pageId`, `authUser`). Cada inicio de sesión es una fila de
  cuenta; cerrar sesión pasa a invitado pero conserva la fila, y volver es un
  toque. A una cuenta la identifica el `SAPISID`, no el correo.
- **El problema.** La cookie guardada es una foto. Google rota sus fichas de
  corta vida (`SIDTS`…) y, con el tiempo, rechaza la copia con 401/403.
- **Cómo lo resuelve** (`heal`, copiado del escritorio: `refresh_session`):
  1. `Ytmusic` emite `authRejected` cuando una petición con cookie vuelve con
     401/403.
  2. Se escucha ese aviso, como mucho **una vez cada 5 minutos** (una cookie
     muerta provoca una ráfaga de rechazos, y todos son lo mismo).
  3. Se carga `music.youtube.com` en una **vista web oculta**. El almacén de
     cookies de esa vista sigue vivo (es el mismo del inicio de sesión), y la
     propia carga de la página hace que Google entregue las cookies rotadas. Se
     espera hasta 8 × 500 ms a que aparezcan.
  4. Solo se aceptan si son **de la misma cuenta** (mismo `SAPISID`) y distintas
     de las guardadas; si no, no se cambia nada. Así la app nunca se mueve de
     cuenta a espaldas del usuario.
  5. Antes de cambiar de cuenta guardada se comprueba que su sesión sigue
     entrando.

## 2. Qué hacía Mysic y qué hace ahora

Antes: la cookie se guardaba cifrada con el Keystore (`YtmSessionStore`, mejor
que el `DataStore` en claro de Limusic), pero **nunca se renovaba**: al primer
401/403 la app decía «YouTube Music cerró la sesión. Inicia sesión de nuevo».

Ahora, igual que Limusic:

- `YtmCookieRefresh.kt`: la vista web oculta, con el mismo criterio de cuenta.
- Canal `com.mysic/ytm`, método `refresh`: guarda la cookie nueva cifrada.
- `YtmClient`: ante un 401/403 pide la renovación y **repite la petición una
  vez** con la cookie nueva; si no hay nada más fresco, avisa como antes. Como
  mucho una renovación cada 5 minutos, y lo que renueva un cliente lo aprovechan
  los demás.

Pruebas: `test/ytm_session_renewal_test.dart`.

## 2 bis. La app no dejaba entrar: «No pudimos verificar tu sesión»

Con el modo **«Solo canciones descargadas»** activo (se guarda entre aperturas),
ninguna petición sale. La comprobación de la sesión al abrir la app fallaba al
instante (`ytm_verify_failed code=MUSIC_NETWORK`, seis veces en menos de dos
segundos) y, como una cuenta recién iniciada no tiene perfil guardado, la
pantalla de error era un callejón sin salida: no se podía entrar ni llegar a
Ajustes para apagar el modo. El teléfono sí llegaba a YouTube Music.

Ahora:

- Si la comprobación falla por algo que no es un rechazo de YouTube (red, modo
  sin conexión, límite de consultas), la app **entra igualmente** con lo que sabe
  de la cuenta; cada pantalla avisa si YouTube la rechaza. Un rechazo de verdad
  sigue cerrando la sesión.
- Con el modo sin conexión activo, la verificación ni intenta la red y no toca la
  sesión.
- La pantalla de error dice el motivo en letra pequeña.

Pruebas: `test/auth_gate_cached_profile_test.dart` y `test/ytm_test.dart`.

## 3. Importar de Spotify (de Mysic de escritorio)

El escritorio lee el enlace en Rust (`spotify_link.rs`) y empareja en
`spotifyImportModel.js`. En el móvil se hace en Dart, sin servidor:

1. **Leer.** `open.spotify.com/embed/playlist/<id>` es una página pública que
   lleva sus datos en un JSON (`__NEXT_DATA__`): nombre, autor, portada y las
   canciones. Sin cuenta ni API de Spotify. Deja leer como mucho las primeras
   100 canciones, y se avisa.
2. **Emparejar.** Cada canción se busca en YouTube Music («título artista»,
   quitando sufijos como «- 2015 Remaster»). Se mira entre los 5 primeros
   resultados: *encontrada* (título y artista coinciden), *por revisar* (se
   incluye pero se avisa) o *sin encontrar*. Cuatro búsquedas a la vez, un
   reintento por búsqueda.
3. **Crear.** Con lo encontrado, sin repetidas y en el orden de Spotify, se crea
   una playlist **privada** en la cuenta (`playlist/create`) con la descripción
   «Importada de Spotify · autor».

Se abre con el botón de enlace de **Buscar** y de **Biblioteca**. Al terminar
ofrece abrir la playlist, ver las dudosas y copiar la lista de las no
encontradas. «Detener» guarda lo encontrado hasta ese momento. Por ahora solo
playlists; álbumes, canciones y artistas avisan de que no se importan.

Código: `features/spotify_import/` y `core/text/fold_text.dart`. Pruebas:
`test/spotify_import_test.dart`, `test/spotify_fetcher_test.dart`.

## 3 bis. Descargas sin internet, sin encerrar al usuario

Lo descargado debe verse y sonar **desde Biblioteca → Descargas, con o sin
internet ni datos**, sin obligar a activar un modo global.

- **Antes.** Si la app arrancaba sin internet y había descargas, se ponía sola en
  el modo «Solo canciones descargadas»: sustituía las pestañas por una lista y
  bloqueaba toda la red hasta pulsar «Reintentar». Además, un álbum descargado
  se abría con la página normal del álbum, que usa el catálogo público de Mysic
  (el servidor del escritorio) y fallaba si este no respondía.
- **Ahora.**
  - Un álbum o playlist descargados se abren siempre con su página propia
    (`DownloadedCollectionScreen`), con internet o sin él.
  - Arrancar sin internet con descargas **deja al usuario en Biblioteca →
    Descargas** (`libraryTabRequests`), solo si seguía en Inicio. No cambia
    ningún ajuste ni bloquea la red, y puede ir a cualquier otra parte.
  - El modo «Solo canciones descargadas» ya **solo lo activa el usuario**, desde
    el interruptor de Descargas o Ajustes (ahorrar datos). Se quitó el modo
    automático (`checkAtStartup`, `retry`, `leaveAutomatic`).

Pruebas: `test/library_screen_test.dart` y `test/download_store_test.dart`.

## 4. Almacenado de las descargas

Defectos encontrados en `DownloadStore`:

- Todas las escrituras usaban el mismo archivo temporal (`index.json.tmp`) y
  podían ocurrir a la vez: una descarga que termina, rellenar el álbum, quitar
  una canción. Se pisaban y dejaban el índice corrupto o desactualizado.
- Si esa escritura fallaba, la descarga se marcaba como **fallida** aunque su
  audio ya estaba guardado.
- Con el índice ilegible la lista quedaba **vacía** y los audios seguían
  ocupando espacio sin verse.
- Una descarga que acababa antes de leer el índice lo reemplazaba solo con ella.

Ahora:

- Todo lo que se escribe pasa por una **fila de una en una**, con temporales
  propios y renombrado atómico.
- El índice se guarda con una **copia anterior** (`index.json.bak`).
- Cada canción lleva su **ficha** (`<id>.json`) junto al audio. Si el índice se
  pierde o se daña, se reconstruye con las fichas. Las descargas anteriores a
  este cambio reciben su ficha la primera vez que se abre la app.
- Que no se pueda escribir el índice ya no cuenta como fallo de la descarga: al
  arrancar se reconstruye lo que falte.
- Las colecciones se leen aparte del índice de canciones, y los temporales y las
  descargas a medias se limpian siempre.

Pruebas: `test/download_recovery_test.dart`.
