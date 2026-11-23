# 20 · Velocidad de Limusic y plan para alcanzarla en Mysic

Qué hace Limusic para reproducir, navegar y cargar rápido, qué de eso ya tiene Mysic, y qué falta. Complementa al [documento 19](19-analisis-limusic-android.md), que cubre el diseño.

## Cómo leer este documento

- **Fuente.** Lectura de código de `SimoHypers/limusic-android`, ramas `master` (commit `f6621cc`, 1.1.0-rc.3) y `dev` (commit `6c8bc5e`, 1.1.0-rc.4). No se compiló ni se ejecutó Limusic: sus tiempos no están medidos, solo el número y el orden de sus peticiones.
- **Rama de referencia: `dev`.** Es un superconjunto de `master`; nada en `master` es más rápido (sección 7).
- **Mediciones de Mysic.** Hechas en un moto g04s (gama baja) con los APK 4051–4055, leyendo el registro del teléfono. Cada cifra indica de dónde sale.
- **Referencias de archivo.** Rutas relativas a la raíz del repositorio de Limusic, rama `dev`. Abreviaturas en el anexo A.
- **"No verificado".** La sección 11 reúne lo que no se pudo comprobar. No se da por cierto en el resto del texto.

## 1. Conclusiones

1. **Limusic no tiene backend propio en el camino de los datos.** El teléfono habla directo con YouTube (InnerTube). Cada pantalla cuesta de 1 a 3 peticiones. Mysic pasa por dos servidores (Render y el backend de escritorio); cada salto añade al menos una ida y vuelta, y Render puede tardar cerca de un minuto en despertar.
2. **Limusic no precarga canciones de otras pantallas ni guarda Inicio en caché.** Un toque en frío paga toda la resolución; Inicio se pide entero en cada arranque. En esos dos puntos Mysic ya va por delante (sección 8).
3. **Su ventaja en reproducción es recordar.** Guarda en base de datos la URL resuelta de cada canción con su caducidad real, guarda el audio en disco sin límite por defecto, y tiene siempre la siguiente pista preparada en un segundo reproductor.
4. **Arranca a sonar con el primer buffer.** Espera de buffer 0 ms. Mysic usa 250 ms, que es equivalente en la práctica.
5. **Su fluidez de interfaz viene de disciplina, no de trucos.** Pestañas que conservan estado, barras fuera del navegador, listas con clave y tipo, efectos caros solo donde se ven y solo en Android 12 o superior.
6. **Lo que más tiempo le queda a Mysic** es, por orden: la espera al servidor de Render en el arranque, la extracción de YouTube en el primer toque de una canción no vista (≈2,5 s), y las páginas de detalle que no pintan nada hasta que llega la respuesta.

## 2. Reproducción

### 2.1 Del toque al sonido en Limusic

| Paso | Qué hace | Red |
|---|---|---|
| 1 | El ViewModel entrega la cola al servicio (`MH:1030`). Lee un ajuste e inserta la canción en la base de datos. | Ninguna |
| 2 | Arranca el reproductor de inmediato (`MH:1081`, `1109`). La radio y el resto de la lista se piden **después** (`MH:1082-1088`, `1179-1195`). | Ninguna |
| 3 | Si hay un reproductor precargado para esa canción, lo usa ya preparado (`XF:1717-1729`). Si no, crea uno nuevo, `prepare()` y `play()` sin esperar (`XF:1731-1793`). | Ninguna |
| 4 | La URL se resuelve **dentro** del hilo de carga del reproductor (`M3:265`, `310`), en este orden: descarga en disco → caché de reproducción completa → URL guardada y no caducada (con un `HEAD` de comprobación) → resolución nueva. | 0, 0, 1 o más |
| 5 | Resolución nueva, en serie (`YT:1383-1540`): id del player, token de integridad, `POST /player`, descifrado, sonda de los últimos 256 bytes. | 2 con todo caliente; varios segundos la primera vez de la sesión |
| 6 | Primer `GET` del audio. Suena con el primer buffer decodificado. | 1 |

Coste por caso, contado en idas y vueltas:

| Caso | Idas y vueltas |
|---|---|
| Canción descargada o completa en caché | 0 |
| URL guardada y vigente | 2 (`HEAD` + audio) |
| En frío, sesión ya caliente | 3 (`/player`, sonda, audio) |
| Primera canción de la sesión | Se suman `iframe_api`, tablas de cifrado, `base.js` (hasta 8 MiB) y el arranque de BotGuard |

### 2.2 Valores exactos

| Parámetro | Valor en Limusic | Dónde |
|---|---|---|
| Espera de buffer para empezar | 0 ms | `XF:633-637` |
| Espera tras un corte | 0 ms | `XF:633-637` |
| Buffer mínimo y máximo | 4 × valor por defecto de Media3 1.11.1 (200 000 ms, ver sección 11) | `XF:630-638` |
| Pistas precargadas | 1, la siguiente real (respeta aleatorio y repetición) | `XF:398`, `2389-2431` |
| Momento de la precarga | Justo después de cargar la actual, no cerca del final | `XF:1806` |
| Trozo de descarga | 5 MiB (`10*512*1024`); la URL se revisa en cada trozo | `M3:256`, `365` |
| Caché de audio en disco | Ilimitada por defecto; opciones 100 MB – 8 GB | `DSM:382`, `CFG:335-337` |
| Clave de caché | `videoId` | `EXT:57`, `92` |
| Caducidad de URL guardada | `ahora + expiresInSeconds` de la respuesta de YouTube | `SR:200-245` |
| Resoluciones simultáneas de una misma canción | Se comparten (una sola petición) | `YT:1329-1365` |
| Formato pedido | Opus 256 (itag 774) → AAC (141) → mayor bitrate | `CFG:194-208`, `SR:170-175` |
| Tiempos de espera del reproductor | 15 s conexión y lectura | `M3:541-545` |
| Reintento ante fallo de red | Indefinido: 1 s sin red; `min(intentos × 1 s, 5 s)` con red | `LS:93-118` |
| Reintento ante 403/410 | Hasta 2 por pista: invalida la URL guardada y retoma la posición | `XF:439`, `1925-1979` |
| Crossfade | 5 s por defecto (1–10 s), como mucho media pista | `DSM:974`, `XF:2167` |

### 2.3 Técnicas, y qué hace Mysic con cada una

| Técnica de Limusic | Estado en Mysic | Comentario |
|---|---|---|
| Arrancar el reproductor antes de pedir la radio y la cola | **Hecho** | `music_mode_screen.dart`, `_play` |
| Espera de buffer mínima | **Hecho** (250 ms) | `just_audio_track_engine.dart` |
| Precargar la siguiente pista | **Hecho a medias** | Se adelanta la URL, no un reproductor ya preparado. Medido: salto a la siguiente en 0,7–1,1 s |
| Compartir resoluciones en vuelo | **Hecho** | `DevicePlaybackResolver.kt`, `resolveSingleFlight` |
| Recordar URL resueltas | **Hecho en memoria** | 48 canciones, 1 hora. Se pierde al cerrar la app. Limusic las guarda en disco |
| Guardar el audio en disco | **Falta** | Repetir una canción vuelve a descargarla |
| Reintento ante URL caducada | **Hecho** | `_recoverSource` con `refresh: true` |
| Soltar conexiones al cambiar de red | **Falta** | Hoy un cambio wifi↔datos puede esperar al tiempo límite de un socket muerto |
| Cliente de YouTube con URL directa sin descifrado | **Depende de NewPipe** | Mysic usa NewPipe Extractor; qué clientes prueba lo decide esa librería |
| Segundo reproductor ya preparado (y crossfade) | **Falta** | Necesita un segundo `AudioPlayer`; es lo que haría el salto instantáneo |

