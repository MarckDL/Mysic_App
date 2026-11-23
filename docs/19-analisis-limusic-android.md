# Análisis de Limusic Android y plan de reforma de Mysic Android

Fecha: 2026-11-20. Repositorio analizado: `SimoHypers/limusic-android` (Kotlin, Compose Multiplatform), leído desde su código fuente. Las rutas de Limusic son relativas a `composeApp/src/commonMain/kotlin/com/simohypers/limusic/`.

Este documento tiene dos partes: cómo está diseñado e implementado Limusic, y qué se lleva a Mysic Android (Flutter), qué no, y por qué.

## 1. Por qué la reforma anterior no se notaba

La primera tanda cambió el reproductor, los álbumes, los artistas y el Inicio con secciones. Tres de esas cuatro cosas solo existen en el modo "Mysic de escritorio". En el modo "Canal de YouTube" la app solo muestra canciones en lista, y el tema claro seguía igual. Limusic se distingue sobre todo por su tema y su estructura de pantalla, que se ven en cualquier modo. Por eso la reforma debe empezar por ahí.

## 2. Cómo es Limusic

### 2.1 Tema

Definido en `ui/theme/Color.kt`, `Theme.kt`, `Typo.kt`.

| Papel | Oscuro (por defecto) | Claro |
|---|---|---|
| Fondo y superficie | `#0C090C` | `#FFFFFF` |
| Texto | `#FAFAFA` | `#0C090C` |
| Texto secundario | `#A89EA8` | `#7A697A` |
| Acento (primary) | `#FF2056` | `#C70036` |
| Tarjeta (surfaceContainerHigh) | `#1D161D` | — |
| Superficie más alta | `#262126` | — |
| Borde suave (outlineVariant) | `#292629` | `#E7E4E7` |

- El oscuro es un negro casi puro con tinte magenta y un único acento carmesí. Las superficies se distinguen por tono; casi no hay bordes ni sombras.
- Tipografía: Oxanium para el cuerpo e IBM Plex Sans para títulos. Los tamaños son pequeños: 13 sp para el título de una fila, 11 sp para el artista, 20 sp Bold para el título de sección.
- Radios: 4, 7, 10, 14 y 20 dp. Las carátulas de lista usan 4 dp; las tarjetas, 10 dp.
- Opción "adaptar colores a la carátula": toma un color de la portada (decodificada a 112 px) y gira el acento y los fondos hacia ese tono.

### 2.2 Estructura de la app

- Tres pestañas: Inicio, Buscar, Biblioteca. La barra es un `NavigationBar` estándar con el color del fondo, sin elevación, con una línea divisoria encima y un indicador del acento al 14 % (`ui/component/LimusicNavigation.kt`).
- El mini reproductor es una tarjeta separada sobre las pestañas (`LimusicMiniPlayer.kt`): radio 10 dp, fila de 58 dp, carátula de 42 dp, botón de play circular de 38 dp relleno del acento y una línea de progreso de 2 dp en el borde inferior. Deslizar a los lados cambia de canción; deslizar arriba abre el reproductor.

### 2.3 Inicio

`ui/screen/home/HomeScreen.kt`, `ui/component/HomeSectionStyles.kt`.

- Cabecera con saludo por franja horaria y avatar. Detrás, la carátula en reproducción muy desenfocada.
- Fila de chips de estado de ánimo: píldoras con borde; la seleccionada va rellena del acento.
- Secciones en lista perezosa, con tres formas:
  1. **Quick picks**: carrusel "hero". La tarjeta central ocupa el 74 % del ancho, con alto = ancho × 1,1 y radio 28 dp. El título va sobre la imagen, con un velo oscuro. Tocar la tarjeta lanza la radio de la canción.
  2. **Estantes de canciones**: rejilla horizontal de 4 filas con carátulas de 44 dp.
  3. **Estantes genéricos**: fila horizontal de tarjetas de 160 dp con radio 10 dp. Los artistas llevan imagen circular.
- Título de sección en 20 sp Bold con botón "Más" o "Reproducir todo".
- Carga con esqueletos animados (shimmer), tirar para actualizar y paginación al llegar al final.

### 2.4 Reproductor

`ui/screen/player/NowPlayingScreen.kt`, `content/NowPlayingContentLimusic.kt`.

- Fondo: la carátula decodificada a 256 px con desenfoque de 80 dp y un lavado del color de fondo entre el 50 % y el 75 %.
- Carátula en un paginador sobre la cola: deslizar cambia de canción. Radio 16 dp y sombra teñida.
- Título grande con marquesina y corazón en la misma línea; artista debajo.
- Barra de progreso ondulada que se aplana en pausa.
- Controles en tres píldoras rellenas del acento: anterior y siguiente de 80×64 dp, play de 120×80 dp.
- Fila inferior de cuadrados con borde de 44 dp: playlist, repetir, letra, aleatorio y cola.

