# 30 · Radio en directo

## Qué hace

El Inicio tiene un bloque **Radio** bajo el primer carrusel (orden: collage
«Accesos directos» → carrusel → radio). Cada emisora es un rectángulo con su
degradado, su nombre y su dial («78.9 FM»). Tocarlo sintoniza y suena el
directo; el reproductor muestra «EN VIVO» en lugar de la barra de progreso.
De fábrica viene **Shonan Beach FM** (78.9 FM, Kanagawa).

El bloque se apaga desde «Editar Inicio → Radios».

## Piezas

- `features/radio/domain/radio_station.dart`: emisora (id, nombre, flujo,
  dial, dos colores). Solo valen flujos `https` sin usuario ni fragmento
  (Android bloquea el tráfico sin cifrar).
- `features/radio/data/radio_store.dart`: lista guardada en
  `radio_stations.json` (escritura atómica); sin archivo, las de fábrica.
- `features/radio/presentation/radio_shelf.dart`: el bloque del Inicio.
- `CatalogTrack.liveStream` / `liveColors` / `isLive` (id `radio:<id>`): la
  emisora como pista. No tiene duración, ni Me gusta, ni historial, ni pasa
  por el resolvedor de YouTube.
- `TrackAudioEngine.load(liveAudio: ...)`: el motor abre el flujo directamente;
  con «solo canciones descargadas» no abre nada.
- `LiveCover`: portada en degradado (los logos de las emisoras suelen ser
  `.ico`, que no se pueden pintar).

## Logo y lo que suena ahora

- Cada emisora puede llevar `logo` (recurso `assets/images/…` o `https`). El de
  Shonan es su logo oficial en blanco, sobre el degradado; sale a la derecha del
  rectángulo, en la portada del reproductor y en el mini-reproductor.
- El flujo envía metadatos ICY (`StreamTitle`, «Artista - Título»). El motor los
  expone (`TrackAudioEngine.liveTitles`), el controlador los separa
  (`parseLiveTitle`: `liveArtist` / `liveTitle`) y el reproductor, el
  mini-reproductor y la notificación muestran artista y canción; la emisora
  queda como «álbum». Si el flujo no dice nada o dice «… - offline», se ve el
  nombre de la emisora y su dial.

### JSON propio de la emisora (programa, título, artista, carátula)

La web de Shonan Beach FM publica `…/wp-content/uploads/now_play.json`
(`program`, `title`, `aartist` [sic], `imagepath`), que su reproductor web lee
cada 30 s. `RadioStation.nowPlaying` guarda esa dirección; mientras suena la
emisora, el controlador la pide cada 30 s (`liveInfoEvery`; solo `https`, 8 s
de límite, 20 KB como máximo, cualquier fallo se ignora) y muestra la carátula
de la canción en la portada, el mini-reproductor y la notificación, con el
artista, el título y el programa. Si hay JSON, manda sobre el título ICY. Sin
JSON, o si falla, queda el ICY y, sin eso, el logo.

### KDVS 90.3 FM (Davis, California)

Segunda emisora de fábrica. Flujo `https://listen.kdvs.org/stream` (AAC 128
kbps; sin título ICY). Su web (Next.js) lee lo que suena de
`https://kdvs.org/api/spinitron/nowplaying` (Spinitron): programa, locutores y
canción/artista, **sin carátula**; por eso se ve su logo (círculo negro, sobre
gris carbón `#2c2c2c`). `LiveNowPlaying.parse` entiende los dos formatos (el de
Shonan y el de Spinitron). Sin canción en el aire, se muestra el programa como
título y sus locutores como artista. El logo se descargó a 192 px: en la portada
grande se ve algo suave.

### ROVR («Radio Reinvented»)

Tercera emisora de fábrica (`rovr.live`). Emite por **HLS** (LL-HLS, AAC hasta
320 kbps), una señal por huso horario; se usa la principal de su web,
`https://hls-prod.rovr.live/prod/stream_plus00/llhls.m3u8` (UTC). ExoPlayer
reconoce `.m3u8` por la extensión. No tiene dial (se ve «EN VIVO»).