### 2.4 Mediciones de Mysic

| Caso | Tiempo | Origen |
|---|---|---|
| Toque en frío: extracción de YouTube | 1,9 s | Registro `device_resolution`, APK 4052 |
| Toque en frío: comprobación del final del archivo | 0,6 s | Ídem |
| Toque en frío: total hasta el primer sonido | 3,3 s | Registro `audio_first_progress`, APK 4052 |
| Canción ya resuelta (calentada o repetida) | 0,44 – 0,65 s | APK 4055, tres toques |
| De eso, preparar el reproductor | 0,39 – 0,59 s | Registro `audio_player_preparation` |
| Calentar 4 canciones al abrir Inicio | 1,3 s, 2,2 s, 3,3 s y 11,2 s acumulados | Registro `device_warm`, APK 4055 |

Lectura: con la URL resuelta, Mysic suena en medio segundo. Todo lo que pase de ahí es extracción. La extracción no se acelera desde la app; solo se evita (recordando) o se adelanta (calentando).

### 2.5 Qué no copiar de Limusic en reproducción

- **El `HEAD` antes de usar una URL guardada** y **la sonda de 256 bytes**: una ida y vuelta cada una, en serie. Limusic las paga por fiabilidad. Mysic ya tiene su propia sonda (un byte del final) y un reintento si la URL falla; no hace falta añadir el `HEAD`.
- **Nada se calienta al arrancar.** La primera canción de cada sesión paga toda la cadena en frío.
- **Reproductores precargados huérfanos.** Al saltar a una pista que no es la precargada, el reproductor precargado antiguo no se libera hasta que cambia la cola (deducido de la lectura, no observado).
- **Un reproductor nuevo por cada pulsación de "siguiente"**, sin espera entre pulsaciones.

## 3. Red y peticiones

### 3.1 Cliente HTTP de Limusic

- Ktor sobre OkHttp, con **un solo grupo de conexiones compartido** por todos los clientes (`ENG:16-26`).
- Compresión **brotli**, gzip y deflate (`YM:205-209`).
- Al cambiar de red vacía las conexiones inactivas, para que ninguna petición espere en un socket muerto (`ENG:33`, `LimusicApplication.kt:64-71`).
- **Sin tiempos de espera y sin reintentos automáticos** en las peticiones de datos. No copiar.
- **Registro completo de cada petición activado siempre** (`YM:165-189`). Es un coste, no copiar.

### 3.2 Peticiones por pantalla

| Pantalla | Peticiones | Orden | Qué se ve mientras tanto |
|---|---|---|---|
| Inicio | 1, más hasta 2 continuaciones si aún no llegó "Quick picks" | En serie | Esqueleto hasta el final |
| Búsqueda | 3 (todo, canciones, vídeos) | **En paralelo** | Esqueleto |
| Filtros de búsqueda (álbumes, artistas…) | 1 cada uno, solo al abrirlo; se recuerda | — | — |
| Sugerencias | 1 por cada tecla, **sin espera ni cancelación** | — | No copiar |
| Artista | 1 | — | Cargador central |
| Álbum | 1 (las canciones vienen dentro) | — | Cargador central |
| Playlist | 1 por página, al llegar al final de la lista | — | Cargador central |
| Biblioteca con sesión | Hasta 21 páginas | **En serie** | No copiar |

Técnicas que sí valen:

- **Un solo disparador para Inicio**: combina idioma, país, sesión y filtro, espera 300 ms y lanza una recarga en lugar de cuatro (`HomeViewModel.kt:110-120`).
- **Cancelar lo obsoleto**: una búsqueda nueva cancela la anterior (`SearchViewModel.kt:220-221`); una recarga de Inicio cancela la que estaba en curso (`HomeViewModel.kt:140`).
- **Reintento solo al volver la red**: la página que falló se recarga sola cuando hay conexión (`BaseViewModel.kt:67-80`).
- **Reproducir desde la tarjeta sin abrir la página** (`BaseViewModel.kt:203-234`).
- **Cambios por lotes**: quitar N canciones de una playlist es una sola petición (`YM:583-602`).

### 3.3 Mysic frente a esto

| Aspecto | Limusic | Mysic hoy |
|---|---|---|
| Saltos hasta los datos | 1 (YouTube) | 2 (servidor propio → YouTube) |
| Arranque | 1 petición de Inicio | Sesión (2 en serie) + conexión musical + Inicio, contra Render |
| Clientes HTTP | Varios, un grupo de conexiones | Uno por cada `AuthenticatedApiClient` (unos 12), sin compartir conexiones |
| Enlaces de artista y álbum | Vienen en la respuesta | Una búsqueda extra por canción (≈240 ms medidos) |
| Tiempos de espera | Ninguno | 75 s contra Render, 15–60 s contra el backend de escritorio |

## 4. Caché de datos e imágenes

### 4.1 Qué guarda Limusic

- **Base de datos local (Room, 25 tablas).** Biblioteca, historial, cola, letras, formatos de audio resueltos. **No guarda Inicio ni las páginas de artista, álbum o playlist.**
- **Álbum y playlist: red primero, base local si falla.** No es "pintar de caché y refrescar".
- **Único caso de pintar de caché y refrescar por detrás:** el catálogo de géneros y ambientes (`HomeRepositoryImpl.kt:219-263`).
- **Fallos recordados:** una canción sin letra no se vuelve a buscar en 24 h (`LyricsCanvasRepositoryImpl.kt:584`); sin carátula animada, en 7 días.

### 4.2 Imágenes

| Aspecto | Limusic | Mysic hoy |
|---|---|---|
| Caché en disco | 512 MiB | 256 MB |
| Vigencia | 24 h; si caduca **espera a la red** y cae a la caché si falla | Sin caducidad: siempre de disco |
| Peticiones simultáneas de la misma imagen | Una sola | Una sola |
| Tamaño pedido | 544 px en rejillas, 360 en artistas, 120 en avatares, 96 en miniaturas, 1080 en el hero | Al tamaño pintado |
| Fundido al aparecer | 550 ms en tarjetas, 300 ms en el reproductor | Sí |
| Precarga de imágenes | Ninguna | Ninguna |
| Conexiones | Cliente por defecto | Un cliente compartido, 6 por servidor |

En imágenes Mysic ya está a la par o por delante: sirve de disco sin esperar a la red.

## 5. Arranque, navegación e interfaz

### 5.1 Arranque

- **Sin pantalla de bienvenida.** Solo un fondo negro igual al primer fotograma, para que no haya destello (`themes.xml:3-13`).
- **El tema correcto desde el primer fotograma.** Lee los ajustes de tema y el último color de carátula antes de pintar (`SharedViewModel.kt:1270-1312`).
- **El mini reproductor no parpadea al abrir.** Su visibilidad se deriva del estado, no se guarda aparte (`App.kt:127-142`).
- **Permisos bajo demanda.** El de notificaciones se pide en la primera descarga, no al abrir.
- **Compilación de lanzamiento:** minificado, recursos reducidos, un APK por arquitectura (`androidApp/build.gradle.kts:80-97`).
- **No tiene** perfiles de arranque (Baseline Profiles) ni pantalla de bienvenida animada.
- **A no copiar:** casi todas sus dependencias se crean al arrancar, y lee ajustes bloqueando el hilo principal.