### 2.5 Álbum y artista

`ui/screen/other/AlbumScreen.kt`, `ArtistScreen.kt`, `ui/component/CollectionHeader.kt`.

- Imagen a sangre fundida con el fondo mediante un velo suave.
- Antetítulo en mayúsculas, título de 28 sp Bold y, a su derecha, Aleatorio y un Play circular de 52 dp relleno del acento.
- El artista muestra una línea con `suscriptores • reproducciones` tal como las devuelve YouTube. No hay un dato propio de "oyentes mensuales".

### 2.6 Implementación y rendimiento

- **Imágenes** (Coil 3): caché en disco de 512 MB y fundido al aparecer. Los fondos desenfocados se decodifican pequeños a propósito (96 y 256 px).
- **Listas**: todo es perezoso (`LazyColumn`, `LazyRow`), con `key` por elemento.
- **Estado**: `derivedStateOf` para no recomponer por cada cambio de scroll o de posición.
- **Tocar una canción lanza su radio** (`MediaServiceHandlerImpl.kt`, `playSong`): la canción suena de inmediato y la cola de relacionadas se rellena después. Un contador de generación descarta respuestas que llegan tarde.
- **Precarga**: la siguiente canción espera preparada y en pausa.
- **Letras**: varios proveedores en orden configurable.

### 2.7 Biblioteca

`ui/screen/library/LibraryScreen.kt`, `ui/component/LibraryTilingBox.kt`.

- Barra superior con título y acciones (nueva playlist, historial).
- Fila de chips con icono: Todo, Playlists, Álbumes, Artistas, Canciones, Descargas, Podcasts. El contenido cambia con un fundido.
- Pestaña "Todo":
  1. Cuatro teselas fijadas en 2×2 (Me gusta, Descargas, Más oído, Artistas). Tarjeta de 72 dp de alto y radio 18 dp, con un cuadro de icono de 40 dp (acento al 16 %) y la última carátula fundida desde la derecha.
  2. Estante horizontal de playlists, con una tesela "Nueva playlist" al principio.
  3. Lista "Añadido recientemente".
- Playlists, álbumes y descargas van en cuadrícula de al menos 3 columnas: carátula 1:1 con radio 10, título a dos líneas.
- Artistas y canciones van en lista.
- No hay buscador ni conmutador de orden dentro de la pantalla.

### 2.8 Búsqueda

`ui/screen/other/SearchScreen.kt`, `ui/component/MoodCategoryCard.kt`.

- Título grande que se desvanece al hacer scroll y barra en píldora.
- En reposo: búsquedas recientes en chips y secciones de "Moods & Genres" con teselas de radio 20, cuyo fondo mezcla la tarjeta con el color de la categoría al 14 %.
- Resultados con chips de filtro (Todo, Canciones, Vídeos, Álbumes, Artistas, Playlists) y una tarjeta de "mejor resultado" con la carátula desenfocada de fondo.

### 2.9 Miniaturas y "sonando ahora"

- Limusic no recorta a cuadrado los vídeos: los muestra en tarjetas 16:9. Las carátulas cuadradas se piden reescribiendo la URL (`=w544-h544`).
- La fila que está sonando lleva un velo negro al 45 % sobre la carátula con seis barras animadas. En tarjetas y cuadrículas no hay resaltado.

## 3. Qué se lleva a Mysic Android

| Elemento de Limusic | Decisión en Mysic | Estado |
|---|---|---|
| Tema oscuro `#0C090C` con acento carmesí | Se adopta como tema por defecto. El claro se conserva en el código. | Esta tanda |
| Barra de pestañas plana con divisor | Se adopta. | Esta tanda |
| Mini reproductor en tarjeta, play circular, gestos | Se adopta. | Esta tanda |
| Saludo por franja horaria en Inicio | Se adopta. | Esta tanda |
| Carrusel "hero" de Quick picks | Se adopta para las primeras canciones del Inicio. | Esta tanda |
| Estantes horizontales de tarjetas | Hecho (build 4031). | Hecho |
| Fila de canción compacta (carátula 48 dp, 13/11 sp) | Se adopta. | Esta tanda |
| Fondo del reproductor con la carátula desenfocada | Se adopta en versión oscura. | Esta tanda |
| Controles en píldoras del acento | Se adoptan. | Esta tanda |
| Fila de cuadrados con borde | Se adopta para Letra, Cola y Dispositivos. | Esta tanda |
| Paginador de carátulas | Hecho; aquí se muestran además las vecinas a los lados, como pide el diseño de referencia. | Hecho, se ajusta |
| Barra de progreso ondulada | Se mantiene la forma de onda con aguja ya hecha. | Hecho |
| Play circular de 52 dp en álbum y playlist | Se adopta. | Esta tanda |
| Radio al tocar una canción | Hecho para el modo de escritorio (`youtube/radio/:id`). | Hecho |
| Listas perezosas y decodificación al tamaño pintado | Hecho. | Hecho |