**Lo que suena:** el HLS no lleva marcadores de canción, pero su web pide la
programación a `https://strapi.rovr.live/api/schedules/radio/public?date=<UTC
yyyy-MM-dd HH:mm:ss>` (público, ~35 KB). Trae el programa en el aire
(`show.title`, curadores) y su lista de pistas (`title`, `artist`,
`albumCoverUrl`) más las marcas `tracks_cues` (`start`/`end` en segundos desde
`startTime`). Cada programa es una mezcla continua, así que la pista que suena
es la última cuyo `start` ya pasó (la duración de la pista coincide con su marca,
por eso el cálculo es fiable). La URL guardada lleva `date=now`, que el cliente
cambia por la hora UTC de cada consulta. Sin pista identificable (inicio del
programa, o JSON incompleto) se muestra el programa y su curador. Hay un posible
desfase de unos segundos con el audio (el HLS va ~30 s por detrás).

**Por qué «no encajaba» (huso horario):** ROVR emite una señal por huso horario y
cada una lleva la **programación de su hora local** (su web usa
`/api/streams?filters[offset]=<huso del navegador>` y pide la programación con la
hora de pared del navegador). Antes se usaba siempre UTC (`stream_plus00`), así que en
Lima (UTC-5) se veía «Saturation Point» cuando la web mostraba «Steel Vagina Radio»
(12–2 PM, contador 103:17). Ahora `RadioStation.zoneStream` guarda la plantilla
`…/stream_{zone}/llhls.m3u8`, `streamFor()` la rellena con el huso del teléfono
(`zoneName`: `minus05`, `plus00`… de -10 a +12) y `date=now` es la hora de pared del
teléfono (`LiveNowPlaying.wall/instant`: la programación viene sin zona y se compara
campo a campo). Sin retraso añadido: el contador sale de la hora de pared, como en su web.

**De dónde sale la canción (y por qué Mysic iba una por detrás de la web):** la web de
ROVR **no lee ninguna etiqueta del audio**: calcula la pista por la hora
(`elapsed = (Date.now() − startTime)/1000` y `getTrackIndexFromStitchedOrDuration` sobre
las marcas `tracks_cues` de la programación, comprobado en su JavaScript). Mysic leía antes
la etiqueta ID3 del audio y, medido el 2026-11-25 en la señal de Lima, esa etiqueta cambia
hasta ~4 min 40 s **después** que la programación (p. ej. «Hyperballad» empieza a las 15:09:26
según las marcas, pero la etiqueta del stream pasó de «Blind» a «Hyperballad» a las
15:14:06). Dos relojes que no coinciden: Mysic mostraba «Blind» mientras la web mostraba
«Hyperballad». Regla actual: **con programación, la canción es la de la programación**
(título, artista, discográfica, carátula del álbum o, si no, la foto del programa), igual
que la web, con el mismo cálculo y sin retraso añadido; el sondeo vuelve a preguntar justo
al empezar la siguiente marca (la web cambia en el inicio de la siguiente, que solapa ~2 s con
el final de la anterior) y como mucho cada 30 s. La etiqueta del audio ya no se pide en
la radio principal.

**Moods (sin programación): etiqueta ID3 del audio.** Cada segmento fMP4 del HLS lleva una
caja `emsg` con una etiqueta ID3 (`TIT2` título, `TPE1` artista, `TALB` álbum, `TPUB`
discográfica, `TYER` año, `TXXX/TrackId`). `HlsTrackInfo.fromSegment` la lee;
`fetchHlsTrackInfo` pide el maestro una vez (recuerda la variante de menos calidad:
segmentos de ~40 KB con los mismos metadatos), lee un segmento de hace ~25 s
(`_hlsLagSegments`: el reproductor va ~30 s por detrás del borde del directo,
`PART-HOLD-BACK=30`) y repite cada 15 s (`hlsInfoEvery`). La carátula sale de
`album_art/<TrackId>.jpg`, comprobada con un HEAD (no todas existen; si no, la imagen del
mood). Verificado con un segmento real: «Remember to Remember — Rick Holmes · 12 inch ·
Gold Mink · 2016». Hasta que llega la primera etiqueta no se enseña ninguna canción.
No se verificó cuánto va esta etiqueta respecto al audio que se oye en los moods.