### 5.2 Navegación

- **Tres pestañas que conservan su estado** al cambiar entre ellas (`LimusicNavigation.kt:67-72`). Volver a Inicio no recarga.
- **Tocar la pestaña activa** sube al principio o refresca; si hay páginas encima, vuelve a la raíz (`:102-110`).
- **Barra inferior y mini reproductor fuera del navegador**: no se redibujan ni se animan al cambiar de página (`App.kt:372-398`).
- **Transición:** deslizamiento horizontal con fundido; entre pestañas, en el sentido de la barra (`AppNavigationGraph.kt:46-63`).
- **Punto débil de Limusic:** las páginas de álbum, playlist y artista reciben solo el identificador y muestran un cargador hasta que llega la respuesta. No pintan título ni portada por adelantado. **Aquí Mysic puede superarla** (sección 9, punto 4).
- **No recargar al volver:** cada pantalla comprueba si ya tiene los datos de ese identificador antes de pedirlos (`PlaylistScreen.kt:258-262`).

### 5.3 Listas e interfaz

- Clave por elemento y tipo de contenido en las listas largas, para reutilizar filas.
- Rejillas construidas como filas de una sola lista, no listas dentro de listas.
- Paginación al acercarse al final (a 6 elementos en playlist, a 1 en Inicio).
- Tamaños fijos en mini reproductor (58 dp) y esqueletos, para que nada salte al cargar.
- Lo que cambia con el desplazamiento se lee en la fase de dibujo, sin reconstruir la pantalla.

### 5.4 Efectos caros y gama baja

| Efecto | Cómo lo limita Limusic |
|---|---|
| Desenfoque de barras | Solo cuando la lista ya no está arriba; radio 24 dp; **solo en Android 12 o superior**, por debajo color opaco (`UIExt.kt:678-707`) |
| Fondo borroso de Inicio | Carátula pedida a 96 px y desenfocada; se puede apagar (`HomeScreen.kt:749-761`) |
| Color desde la carátula | Imagen a 112 px, cálculo fuera del hilo principal, caché por URL, y **lee por adelantado las 4 carátulas vecinas**; conserva el color anterior hasta tener el nuevo (`PagerBlend.kt:45-96`) |
| Letras con desenfoque | Estilo oculto en ajustes por debajo de Android 12 |
| Esqueleto | Un gradiente de 3 colores, 1 s |

No detecta gama baja por memoria ni ofrece "reducir animaciones".

Mysic ya hace el fondo de 96 px, el color con caché y el desenfoque condicionado al desplazamiento. Le falta la alternativa opaca por versión de Android y la lectura anticipada de colores vecinos.

### 5.5 Percepción de velocidad

- Cambio entre carga y contenido siempre con fundido.
- Aviso flotante sobre el mini reproductor con lo que se está cargando tras cerrar un menú (`BaseViewModel.kt:111-137`).
- Estado "sin conexión" explícito, con reintento y acceso a lo descargado.

## 6. Servicios externos

Ninguno pasa por un servidor de Limusic salvo sus letras propias y la escucha compartida. **No se copió ninguna clave**; donde existe una, solo se indica.

### 6.1 Necesarios para reproducir y cargar

| Servicio | Para qué | Clave o cuenta | Tiempo límite |
|---|---|---|---|
| InnerTube: `music.youtube.com/youtubei/v1`, `www.youtube.com/youtubei/v1/player` | Todos los datos y la resolución del audio | Sesión opcional | Ninguno |
| `www.youtube.com/iframe_api` y `/s/player/<id>/…/base.js` | Id y código del player para descifrar firmas | No | Id en memoria 30 min |
| Tablas de cifrado en `raw.githubusercontent.com` (dos proyectos de terceros) | Descifrado de firmas sin ejecutar el player | No | 5 s; se renuevan cada 6 h |
| BotGuard: `www.youtube.com/api/jnn/v1` (en un WebView oculto) | Token de integridad | Hay una clave embebida | 20 s; se renueva 600 s antes de caducar |
| `i.ytimg.com`, `yt3.googleusercontent.com`, `lh3.googleusercontent.com` | Imágenes | No | — |

Mysic no usa InnerTube directo, tablas remotas ni BotGuard: delega en NewPipe Extractor (en el teléfono) y en el backend de escritorio. Depender de tablas de cifrado de terceros en GitHub es un riesgo de disponibilidad que Mysic no tiene.

### 6.2 Letras

Orden por defecto en Limusic (`LyricsSource.kt:7-17`): Limusic → Better Lyrics → Unison → LyricsPlus → LRCLIB → YouTube → NetEase → QQ → KuGou.

Estrategia: cada proveedor arranca 300 ms después del anterior, sin esperarlo, con 10 s cada uno. Gana la primera respuesta sincronizada según el orden del usuario y cancela el resto (`LyricsCanvasRepositoryImpl.kt:107-129`).

| Proveedor | Host | Clave | En Mysic |
|---|---|---|---|
| Limusic Lyrics | `lyrics.limusic.app` | Token anónimo | No (servidor de Limusic) |
| Better Lyrics | `lyrics-api.boidu.dev` | No | **Sí** |
| Unison | `unison.betterlyrics.org` | No | No respondió en las pruebas |
| LyricsPlus | `lyricsplus.binimum.org/v2` | No | No respondió en las pruebas |
| LRCLIB | `lrclib.net/api` | No | **Sí** |
| YouTube Music | InnerTube | — | No |
| NetEase, QQ, KuGou | `music.163.com`, `c.y.qq.com`, `*.kugou.com` | No | No (servicios internos de terceros) |

Mysic usa la misma estrategia escalonada (250 ms, 10 s), con dos proveedores.

### 6.3 Opcionales, sin efecto en la velocidad

| Servicio | Host | Para qué | Clave o cuenta |
|---|---|---|---|
| Apple Music | `music.apple.com`, `amp-api.music.apple.com` | Carátula animada y logo de artista | Token extraído de la web |
| Last.fm | `ws.audioscrobbler.com/2.0/` | Registro de escuchas | Clave y secreto de API, más cuenta |
| Discord | `gateway.discord.gg`, `discord.com/api` | Estado "escuchando" | Cuenta |
| Escucha compartida | `sync.limusic.app` | Sincronía entre dispositivos | No |
| Actualizaciones | `api.github.com/repos/SimoHypers/limusic-android` | Versiones nuevas | No |
| AutoEq | `raw.githubusercontent.com/jaakkopasanen/AutoEq` | Curvas de ecualización | No |
| Diccionario Kuromoji | Publicación en GitHub | Romanización del japonés | No |

**No están en Limusic:** Spotify (el estilo "Spotify" es solo visual), SponsorBlock, Return YouTube Dislike, Musixmatch, analíticas ni informes de fallos (el DSN de Sentry está vacío).

## 7. `master` frente a `dev`