Segunda tanda (builds 4033–4036):

| Elemento | Decisión en Mysic | Estado |
|---|---|---|
| Collage de acceso rápido (YouTube Music) | Cuadrícula 3×3 con título sobre la portada y marco blanco en la que suena. | Hecho |
| Accesos directos bajo el collage | Fichas de dos columnas. | Hecho |
| Chips de ambiente | Cada chip llena el Inicio con una búsqueda; el catálogo no ofrece Inicio por estado de ánimo. | Hecho |
| Estante de canciones en 4 filas | Las canciones que no caben en el collage. | Hecho |
| Teselas fijadas 2×2 de la Biblioteca | Me gusta, Artistas, Recientes y Lo más oído, según permita la conexión. | Hecho |
| Chips con icono en la Biblioteca | Se adoptan. | Hecho |
| Playlists en cuadrícula de 3 columnas | Se adopta en la Biblioteca. | Hecho |
| Miniaturas de vídeo | Mysic las recorta a cuadrado ampliándolas 4/3, para quitar las franjas negras de `hqdefault`. Limusic las deja en 16:9. | Hecho |

Diferencias deliberadas respecto a Limusic:

- **Álbum con disco de vinilo** y **artistas en cuadrícula con el nombre dentro de la foto**: vienen de las imágenes de referencia, no de Limusic.
- **Doble inicio de sesión**: se conserva (Google y Mysic de escritorio). Limusic no tiene cuentas propias.

## 4. Qué queda fuera de esta tanda

- **Tipografías Oxanium e IBM Plex Sans**: hay que incluir los archivos de fuente en el proyecto. Se sigue con Roboto.
- **Caché de imágenes en disco**: Flutter no la trae. Añadirla exige una librería que hoy rompería las pruebas de widgets; conviene hacerlo aparte.
- **Color del tema desde la carátula** en toda la app: hoy solo tiñe el reproductor.
- **Shimmer y tirar para actualizar** en Inicio y Biblioteca.
- **Pantalla de Búsqueda** al estilo Limusic (teselas de géneros, tarjeta de mejor resultado, filtros).
- **Estante de playlists en Inicio** y **"Nueva playlist"** en la Biblioteca: exigen consultas y permisos de escritura que hoy no se usan.
- **Última carátula fundida** en las teselas de la Biblioteca.
- **Cabeceras a sangre** en álbum y artista, y barras superiores con desenfoque al hacer scroll.
- **Precarga de la siguiente canción** en el modo de escritorio y proveedores de letras adicionales.
- **Indicador de "sonando ahora"** sobre la carátula de la fila.

## 4.1 Estado del proyecto frente a Limusic (2026-11-21)

Revisado contra el código de Mysic Android (`mobile/lib`) y el de Limusic.

**Ya replicado**
- Tema: paleta oscura de Limusic (`#0C090C`, acento `#FF2056`), barra de pestañas plana, tipografías Oxanium (texto) e IBM Plex Sans (títulos), con sus licencias OFL en `mobile/assets/fonts`.
- Mini reproductor en tarjeta con play circular, línea de progreso y gestos (lados: cambiar de pista; arriba: abrir).
- Inicio: saludo por franja horaria, chips de ambiente, collage 3×3 con marco en la canción que suena, accesos directos, estante de canciones en cuatro filas, estantes horizontales de tarjetas, radio al tocar una canción.
- Reproductor: carrusel de portadas con las vecinas, fondo con la carátula desenfocada, barra con forma de onda, píldoras del acento y cuadrados con borde.
- Biblioteca: teselas fijadas, chips con icono y playlists en cuadrícula.
- Artista (cabecera 1:1 a sangre) y álbum (portada con medio vinilo), enlazados entre sí y desde cada canción.
- Búsqueda: estado en reposo con búsquedas recientes y géneros, y filtros de canciones, artistas y álbumes.
- Rendimiento: listas perezosas, portadas decodificadas al tamaño que se pinta y pedidas al tamaño de URL adecuado, esqueletos de carga, tirar para actualizar.
- Indicador de "sonando ahora" (seis barras animadas sobre la carátula).