**Controles de una radio (coherentes con la web de ROVR):** un solo botón grande,
**detener / sintonizar** (icono de parar; reanudar vuelve al directo); sin anterior ni
siguiente, repetir, aleatorio, letra, cola ni guardar; el menú (⋮) conserva el
temporizador de apagado y «Detener reproducción» (sin velocidad/tono ni ficha de
canción). Deslizar hacia arriba no abre la cola. El mini-reproductor usa el mismo icono,
sin «siguiente» ni barra de avance, y la notificación del sistema no muestra repetir ni
anterior/siguiente ni permite buscar un punto.

**Pastillas:** son `LibraryChip`, las mismas que los filtros de la Biblioteca.

**Moods = otras señales** (`https://strapi.rovr.live/api/streams/moods/public`):
cada mood (DRIVE, THINK, FEEL, MOVE, en el orden de `mood.order`) es una señal HLS
propia (`mood_<nombre>/llhls.m3u8`). Bajo «Reproduciendo» salen las pastillas
**RADIO · mood · mood…** (`_MoodPills`): la que suena va rellena y tocar otra
cambia de señal (`playQueue` con la pista del mood, que cuelga de la de la emisora
por `CatalogTrack.liveParent`; «RADIO» vuelve a ella). La lista se lee una vez por
emisora (`TrackPlaybackController.liveMoodOptions`, `RadioMood.parseList`). Un
mood no trae «ahora suena»: se ve su nombre y su imagen cuadrada como portada, sin
línea de tiempo. (Las etiquetas del programa —`playlistTags`: BRAIN, DREAM…— se
leen pero ya no se muestran: no son las señales.)

**Reproductor de ROVR** (como su web, todo alineado a la izquierda): artista, canción, y una línea con
la emisora, el programa y «by» el curador, más la discográfica (`track.label`).
Abajo, la **línea de tiempo del programa** (`LiveTimeline`): el contador de lo que
lleva en el aire (`84:01`) y una barra hasta el final del programa
(`startTime`→`endTime`). Los instantes llevan sumado el retraso del streaming
(`LiveNowPlaying.rovrDelay`, 30 s, el que declara su web), que también se resta
al elegir la pista que suena. El controlador vuelve a preguntar justo cuando
acaba la canción (`trackEndsAt`), así el título no tarda hasta 30 s en cambiar.

**Aspecto:** ficha amarilla (`#FFF057`→`#F2CC1C`, el amarillo de su logo) con texto
oscuro (`RadioShelf` elige negro o blanco según la luminosidad del fondo). El
logo es una versión con las placas en negro y las letras recortadas, para que se
vea sobre el amarillo.

**Fila de radios:** `clipBehavior: Clip.none`, como los demás carruseles del Inicio,
y el ancho de la ficha se calcula (`RadioShelf.tileWidthFor`) para que quepan dos y
la tercera asome 40 dp. Con 180 dp fijos, dos fichas llenaban justo la fila y la
tercera empezaba exactamente en el borde: Flutter no dibuja lo que empieza fuera de
la vista, así que no se veía nada.

El título del bloque es **«Radio (Auspiciado por Borregon)»**
(`RadioShelf.title`).

## Decisiones y límites

- La frecuencia no viene en Radio Browser; se guarda en la emisora.
- Consumo orientativo: ~58 MB por hora a 128 kbps.
- Aún no hay buscador para añadir emisoras ni reconexión más allá del reintento único que ya existe.

## Buscar → Artistas

Las fichas de artista de la búsqueda reutilizan `ArtistPhotoTile` /
`ArtistPhotoRow` (cuadradas, como las de la Biblioteca) en lugar de los
círculos propios.