75 archivos distintos, la mayoría interfaz. Los búferes, la precarga, el cifrado, la resolución, el cliente HTTP, las cachés y la base de datos son **idénticos** en las dos ramas.

Lo que `dev` mejora en velocidad:

| Cambio | `master` | `dev` |
|---|---|---|
| Avisos de reproducción a YouTube | ~4 peticiones al arrancar cada pista y una cada ~20 s | 1 petición por pista |
| Lectura de posición | Cada 50 ms siempre | 50 ms con la pantalla visible; 1 s oculta |
| Pista ya en disco | Pedía `/player` igualmente | Solo si el usuario activó enviar historial |
| Descargas | Mantenían la red despierta | No, si el archivo está completo |
| "Anterior" | Delegaba en el reproductor | Mueve la cola al instante |
| Deslizar carátulas rápido | Un salto por carátula | Un solo salto al terminar el gesto |
| Red bloqueada en segundo plano | Reintentaba | Se trata como sin red |
| Color de carátula | Por pista | Lee por adelantado las vecinas |

## 8. Dónde Mysic ya va por delante

| Punto | Limusic | Mysic |
|---|---|---|
| Abrir la app | Pide Inicio entero cada vez | Entra con el perfil guardado; Inicio con contenido a los 2,7 s medidos (servidor despierto) |
| Canciones a la vista | No adelanta nada | Adelanta las 4 primeras del collage |
| Imágenes caducadas | Espera a la red | Sirve de disco |
| Sugerencias y esperas | Sin espera, sin límites de tiempo | Tiempos límite en todas las peticiones |
| Enlace al álbum en el reproductor | — | Nombre resuelto y enlace directo |

## 9. Plan para Mysic

Ordenado por tiempo que ahorra al usuario. "Servidor" indica que necesita el cambio correspondiente del prompt de servidor ya entregado.

| # | Qué | Ahorro esperado | Dónde | Riesgo |
|---|---|---|---|---|
| 1 | **Arranque en una sola petición** (perfil + conexión + Inicio) y servidor siempre despierto | Hasta un minuto en frío; 1–2 idas y vueltas en caliente | Servidor (Render) + `music_mode_controller.dart` | Bajo |
| 2 | **Guardar Inicio y la conexión musical en disco** y pintarlos al abrir, refrescando por detrás | Inicio visible en menos de 1 s | `music_mode_controller.dart`, `music_mode_screen.dart` | Medio: la conexión lleva lógica de generaciones y de reproducción |
| 3 | **Guardar en disco las URL resueltas** (hoy solo en memoria) | Los ≈2,5 s de extracción en canciones ya escuchadas, tras reabrir la app | `DevicePlaybackResolver.kt` | Bajo: las URL caducan solas y ya hay reintento |
| 4 | **Pintar título y portada al abrir álbum, artista y playlist**, con transición de la portada | La página deja de parecer vacía ~0,3–1 s | `catalog_pages.dart`, rutas en `catalog_navigator.dart` | Bajo |
| 5 | **Caché de audio en disco** por canción, con límite configurable en Ajustes | Repetir una canción: 0 red | `just_audio_track_engine.dart` (`LockCachingAudioSource` o equivalente) | Medio: espacio en disco; probar con saltos de posición |
| 6 | **Enlaces de artista y álbum dentro de cada canción** | Una búsqueda (≈240 ms) por canción | Servidor (escritorio) + `desktop_music_client.dart` | Bajo |
| 7 | **Un grupo de conexiones compartido** entre los clientes HTTP y vaciarlo al cambiar de red | Negociaciones TLS repetidas; esperas tras cambiar wifi↔datos | `api_dio.dart`, `authenticated_api_client.dart` | Medio: toca todos los clientes |
| 8 | **Segundo reproductor con la siguiente pista ya preparada** | Salto de 0,7–1,1 s a casi instantáneo; habilita crossfade | `just_audio_track_engine.dart`, `track_playback_controller.dart` | Alto: es el núcleo de la reproducción |
| 9 | **Calentar también** lo que el usuario acaba de ver: resultados de búsqueda, primeras filas de una playlist | Los ≈2,5 s en frío en más casos | `music_mode_screen.dart`, `catalog_pages.dart` | Bajo; gasta datos |
| 10 | **Alternativa opaca al desenfoque** por debajo de Android 12 y ajuste "reducir efectos" | Fluidez en gama baja | `music_mode_screen.dart`, `player_backdrop.dart`, Ajustes | Bajo |
| 11 | **Leer por adelantado el color** de las carátulas vecinas del reproductor | El cambio de color al deslizar deja de llegar tarde | `adaptive_theme.dart`, `cover_color.dart` | Bajo |
| 12 | **Perfiles de arranque (Baseline Profiles)** | Arranque en frío del proceso; Limusic no los tiene | Compilación Android | Bajo; hay que medir si compensa en Flutter |

### Estado tras el APK 4057

| # | Estado | Nota |
|---|---|---|
| 1 | Pendiente | Necesita el endpoint de arranque en el servidor de Render |
| 2 | Hecho, sin probar en el teléfono | Conexión del canal y primera página de Inicio guardadas por cuenta (`music_boot_cache.dart`) |
| 3 | Hecho, sin probar en el teléfono | `resolved_sources.json` en la caché de la app |
| 4 | Hecho, sin probar en el teléfono | Álbum y artista; las playlists siguen con su lista de siempre |
| 5 | Hecho, **apagado por defecto**, sin probar en el teléfono | Ajustes → Audio guardado. Usa una API de `just_audio` marcada como experimental |
| 6 | Pendiente | Necesita el cambio en el backend de escritorio |
| 7 | Hecho a medias | Conexiones compartidas contra el servidor de Mysic, inactivas 15 s. No hay aviso de cambio de red: la app no tiene dependencia de conectividad |
| 8 | No hecho | Toca el núcleo de la reproducción; no se hace sin poder probar en el teléfono |
| 9 | Hecho, sin probar en el teléfono | Búsquedas y primeras filas de cualquier lista de canciones |
| 10 | Hecho, sin probar en el teléfono | Ajustes → Reducir efectos. El desenfoque de Flutter no depende de la versión de Android, así que es un ajuste y no un corte por versión |
| 11 | Hecho, sin probar en el teléfono | Siguiente, anterior y la que sigue a la siguiente |
| 12 | No hecho | El código Dart ya va compilado de antemano; el beneficio en Flutter es dudoso y habría que medirlo |

Recomendación de orden: 1 y 6 dependen del servidor y son los de mayor efecto por menor riesgo en la app. En la app, empezar por 3 y 4 (rápidos y seguros), luego 2 y 5.

## 10. Qué no copiar de Limusic

- Peticiones de datos sin tiempo límite ni reintentos.
- Registro completo de cada petición en la versión publicada.
- Sugerencias de búsqueda en cada tecla, sin espera ni cancelación.
- Biblioteca paginada en serie hasta 21 páginas.
- Lecturas de ajustes que bloquean el hilo principal.
- Casi todas las dependencias creadas al arrancar.
- Inserción de canciones en la base de datos una a una.
- Un flujo de base de datos abierto por cada fila de canción para saber si está descargada.
- Caché de audio sin límite por defecto.
- Dependencia de tablas de cifrado alojadas por terceros.
- Uso de servicios internos de otras empresas (NetEase, QQ, KuGou, token de Apple Music) sin acuerdo.