**Añadido en la tercera tanda (build 4042)**
- **Caché de portadas en disco** (`core/images/disk_cached_image.dart`): cada portada https se guarda una vez en la carpeta de caché del sistema (tope de 256 MB, se borran las menos usadas), se decodifica al tamaño con que se pinta y la memoria de imágenes sube a 160 MB. Limusic usa 512 MB; 256 es suficiente para el catálogo que se ve en un teléfono.
- **Color adaptado a la carátula** (`core/images/cover_color.dart`, `app/adaptive_theme.dart`): se muestrea la portada a 48 px, se elige el tono con más peso (ignorando blancos, negros y grises) y se derivan las reglas de Limusic: acento en tono 70 con croma mínima de 30, contenedor del acento en tono 30 y fondos con croma 10 en su propio tono; texto y bordes no cambian. Activado por defecto, con un fundido de 450 ms entre canciones.
- **Sección "De one pe"** en el Inicio (el `ShortcutsSection` de Limusic): tarjetas de 56 dp con la portada pegada a la izquierda o un cuadro con icono para las colecciones; hasta ocho (Me gusta, Artistas, Recientes y playlists de la cuenta). En Limusic los fija el usuario a mano; aquí se rellenan solos.
- **Fondo del Inicio**: la carátula de la canción que suena a 96 px con desenfoque 40 y opacidad 0,7, con los dos velos de Limusic; sin canción, un resplandor del acento. Se desplaza con la lista.
- **Teselas de la Biblioteca** con la imagen fundida desde la derecha (opaco → 55 % → transparente) para Me gusta y Artistas.
- **Placeholder de portada**: un degradado de superficie en vez de un hueco mientras carga.

**Añadido en la cuarta tanda (build 4044)**
- **Barras superiores con desenfoque**: la barra de las pantallas de música va encima del contenido, transparente arriba del todo y, al desplazar, el contenido que pasa por debajo se desenfoca (sigma 20, velo del color de página al 60 %, aparece en los primeros 32 dp). En el Inicio el fondo con la carátula llega hasta detrás de la barra.
- **Letras con varias fuentes** (`features/lyrics`): se consultan a la vez, escalonadas 250 ms, con 10 s de presupuesto cada una. Gana la primera letra palabra a palabra; si no hay, la primera sincronizada por línea según el orden de preferencia; en último caso, texto plano. Fuentes: **Better Lyrics** (TTML con tiempos por palabra) y **LRCLIB** (coincidencia exacta y búsqueda con tolerancia de 5 s). El título se limpia de sufijos como "(Official Video)".
- **Estilo Classic de Limusic**: 26 sp en negrita, línea activa al 100 % y escala 1,04, siguientes al 70 %, pasadas al 40 %, bordes que se desvanecen, centrado animado, toque en una línea para saltar a ella, y la línea activa se colorea palabra a palabra a cada fotograma.
- **Desfase** de la letra con pasos de 0,1 s (se guarda entre sesiones) y esqueleto de carga.

**Fuentes de Limusic que no se implementan, y por qué**
- NetEase, QQ y KuGou usan los servicios internos de empresas comerciales, sin API pública ni permiso para terceros.
- El servicio propio de Limusic (`lyrics.limusic.app`) es infraestructura de ese proyecto.
- LyricsPlus y Unison son servicios comunitarios, pero no respondieron a las pruebas, así que no pude comprobar su formato y no escribí código a ciegas.
- Cada fuente nueva recibe el título y el artista de lo que escuchas; mantener pocas reduce a quién se le cuenta.

**Pendiente, por orden de impacto**
1. **"Nueva playlist"** y el estante de playlists de la Biblioteca con mosaicos: exigen escritura en el servidor.
2. **Traducción y romanización** de la letra, y el estilo Apple Music (desenfoque por distancia).
3. **Precarga de la siguiente pista** en modo escritorio y crossfade entre pistas.
4. Gestos del reproductor (doble toque = me gusta, deslizar arriba = cola), estilos alternativos de reproductor, tema claro conmutable y diseño para tablets.
5. Interruptor en Ajustes para el color adaptado y para vaciar la caché de portadas.
**No se replica a propósito:** descargas y podcasts (Mysic Android no los ofrece) y Discord/Listen Together.
## 5. Riesgos

- El tema oscuro por defecto contradice una prueba existente (`mantiene el diseño claro…`), que se actualiza para exigir el oscuro.
- Nada de esto está validado por el mantenedor del repositorio original; es una reforma local sobre la copia de `App_Mysic`.