## 11. No verificado

- **Tiempos reales de Limusic.** No se ejecutó. Todos sus costes son conteo de peticiones.
- **Búfer de 200 000 ms.** Sale de multiplicar por 4 el valor por defecto de Media3 1.11.1 (50 000 ms), leído del código fuente en la web, no de la librería compilada.
- **HTTP/2 y tamaño del grupo de conexiones.** Limusic no los configura; rigen los valores por defecto de OkHttp 5.5.0 y Ktor 3.6.0, no comprobados.
- **Caché de imágenes en memoria de Limusic.** Sin configurar; valor por defecto de Coil no comprobado.
- **Hueco entre pistas en Limusic** y coste de abrir la salida de audio: no medidos.
- **Reproductores precargados huérfanos** (sección 2.5): deducido de la lectura.
- **Si las dependencias "al arrancar" de Limusic se crean de verdad al iniciar:** un comentario del propio repositorio sugiere que no siempre.
- **En Mysic:** el toque en frío sobre una canción fuera del collage no se midió en el 4055; el salto de pista no se midió antes de adelantar la URL, así que no hay cifra de mejora; el arranque con el servidor de Render dormido no se midió; en una prueba el registro mostró dos cargas seguidas de la misma canción tras un toque y no se aclaró la causa; el arreglo del cierre al salir con "atrás" (APK 4056) está pendiente de confirmar en el teléfono.

---

# Segunda ronda de análisis

Cinco análisis más, todos de solo lectura: tres sobre Limusic (`dev`) y dos sobre el código propio (la app móvil y los dos servidores). Nada se ejecutó; donde se cita una cifra es del código o de las mediciones de la sección 2.4.

## 12. Cola, radio, descargas e historial en Limusic

### 12.1 Cola

- **Una sola lista plana** en orden de reproducción más un puntero a la pista actual (`QueueState.kt:17-52`). Cada pista lleva marcas: "a continuación", "añadida a la cola", "de autoplay".
- **Vive en el servicio, no en el reproductor.** Cada cambio vuelca la lista al reproductor; este solo recarga audio si cambió la pista actual, y si solo cambió la siguiente rehace la precarga.
- **Canción suelta** (Inicio, búsqueda, artista): la cola es esa canción, suena ya, y después se pide su radio y se añade detrás (`MediaServiceHandlerImpl.kt:1072-1089`).
- **Álbum o playlist:** la lista ya cargada; el resto de páginas se recorre **en segundo plano nada más empezar**, con tope de 50 páginas (`:1179-1196`). No espera a acercarse al final.
- **Sin tope de pistas futuras.** El historial se recorta a 200 pistas ya oídas.
- **Aleatorio:** reordena la propia lista y guarda copia para deshacer; el modo aleatorio del reproductor queda apagado. Baraja solo lo que viene después de la actual.
- **Anterior:** si la posición pasa de 3 s, reinicia la pista; en la primera pista de una cola nueva, vuelve a la cola anterior.
- **"A continuación"** va tras la actual en orden de llegada; **"añadir"** va al final pero delante del autoplay. Una pista ya pendiente se mueve, no se duplica.
- **Contador de generación:** una respuesta de red de una cola ya reemplazada se descarta.

### 12.2 Radio y autoplay

| Aspecto | Valor |
|---|---|
| Endpoint | Siempre `next`, con semilla `RDAMVM<id>` (canción) o `RDAMPL<id>` (playlist o álbum) |
| Cuándo se pide | Al tocar una canción (tras arrancar el audio); en cada cambio de pista si quedan 2 o menos; al terminar la última; al pulsar Siguiente en la última |
| Cuántas | 20 por petición |
| Duplicados | Se descarta lo que ya está en la cola |
| Orden | Primero lo no escuchado en 30 días |
| Por defecto | Activado; con repetición activa no hay autoplay |

### 12.3 Descargas y uso sin red

- 3 canciones en paralelo, 3 reintentos (`DownloadUtils.kt:184-194`).
- **Dentro de una canción, trozos de 4 MiB uno tras otro**, sin el parámetro `range=` en la URL. El propio código documenta por qué: una petición abierta baja a 32 KB/s frente a 9,4 MB/s por trozos (`ChunkedDataSource.kt:12-22`).
- Una sola consulta de resolución a la vez y 3 s como mínimo entre consultas. Un 429 pausa todas las descargas.
- Sin red: el reproductor comprueba primero si la pista está entera en disco y, si no, falla al instante sin consultar nada.

Consecuencia para Mysic: el audio guardado del punto 5 del plan descarga cada canción con **una petición abierta**, justo el caso lento que Limusic evita. Reproducir no se ve afectado (va a velocidad de escucha), pero la canción tardará casi su duración en quedar guardada. Hay que comprobarlo en el teléfono antes de activar la opción por defecto.

### 12.4 Historial

- Al cambiar de pista suma una reproducción y marca la fecha. **Sin umbral de tiempo.**
- "Recientes": las 500 últimas, una fila por canción. "Más escuchadas": las 50 con más reproducciones.
- No hay registro por evento con segundos escuchados (la tabla existe pero nada escribe en ella).

### 12.5 Gestos

- Mini reproductor: toque o deslizar arriba (60 px) abre; deslizar horizontal (120 px) cambia de pista.
- Carátula: el salto se ejecuta al terminar el gesto. Deslizar arriba 40 dp abre la cola.
- Temporizador: 5 a 60 min o "fin de la canción"; fundido de 5 s con curva coseno y 0,8 s de silencio antes de pausar.

## 13. Base de datos y biblioteca en Limusic

### 13.1 Qué guarda y cómo

- Una base SQLite (Room, versión 29, 25 tablas, 46 migraciones). Canciones, álbumes, artistas, playlists, playlists propias con su tabla de posiciones, historial de búsqueda, cola.
- **Sin índices secundarios** en las tablas principales: los filtros "me gusta" y "descargada" recorren la tabla entera. No copiar.
- Solo 13 consultas son observadas (se reemiten al cambiar la tabla); el resto son lecturas únicas.
- Lee tablas enteras por páginas de 100 con desplazamiento. No copiar.

### 13.2 Qué pinta la Biblioteca sin red

- **Cuatro tarjetas** (Me gusta, Seguidos, Más escuchadas, Descargas): cuenta más las 3 carátulas más recientes, observadas. Un "me gusta" en cualquier pantalla mueve la tarjeta.
- En total unas 15 consultas locales y ninguna petición sin sesión.
- **Con sesión, álbumes, artistas y canciones van a la red sin caché**, y el estante de playlists espera a la respuesta. Es su punto débil; Mysic puede evitarlo.

### 13.3 "Me gusta" y ediciones

- **Primero se escribe en local y la interfaz cambia al instante; después va la petición.** Si falla, se revierte y se avisa. Sin reintentos ni cola.
- Lo hecho sin sesión se apunta como "pendiente de sincronizar" y **gana a la respuesta del servidor**.
- Un contador de época descarta respuestas pedidas antes de un toque.
- Lo recién creado en YouTube se mantiene en memoria y se pinta delante hasta que el servidor lo lista (YouTube tarda segundos).
- Sincronización de "me gusta": cada 30 min como mucho, 6 h tras un fallo, 1,5 s entre páginas, y corta en la primera página con un "me gusta" ya conocido.

### 13.4 Para Mysic

Mysic no tiene base de datos local: guarda archivos JSON pequeños. Opciones, por orden de esfuerzo:

1. **Seguir con JSON** para lo que ya se guarda (perfil, conexión, Inicio) y añadir la lista de playlists y los "me gusta" recientes. Vale hasta unos miles de filas.
2. **SQLite con `drift`** si se quiere biblioteca completa sin red, con índices en "me gusta", "descargada" y "última escucha".

Lo que conviene copiar con cualquiera de las dos: escritura local primero con reversión, tarjetas de cuenta más 3 carátulas, y no volver al estado de carga al releer.

## 14. Servicio de medios y segundo plano en Limusic

| Tema | Qué hace Limusic | En Mysic |
|---|---|---|
| Vida del servicio | Sobrevive a deslizar la app fuera, incluso en pausa (ajuste para lo contrario, apagado por defecto) | Por comprobar |
| Reanudar con el reproductor vacío | Un "play" de auriculares o del sistema restaura la cola guardada y reproduce. Sin esto el sistema mataba el servicio | Por comprobar |
| Guardado | Posición cada 5 s mientras suena; cola completa al pausar, cambiar de pista o liberar; la lista solo se reescribe si cambió | No se guarda la cola |
| Lectura de posición | 50 ms con la app visible, **1 s oculta**, y despierta al instante al volver | Siempre al mismo ritmo, también oculta (sección 15, punto 3) |
| Foco de audio | Reanuda solo tras una pérdida transitoria; baja a 0,2 en vez de pausar cuando otra app pide atenuar | El motor pausa en toda interrupción |
| Auriculares desconectados | Pausa. No reanuda sola al reconectar | Pausa |
| Red caída a mitad de pista | Reintenta sin límite: cada 1 s sin red, hasta 5 s con red | Un reintento con URL nueva |
| Error de fuente (403/410) | Hasta 2 reintentos con URL nueva **en la misma posición** | Un reintento, retomando la posición |
| Bloqueos de energía | Sin bloqueo de wifi para pistas ya descargadas | No configurable en la librería |
| Carátula de la notificación | Limitada al tamaño que acepta el sistema (320 dp) | Por comprobar |
| Batería | No pide exención de optimización | No pide |
| Diagnóstico | Registro rotativo a fichero (≈4 MB) con línea temporal de reproducción y origen de cada orden | Solo registro del sistema |

Android Auto, widget de pantalla de inicio y ecualizador propio existen en Limusic; no afectan a la velocidad.

## 15. Auditoría de rendimiento de Mysic móvil

Hallazgos sobre el código tras el APK 4057. "Confirmado" significa que el código lo hace; la magnitud no está medida.

### 15.1 Confirmado en el código

| # | Qué pasa | Dónde | Arreglo | Riesgo |
|---|---|---|---|---|
| 1 | **Con Mysic de escritorio, el audio no pasa por el resolvedor del teléfono**: ni el calentado ni la precarga hacen nada, y cada toque paga la ruta por el servidor | `music_mode_controller.dart:96-102`, `track_playback_controller.dart` (`warmTracks`) | Probar primero el resolvedor del teléfono y dejar el servidor como respaldo | Medio |
| 2 | **El tema de toda la app se anima 450 ms en cada cambio de carátula**, reconstruyendo todo lo que usa el tema, justo mientras se abre el reproductor y carga el audio | `adaptive_theme.dart` | Aplicarlo en un fotograma o tras la transición | Bajo |
| 3 | **Cada aviso de posición (5 por segundo o más) reconstruye pantallas enteras**: el reproductor completo, el mini reproductor, las filas visibles, el collage, el fondo de Inicio. También en segundo plano | `track_playback_controller.dart:43-48`, `player_screen.dart:29`, `player_widgets.dart:15`, `music_tiles.dart:572/704/1080` | Sacar la posición a un aviso aparte que solo escuchen la barra y la letra; pausar oculta | Bajo-medio |
| 4 | **Cada cambio de pista destruye y recrea el reproductor nativo**, y la resolución espera a que termine esa parada | `track_playback_controller.dart` (`_stopEngine`), `just_audio_track_engine.dart` (`stop`) | No parar al cambiar de pista; resolver en paralelo | Medio |
| 5 | **La misma carátula se descarga y decodifica hasta cuatro veces** al empezar una pista; el reproductor se salta la caché de disco | `player_screen.dart:37`, `player_backdrop.dart:44`, `cover_color.dart:39`, `music_tiles.dart:820/1114` | Una sola URL y un solo proveedor con caché | Bajo |
| 6 | **La lista de Inicio recrea todas sus filas en cada reconstrucción**, y hay muchas: 2–3 por cada vuelta a primer plano, más las de las portadas | `music_mode_screen.dart` (`_itemRows`), `music_mode_host.dart:7-15` | Guardar las filas e invalidarlas solo cuando cambian los datos | Medio |
| 7 | **El registro de escuchas escribe en disco cada 10 s para siempre**, aunque no suene nada | `listening_tracker.dart:17` | No hacer nada si no hay cambios | Bajo |
| 8 | Con escritorio, cada vuelta a primer plano pide Inicio entero y luego lo sirve sin mirar su antigüedad | `desktop_music_client.dart:207-224`, `:425-429` | Reverificar solo la cuenta; caducar Inicio a los 30 s | Bajo |
| 9 | El resolvedor guarda su archivo antes de entregar la URL | `DevicePlaybackResolver.kt:310` | Entregar y guardar después | Bajo |
| 10 | Firebase y el servicio de audio se inician uno tras otro antes de pintar | `main.dart:22`, `:33` | En paralelo | Medio |
| 11 | El calentado falta en álbum y artista, y con Inicio leído de disco espera a la red | `catalog_pages.dart`, `music_mode_screen.dart` (`_seedHome`) | Calentar al sembrar y tras cargar álbum o artista | Bajo |
| 12 | La caché de portadas puede no recortarse nunca en sesiones cortas | `disk_cached_image.dart:133` | Un recorte al poco de arrancar | Bajo |
| 13 | Tres sincronizaciones en cada vuelta a primer plano | `connected_host.dart:87`, `music_mode_host.dart:42`, `music_mode_screen.dart:462-468` | No refrescar si la última verificación es reciente | Bajo |

Los puntos 2, 3 y 5 se refuerzan entre sí: al tocar una canción, a la vez se anima el tema de toda la app, se descargan cuatro copias de la carátula y el reproductor se reconstruye entero cinco veces por segundo. Es el momento que el usuario percibe como lento.

### 15.2 Sospechas por confirmar midiendo

| # | Sospecha | Cómo medir |
|---|---|---|
| 14 | Los desenfoques (barra, fondo de Inicio, fondo del reproductor) se recalculan en cada fotograma | Tiempo de dibujo con y sin "Reducir efectos" |
| 15 | La hoja de letras dibuja toda su lista en cada fotograma: máscara sobre todo el desplazamiento y una capa por línea | Ídem, con la hoja abierta |
| 16 | La comprobación del final del archivo cuesta una ida y vuelta por toque (0,6 s en la medición de la sección 2.4) | Ya sale en el registro como `validationMs` |
| 17 | El calentado va de una en una | `queueMs` en el registro |
| 18 | 160 MB de caché de imágenes en memoria es demasiado para un teléfono de 4 GB | Memoria del proceso con 64–80 MB |
| 19 | Si el servidor cambia el contador de actividad con cada escucha, cada vuelta a primer plano remonta todas las pantallas musicales y pierde el desplazamiento | Observar con qué frecuencia cambia |
| 20 | 75 s de tiempo límite en todas las peticiones: una lista puede girar 75 s sin fallar | — |

### 15.3 Lo que está bien

- Las imágenes de las listas se decodifican al tamaño pintado.
- Las peticiones se cancelan al salir de las pantallas principales.
- Las cachés en memoria tienen tope y los controladores se liberan.
- El carrusel del reproductor, la cola y el álbum son perezosos.
- No se encontraron llamadas que fallen solo en la versión publicada.

## 16. Auditoría de latencia de los servidores

### 16.1 Servidor A: API principal (Render)

- **Plan gratuito** (`render.yaml:5`). Se asume que duerme tras inactividad; al despertar pierde además todas sus cachés en memoria.
- **Cada petición verifica el token con comprobación de revocación**, que obliga a consultar a Google. No hay caché de tokens verificados. En el arranque son 4 verificaciones en serie.
- **Sin compresión** en el servidor. Todas las respuestas del arranque van con `no-store`.

| Petición | Qué hace | Coste |
|---|---|---|
| `GET /auth/session` | Solo verifica el token | Redundante: no aporta nada que `/auth/sync` no dé |
| `POST /auth/sync` | Verifica y escribe el perfil | 1 escritura en cada arranque aunque nada cambie |
| `GET …/connection` | Verifica el vínculo con YouTube | En frío: ~6 consultas en serie, 2 llamadas a YouTube en paralelo y 1 a Google. En caliente: 2 consultas |
| `GET …/pages/home` | Lee Inicio | 4 consultas en serie y de 1 a 6 llamadas a YouTube **en serie**. Inicio no se cachea |

- **Inicio se descarga dos veces en frío:** una para verificar el vínculo y otra para servirlo.
- **Unas 11 consultas a la base en serie** en el arranque, varias repetidas (el usuario se lee 4 veces).
- **Las canciones no llevan álbum:** el servidor detecta el dato de YouTube pero solo lo usa como sí o no y descarta el identificador y el nombre (`music-account-catalog.ts:154-156`). Por eso la app hace una búsqueda extra por canción.

### 16.2 Servidor B: backend de escritorio (VPS)

| Petición | Caché | Coste en fallo |
|---|---|---|
| `search` | Memoria y disco: fresca 30 min, servible hasta 24 h con refresco por detrás | 1 llamada a YouTube |
| `album`, `artist` | 15 min | 1 llamada |
| `home` | 90 s por usuario | 1 llamada |
| `radio` | **Ninguna** | 1 llamada cada vez |
| `account` | Ninguna | 1–2 consultas |
| `stream` | URL resuelta 30 min por usuario | Resolución completa |

- **La URL de audio sí se guarda entre peticiones** de la misma canción, pero por usuario.
- **Primer tramo en memoria (256 KB):** solo se llena llamando a `/stream/:id/info` y solo se sirve si se pide desde el byte 0. El propio código cifra en 0,5–0,9 s lo que ahorra. **La app no llama a `/info`**, así que no lo aprovecha.
- **`type=all` devuelve canciones, artistas y álbumes en una llamada;** la app hace tres.
- **Ya devuelve artista, álbum y nombre del álbum** en búsqueda, álbum, radio y artista. La búsqueda extra de la app solo hace falta para lo que viene del servidor A.
- Nginx comprime con gzip y usa HTTP/2 (según la plantilla; lo desplegado no se comprobó).

### 16.3 Propuestas de servidor, por ahorro

| # | Servidor | Cambio | Ahorro | Riesgo | Cambio en la app |
|---|---|---|---|---|---|
| S1 | A | Caché de token verificado 60–120 s | Una consulta a Google en casi todas las peticiones | Bajo-medio: una revocación tarda ese tiempo en aplicarse | Ninguno |
| S2 | A | Endpoint de arranque único (perfil + conexión + Inicio) | De 4 idas y vueltas en serie a 1 | Medio | Una llamada, con las antiguas de respaldo |
| S3 | A | No dormir, o ruta de calentamiento que la app llame al abrir | El mayor si hoy duerme (no medido) | Bajo | Opcional: llamarla antes de tener el token |
| S4 | A | Reutilizar y cachear el Inicio que ya descarga la verificación | Una llamada a YouTube por arranque en frío | Medio | Ninguno |
| S5 | A | Quitar lecturas repetidas a la base | De ~11 consultas a ~4 | Bajo | Ninguno |
| S6 | A | Incluir álbum y su nombre en las canciones | Una búsqueda por canción | Bajo | Leer los campos nuevos |
| S7 | B | Precarga de audio: llamar a `/stream/:id/info` para la pista actual y la siguiente | 0,5–0,9 s por pista con escritorio | Medio | Llamar a `/info` al encolar. **No necesita cambio de servidor** |
| S8 | B | Caché de `radio` 5–10 min | Una llamada al repetir | Bajo | Ninguno |
| S9 | B | Usar `type=all` en la primera búsqueda | 2 de 3 peticiones | Bajo | Cambiar el parámetro |

Variante sin servidor de S2: quitar en la app la llamada a `/auth/session` (es redundante) ahorra una ida y vuelta en cada arranque.

Los archivos de `stream` del servidor B están marcados como generados: un cambio ahí va en su origen o como ruta propia.

## 17. Plan revisado

La segunda ronda cambia las prioridades. Lo más rentable ya no es copiar más de Limusic, sino arreglar lo que la auditoría encontró en el código propio.

### 17.1 En la app, sin tocar servidores

| Orden | Qué | De dónde sale | Riesgo |
|---|---|---|---|
| 1 | Separar el aviso de posición del resto, y pausarlo con la app oculta | 15.1 punto 3; Limusic 14 | Bajo-medio |
| 2 | Aplicar el tema de carátula sin animar toda la app | 15.1 punto 2 | Bajo |
| 3 | Una sola carátula por pista, con caché de disco | 15.1 punto 5 | Bajo |
| 4 | Quitar la llamada redundante a `/auth/session` | 16.3 | Bajo |
| 5 | No escribir el registro de escuchas si no hay cambios | 15.1 punto 7 | Bajo |
| 6 | Calentar al sembrar Inicio y en álbum y artista | 15.1 punto 11 | Bajo |
| 7 | Llamar a `/stream/:id/info` para la pista actual y la siguiente con escritorio | 16.3 S7 | Medio |
| 8 | Usar `type=all` en la primera búsqueda | 16.3 S9 | Bajo |
| 9 | Guardar las filas de Inicio en vez de recrearlas | 15.1 punto 6 | Medio |
| 10 | No destruir el reproductor en cada cambio de pista | 15.1 punto 4 | Medio |
| 11 | Probar el resolvedor del teléfono antes que el servidor con escritorio | 15.1 punto 1 | Medio |
| 12 | Guardar la cola y la posición, y restaurarlas en pausa al abrir | 12.1, 14 | Medio |
| 13 | Autoplay: pedir 20 más cuando queden 2 o menos | 12.2 | Medio |
| 14 | "Me gusta" con escritura local primero y reversión | 13.3 | Medio |

Los seis primeros son de bajo riesgo y atacan el momento del toque, que es donde el usuario nota la lentitud.

### 17.2 En los servidores

Por orden: S3 (no dormir), S1 (caché de token), S6 (álbum en las canciones), S5 (lecturas repetidas), S2 (arranque único), S4 (Inicio cacheado), S8 (radio).

### 17.3 Decisiones pendientes

- **Base de datos local.** Seguir con archivos JSON o pasar a SQLite decide hasta dónde llega la biblioteca sin red.
- **Audio guardado por defecto.** Depende de comprobar en el teléfono cuánto tarda una canción en quedar guardada con una petición abierta (12.3).
- **Segundo reproductor con la siguiente pista preparada.** Sigue pendiente; el punto 10 de 17.1 es un paso previo y más seguro.

## 18. No verificado en la segunda ronda

- Ningún tiempo de Limusic ni de los servidores: todo es lectura de código.
- Que el plan gratuito de Render duerma el servicio y cuánto tarda en despertar.
- Que la verificación de token con revocación haga exactamente una consulta a Google por petición.
- La configuración real de Nginx en el servidor (solo se leyó la plantilla).
- Si el reproductor de Mysic acepta el primer tramo de 256 KB que sirve el servidor B y pide el resto.
- En Limusic: el comportamiento heredado de la librería de medios (primer plano al pausar, doble pulsación de auriculares, ritmo de la notificación); cuántas pistas devuelve cada petición de radio; la acumulación de reproductores precargados.
- En Mysic: la magnitud de todos los hallazgos de la sección 15; los de 15.2 son hipótesis.
- El servicio de medios de Mysic (qué pasa al deslizar la app fuera, reanudar con la cola vacía, tamaño de la carátula de la notificación) no se auditó.

## 19. Estado actual (APK 4090)

La arquitectura vigente está en [`21-arquitectura-movil-ytm.md`](21-arquitectura-movil-ytm.md). Lo que sigue resume qué punto de este plan quedó hecho, cambió de sentido o sigue pendiente.

### 19.1 Qué cambió respecto al plan

- **Mysic de escritorio y Render salieron del camino de los datos.** Los hallazgos 1 y 8 de 15.1, las propuestas S1–S8 de 16.3 (todas eran de servidor) y los puntos 7 y 11 de 17.1 quedan **sin objeto**: la app habla directo con YouTube Music desde el teléfono, como Limusic, y el audio se resuelve en el teléfono.
- **Base de datos local**: la decisión pendiente de 17.3 está resuelta con SQLite (`mysic_listens.db`) para Recientes y Lo más oído.
- **Sin servidor no hay arranque en frío de Render ni salto a la UE.** Las recomendaciones de la sección 6 de "Qué hacer para mejorar la velocidad" (despertar Render, mover Supabase) ya no aplican a la app móvil.

### 19.2 Peticiones y navegación (medido en el teléfono)

| Caso | Antes | Ahora |
|---|---|---|
| Peticiones `browse` al abrir la app | ~13 en 4 s (encadenaba páginas y cargaba 10 páginas de Me gusta) | 2–3 |
| Cambiar de pestaña 5 veces | Inicio se volvía a actualizar | Sin peticiones de Inicio (solo la primera visita a Biblioteca) |
| Collage "Accesos directos" al abrir | Dos composiciones seguidas, y rotaba cada 6 s | Una sola, la guardada de la vez anterior, sin rotar |

Causas corregidas: el scroll infinito se disparaba sin desplazamiento (una lista corta encadenaba páginas), la carga de Me gusta repetía hasta 10 páginas en cada arranque (ahora solo si lo guardado tiene más de 30 min) y el collage se calculaba con datos parciales y luego completos.

### 19.3 Tiempos de reproducción

Los medidos antes del cambio de arquitectura siguen siendo la referencia (toque en frío ≈ 1,65 s; canción calentada ≈ 0,45–0,65 s) y **no se han repetido** con el APK 4090. En el registro del teléfono se vieron preparaciones de 224 ms con la URL ya resuelta. Para mejorarlos, ver [`22-reproduccion-instantanea.md`](22-reproduccion-instantanea.md).

### 19.4 Qué sigue pendiente

- Segundo reproductor con la siguiente pista ya preparada (17.3); ver 22.
- Recordar la pausa de "Registrar escuchas" al reiniciar.
- Corazón en el mini reproductor y en el reproductor de la app; chips de ambiente como Inicios reales.
- Decidir si se apagan los servidores sin uso (Render, Supabase, backend de escritorio).
- Medir otra vez la reproducción con el APK actual.

### 19.5 El collage no es el de YouTube Music, a propósito

El "Accesos directos" de YouTube Music lo arma YouTube con las recomendaciones de la cuenta. Con la sesión de YouTube Music ya se lee el Inicio real, pero el collage propio mezcla **lo tuyo** (lo más escuchado, lo reciente, los Me gusta y tus playlists, una playlist cada tercera tarjeta). Se compone una vez y se guarda para que no cambie delante del usuario; el botón Actualizar lo renueva.
## Anexo A · Abreviaturas de archivo (Limusic, rama `dev`)

| Abrev. | Archivo |
|---|---|
| `M3` | `core/media/media3/src/main/java/com/simohypers/limusic/media3/di/Media3ServiceModule.kt` |
| `XF` | `core/media/media3/.../media3/exoplayer/CrossfadeExoPlayerAdapter.kt` |
| `LS` | `core/media/media3/.../service/mediasourcefactory/LiveStreamPlayback.kt` |
| `EXT` | `core/media/media3/.../extension/Media3Ext.kt` |
| `MH` | `core/data/src/androidMain/kotlin/com/simohypers/limusic/data/mediaservice/MediaServiceHandlerImpl.kt` |
| `SR` | `core/data/src/commonMain/.../data/repository/StreamRepositoryImpl.kt` |
| `DSM` | `core/data/src/commonMain/.../data/dataStore/DataStoreManagerImpl.kt` |
| `YT` | `core/service/kotlinYtmusicScraper/src/commonMain/.../kotlinytmusicscraper/YouTube.kt` |
| `YM` | `core/service/kotlinYtmusicScraper/src/commonMain/.../kotlinytmusicscraper/Ytmusic.kt` |
| `ENG` | `core/service/ktorExt/src/androidMain/.../ktorext/Engine.android.kt` |
| `CFG` | `core/common/src/commonMain/.../common/Config.kt` |

Los archivos citados por nombre (`HomeViewModel.kt`, `App.kt`, `UIExt.kt`, etc.) están bajo `composeApp/src/commonMain/kotlin/com/simohypers/limusic/`.

## Anexo B · Cómo medir en Mysic

- Registro del teléfono: `adb logcat -s MysicPlayback:* flutter:*`.
- `device_resolution`: resolución de la URL, con `extractorMs`, `validationMs` y `cacheHit`.
- `device_warm`: cada canción adelantada al abrir Inicio.
- `audio_player_preparation`: preparación del reproductor.
- `audio_first_progress`: del toque al primer avance de posición.
- Arranque en frío: `adb shell am force-stop com.mysic.mysic`, luego `adb shell am start -n com.mysic.mysic/.MainActivity` y capturas seguidas.
- Comparar siempre el mismo caso antes y después, con el servidor en el mismo estado (despierto o dormido).
