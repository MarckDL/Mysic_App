# 22 · Reproducción instantánea: qué hace Mysic de escritorio y qué se puede replicar en el teléfono

Fecha: 22 nov 2026. Base: lectura del código de escritorio (carpeta `MUSICAL/Frontend` y `MUSICAL/Backend`, solo lectura) y del código del teléfono (`DevicePlaybackResolver.kt`, `just_audio_track_engine.dart`, `track_playback_controller.dart`). Las cifras de escritorio vienen de `docs/AUDIO_DIRECTO.md` de ese proyecto; **no se midieron de nuevo**. Las estimaciones de ganancia en el teléfono son hipótesis, marcadas como tales.

## 1. La idea central del escritorio

En escritorio el `<audio>` apunta a `http://mysicstream.localhost/<videoId>`: un protocolo propio de Tauri (Rust) resuelve la URL de YouTube **desde la IP del usuario** con el cliente `VISIONOS` y sirve tramos `206` (rangos). El servidor Express (`/stream/:id`) es solo respaldo, y el iframe de YouTube el último recurso.

Resultado documentado (app real, clic hasta audio): pista preparada ≈ 200–390 ms, pista fría ≈ 200–840 ms según la versión. Antes, por el servidor: 0,7–1,5 s.

## 2. Mecanismos del escritorio y su equivalente en el teléfono

| # | Mecanismo en escritorio (archivo) | Valor clave | En el teléfono hoy | ¿Replicable? |
|---|---|---|---|---|
| 1 | **Resolución local con cliente VISIONOS**: un solo `POST youtubei/v1/player`, sin token ni descifrado; elige itag 140 (`resolver.rs`) | ~80 ms por pista (600–1000 ms en frío por servidor) | Resolución con **NewPipe Extractor** (varias peticiones y descifrado) | **Sí, y es lo de mayor efecto en frío** (ver 3.1) |
| 2 | **Caché de URLs en memoria**, renovada 10 min antes de su `expire=` | 200 entradas | Sí: caché LRU de 48 con margen de caducidad, tomando el `expire=` de la URL, **persistida en disco** | Ya hecho (el teléfono incluso persiste) |
| 3 | **Deduplicación en vuelo** (`resolving`, `OnceCell`) | una sola resolución por pista | Sí: `resolveSingleFlight` con un único hilo | Ya hecho |
| 4 | **Warm-up al abrir** (visitante + conexiones TLS + última canción) (`warm_resolver`) | 500 ms menos en la primera del día | Parcial: `warmUp` del resolvedor y calentado de las 4 primeras canciones a la vista | Ampliar (3.2) |
| 5 | **Pre-resolución al pasar el cursor** (80 ms de espera) (`usePlayer.js` `warmSong`) | — | Solo las 4 primeras visibles y la siguiente de la cola | **Sí: al poner el dedo** (3.2) |
| 6 | **Prefetch de detalle** (álbum, artista, playlist) a los 150 ms de intención (`intentPrefetch.js`) | oculta ~450 ms | Se pinta al instante con `PageSeed` y caché de disco, pero la petición empieza al tocar | **Sí: al poner el dedo** (3.2) |
| 7 | **Primer tramo ("head") en memoria**: 256 KB de las pistas preparadas, 12 pistas, 180 s (`resolver.rs`) | abrir la conexión costaba 0,5–0,9 s | **No.** El reproductor abre su propia conexión al tocar | **Sí, con un proxy local** (3.3) |
| 8 | **Reutilización de conexiones** (pool de 4, keep-alive 30 s) | — | El reproductor nativo usa sus propias conexiones; no comparte con el resolvedor | Se resuelve con el proxy local (3.3) |
| 9 | **Rangos acotados** (64 KB, 512 KB, 2 MB) para evitar el límite de ~2× tiempo real de YouTube | — | ExoPlayer pide los rangos que necesita | Ya cubierto por el reproductor |
| 10 | **Reintento con URL nueva** ante 403/410 | 1 reintento | Sí: `refresh=true` y recuperación automática una vez | Ya hecho |
| 11 | **Cadena de respaldo** (directo → servidor → iframe) | 3 niveles | Un solo nivel (NewPipe) | Añadir un segundo extractor propio como respaldo (3.1) |
| 12 | **Perfil de cliente como dato** (`client-config.json`, 24 h, cambiable sin instalador) | 16 KiB | La versión de NewPipe va fija en la app | Opcional (3.1) |
| 13 | **Precarga de la siguiente pista**: resuelve la URL y baja el primer tramo (no crea un segundo `<audio>` para YouTube) | — | Resuelve la URL de la siguiente (`prefetch`); no precarga bytes | Sí: bytes de la siguiente (3.3) y/o lista de ExoPlayer (3.4) |
| 14 | **Caché del servidor y proxy con Range** | 30 min, 500 entradas | Ya no se usa servidor | No aplica |

Lo que el escritorio **no** tiene (para no copiarlo creyendo que existe): carrera entre clientes (`Promise.any`), clientes WEB o TV, caché de audio en disco para streaming (solo descargas explícitas), segundo reproductor con mezcla entre pistas, semáforos de concurrencia fuera del prefetch por intención, ni circuit-breaker formal.

## 3. Propuestas para el teléfono, de mayor a menor efecto

El tiempo de un toque en frío en el teléfono (≈ 1,65 s medido antes del cambio de arquitectura) se reparte entre **resolver la URL** (NewPipe: de 15 ms con caché a ~1,3 s en frío según el registro `audio_source_resolution`) y **preparar el reproductor** (`audio_player_preparation`: de 224 ms a ~2,1 s en el registro). Esa segunda parte es la que el truco del primer tramo ataca en escritorio.

### 3.1 Resolver con un solo `player` (cliente VISIONOS) — frío: mayor efecto
Replicar `resolve_network`: un `POST youtubei/v1/player` con el contexto de `VISIONOS` y `visitorData` (cacheado 12 h), elegir el itag 140. Sin token ni descifrado. En escritorio son ~80 ms; en el teléfono desde la IP del usuario se midió ~100 ms frente a 1,1–1,5 s por el servidor (nota de memoria "Resolver audio en el cliente").
- **Respaldo**: dejar NewPipe como segundo nivel (cadena como en el escritorio).
- **Riesgo**: YouTube puede cambiar o cerrar este cliente; por eso el perfil debe ser un dato actualizable (punto 12) y no un valor en el código.
- **Estimación**: −0,5 a −1 s en un toque en frío (hipótesis; a medir).

### 3.2 Calentar al tocar, no al soltar — barato
- `Listener.onPointerDown` en filas y tarjetas de canción: `warmTracks([pista])` antes de que el dedo se levante (entre el contacto y la liberación pasan ~80–150 ms).
- Lo mismo con playlist y álbum: lanzar la petición de la página al poner el dedo, no al soltar.
- Calentar al detenerse el desplazamiento (no solo al abrir la página), con tope de 4 canciones.
- Esfuerzo bajo, sin riesgo. **Estimación**: −100 a −200 ms por toque.

### 3.2b Más calentado al abrir
Abrir una conexión TLS a `googlevideo.com` y resolver la última canción escuchada, como `warm_resolver` (en escritorio ahorró ~500 ms en la primera reproducción del día).

### 3.3 Primer tramo con un proxy local — ataca la preparación del reproductor
Un servidor HTTP de bucle local (`127.0.0.1`) dentro de la app, como el protocolo `mysicstream` del escritorio:
- Para las canciones calentadas y la siguiente de la cola descarga los primeros 256 KB y los guarda en memoria (12 pistas, 180 s).
- El reproductor se apunta a `http://127.0.0.1:<puerto>/<id>`; al pedir `bytes=0-` recibe el tramo de memoria **sin tocar la red** y, mientras suena, el proxy continúa con rangos acotados usando conexiones reutilizadas (pool con keep-alive).
- Ventaja adicional: el proxy reutiliza la conexión que ya abrió, así que se resuelve también el punto 8.
- `just_audio` ya usa un proxy local para `LockCachingAudioSource`, por lo que la mecánica de reproducir desde `127.0.0.1` está probada; hay que confirmar que `network_security_config.xml` permite texto claro solo a `127.0.0.1`.
- **Riesgos**: más código a mantener (rangos, cancelación, errores 403/410 con URL nueva), y mensajes de caducidad de la URL dentro del proxy. **Estimación**: de ~0,9 s a ~0,2 s de preparación en canciones calentadas (hipótesis, extrapolada de lo medido en escritorio).

### 3.4 Siguiente pista ya preparada en el reproductor
Dejar la siguiente en una lista de ExoPlayer (por ejemplo con `ConcatenatingAudioSource` y `useLazyPreparation: false`), para que "siguiente" y el paso automático no esperen. Es el "segundo reproductor" pendiente de `20` (17.3). El escritorio **no** lo hace para YouTube (solo precarga el primer tramo), así que el proxy del punto 3.3 da casi lo mismo con menos riesgo para la reproducción.

### 3.5 Medir antes y después
El escritorio mide `playback-intent` → `audio-playing` y compara 5 pruebas frías y preparadas por variante. En el teléfono ya hay `device_resolution`, `audio_player_preparation` y `audio_first_progress` en el registro: repetir el protocolo del Anexo B de `20` con el APK actual **antes** de cambiar nada, porque los tiempos de referencia son anteriores al cambio de arquitectura.

## 4. Mediciones del APK 4090 (paso 1, hecho)

Medido en el teléfono real (moto g04s) el 22 nov 2026, con el registro de la app (`device_resolution`, `audio_source_resolution`, `audio_player_preparation`, `audio_first_progress`). Método: reiniciar la app antes de cada medida, abrir "Tus Me gusta", bajar hasta una fila concreta y tocarla; la medida es el tiempo hasta el primer avance de posición. "En frío" = la URL no estaba en la caché del resolvedor (`cacheHit=false`); "resuelta" = estaba (`cacheHit=true`). Muestras pequeñas (4–9 por caso): sirven para el orden de magnitud, no para decimales.

| Caso | n | Resolución | Preparación del reproductor | **Primer sonido** |
|---|---|---|---|---|
| En frío | 7 | 0,9–1,2 s (extractor 0,88–1,03 s) | 0,84–1,7 s | **1,8–2,9 s** (mediana ≈ 2,2 s) |
| URL resuelta | 9 | 0,06–0,14 s | 0,48–1,4 s | **0,62–1,5 s** (mediana ≈ 1,1 s) |
| Resuelta, con "Guardar el audio escuchado" apagado | 3 | 0,09–0,14 s | 0,48–0,89 s | 0,62–1,5 s |

Para comparar, el escritorio: preparada ≈ 0,2–0,4 s y fría ≈ 0,2–0,8 s.

**Lo que dicen los números**
1. Hay **dos bloques de ~1 s cada uno**: resolver la URL (solo en frío) y preparar el reproductor (siempre).
2. Con la URL ya resuelta, la preparación es **~90 % del tiempo**: calentar la resolución **no** puede bajar de ~1,1 s. Esa es la diferencia con el escritorio (~0,7–0,9 s) y es justo lo que el primer tramo en memoria ataca.
3. El proxy de "Guardar el audio escuchado" **no** es la causa: apagarlo no cambia la preparación de forma apreciable (el rango es ancho en ambos casos).
4. La preparación varía mucho (0,5–1,7 s): es red (conexión TLS a `googlevideo.com` y primer byte) más la preparación de ExoPlayer, que el registro no separa. Antes de implementar el proxy conviene separar ambas con una medida más fina (ver 5.4).

## 5. Plan elaborado

El orden cambia respecto a lo propuesto antes: con estos números, el trabajo sobre la **preparación** (5.3) tiene tanto efecto como el de la **resolución en frío** (5.2), y calentar al tocar (5.1) solo ayuda a la resolución.

### 5.1 Calentar al poner el dedo (esfuerzo bajo, riesgo bajo)

- **Qué**: al detectar el contacto (`onPointerDown`) sobre una fila o tarjeta de canción, pedir al resolvedor esa canción antes de que el dedo se levante (pasan ~80–150 ms entre el contacto y la liberación). Lo mismo con playlist y álbum: lanzar su página al contacto, no al soltar.
- **Dónde**: un widget reutilizable `TouchWarm` (envuelve `Listener(behavior: translucent)`) en `music_tiles.dart`, aplicado a `SongRow`, `RankedSongRow`, `TopSongCard`, las casillas del collage, las tarjetas de estante y las de playlist/álbum. Se conecta a `warmTracks([pista])` del controlador de reproducción y, para páginas, a la carga de la página (`PageSeed` ya pinta al instante).
- **Detalles a cuidar**
  - El resolvedor nativo tiene un único hilo: si hay calentados en cola, la resolución de la canción tocada puede esperar detrás (el código ya distingue vuelos "sin dueño"); confirmar que el calentado al tocar **no** retrasa la resolución en primer plano y, si lo hace, cancelar los pendientes al tocar.
  - Tope de 4 calentados simultáneos (`warmLimit`) para no gastar datos con arrastres rápidos.
  - Sin efecto con "Reducir efectos"? No: no es visual, se queda activo.
- **Pruebas**: una prueba de widget que verifique que el contacto llama al calentado una sola vez y **no** reproduce; una prueba del controlador que verifique el tope.
- **Aceptación**: en el registro aparece `device_warm` antes de `device_resolution` para la canción tocada, y la mediana del primer sonido en frío baja ≥ 80 ms (n ≥ 8, mismo método de la sección 4).
- **Marcha atrás**: quitar el widget; nada más depende de él.

### 5.2 Resolver con una sola petición `player` (cliente VISIONOS), con NewPipe de respaldo

Es lo que más ayuda en frío (de ~1 s a ~0,1 s de resolución según el escritorio).

- **Cómo lo hace el escritorio** (`Frontend/src-tauri/src/resolver.rs`, a falta de leer el cuerpo completo de la petición): `POST https://www.youtube.com/youtubei/v1/player?prettyPrint=false&alt=json` con `context.client` = `{ clientName: "VISIONOS", clientVersion: "1.02", osName: "visionOS", osVersion, deviceMake: "Apple", deviceModel: "RealityDevice17,1", userAgent, hl: "en", gl: "US", visitorData }`, cabeceras `User-Agent` y `X-Goog-Visitor-Id`, y el `videoId`. Elige el formato 140 (AAC) y, si no hay, el de mayor bitrate. El `visitorData` sale de `/sw.js_data` (respuesta JSPB con prefijo `)]}'`, posición `[0][2][0][0][13]`) y se cachea 12 h; ante `LOGIN_REQUIRED` se renueva una vez y se reintenta. La caducidad sale del parámetro `expire=` de la URL (se renueva 10 min antes).
- **En el teléfono**: una clase Kotlin `VisionOsResolver` junto a `DevicePlaybackResolver`, con OkHttp (ya es dependencia):
  1. `visitorData` (12 h, en memoria y disco).
  2. `POST player` con el perfil del cliente leído de un **JSON de configuración** (no en el código): `clientName`, `clientVersion`, `osName`, `osVersion`, `deviceMake`, `deviceModel`, `userAgent`. Así se corrige sin publicar un APK si YouTube cambia la versión (el escritorio lo hace con `client-config.json`, 24 h, máx. 16 KiB).
  3. Elegir el formato 140; devolver el mismo `CachedSource` que ya usa el resolvedor (la caché, la persistencia y las validaciones se reaprovechan).
  4. **Cadena de respaldo**: si falla (sin URL, `UNAVAILABLE`, `LOGIN_REQUIRED` tras renovar, o tiempo agotado a los ~4 s), seguir con NewPipe como hoy.
- **Riesgos**
  - YouTube puede cambiar o cerrar ese cliente: por eso el perfil es un dato y NewPipe queda de respaldo.
  - Una URL de este cliente puede comportarse distinto en ExoPlayer (cabeceras o rangos): validar con varias canciones y con "Reintentar" tras caducar.
  - Es una API no oficial; hay que vigilar un contador de fallos en el registro.
- **Pruebas**: pruebas de unidad del analizador de la respuesta (con una respuesta de ejemplo guardada), de la elección de formato, de la lectura del `expire=` y de la cadena de respaldo; en el teléfono, repetir el protocolo de la sección 4 en frío.
- **Aceptación**: resolución en frío mediana ≤ 0,3 s (hoy ≈ 1,0 s) y ningún aumento de errores de reproducción en 30 canciones distintas; el respaldo se ejercita al menos una vez forzando el fallo.
- **Marcha atrás**: un interruptor (`directResolver` en Ajustes avanzados o en la configuración) que lo apaga y vuelve solo a NewPipe.

### 5.3 Atacar la preparación del reproductor (proxy local con el primer tramo)

Es el bloque que queda tras 5.1 y 5.2 (≈ 0,5–1,4 s). Dos caminos; el segundo es el que replica al escritorio.

- **A. Siguiente pista ya preparada en ExoPlayer** (lista de reproducción con la siguiente en cola y `useLazyPreparation: false`): el paso a la siguiente y el automático no esperan. No ayuda al primer toque. Es el "segundo reproductor" pendiente de `20`; el escritorio **no** lo hace para YouTube.
- **B. Proxy HTTP en `127.0.0.1` con el primer tramo en memoria** (lo que hace el protocolo `mysicstream` del escritorio):
  - Las canciones calentadas y la siguiente de la cola descargan sus primeros 256 KB (12 pistas, 180 s en memoria).
  - El reproductor se apunta a `http://127.0.0.1:<puerto>/<id>`; la petición `bytes=0-` se responde **desde memoria** sin red, y mientras suena el proxy sigue con rangos acotados (64 KB, 512 KB y luego 2 MB: los acotados evitan el límite de ~2× tiempo real que YouTube aplica a `bytes=X-`) usando un pool de conexiones con keep-alive. La misma conexión sirve al primer tramo y al resto.
  - `just_audio` ya reproduce desde un proxy local en `127.0.0.1` (para `LockCachingAudioSource`), así que la mecánica está probada; hay que permitir el texto claro **solo** a `127.0.0.1` en `network_security_config.xml`.
  - Ante `403/410` el proxy descarta la URL, resuelve una nueva (`refresh`) y reintenta una vez, como el escritorio.
  - Cancelación: al cambiar de pista se cancela la descarga anterior; solo se atiende la última.
- **Riesgos**: más código crítico (rangos, cancelación, caducidad); cualquier error se oye como un corte. Mitigación: el proxy es opcional (interruptor) y, si falla al abrir, el reproductor cae a la URL directa de hoy.
- **Aceptación**: preparación mediana ≤ 0,3 s en canciones calentadas (hoy ≈ 0,9 s) con las medidas finas de 5.4 y sin cortes en 5 canciones escuchadas 15 s con búfer ≥ 100 s (el criterio que usa el escritorio).

### 5.4 Medir mejor la preparación antes de construir 5.3

Añadir al registro, sin cambiar el comportamiento, la hora de: URL entregada al reproductor → primera respuesta HTTP (primer byte) → `setAudioSource` terminado → primer avance. Con eso se sabe cuánto de ~0,9 s es red (el proxy lo ataca) y cuánto es ExoPlayer (el proxy no). Si la parte de red es menor de ~0,4 s, **no** merece construir el proxy.

### 5.5 Orden de trabajo y decisiones

| Paso | Cuándo | Ataca | Estimación (hipótesis) |
|---|---|---|---|
| 1 | **Hecho** (sección 4) | — | — |
| 5.4 medida fina | Primero, es barato | Decide 5.3 | — |
| 5.1 calentar al dedo | Segundo | Resolución | −80 a −200 ms por toque en frío |
| 5.2 VISIONOS + respaldo | Tercero | Resolución en frío | de ≈ 2,2 s a ≈ 1,3 s en frío |
| 5.3 proxy con primer tramo | Cuarto, solo si 5.4 lo justifica | Preparación (todos los toques) | de ≈ 1,1 s a ≈ 0,4 s con URL resuelta |

Combinando los tres, el objetivo realista es ≈ 0,4–0,6 s con URL resuelta y ≈ 0,6–0,9 s en frío; el escritorio llega a ≈ 0,2–0,4 s porque no tiene la parte de preparación de ExoPlayer y la red de un teléfono es peor. Son **hipótesis**: se confirman o se descartan repitiendo la sección 4 después de cada paso.

**Decisiones del usuario antes de empezar**: si se acepta usar el cliente VISIONOS (API no oficial, con riesgo de cambio) con NewPipe de respaldo; y si el perfil del cliente se sirve desde un archivo propio (por ejemplo en el VPS público) o va dentro del APK.

## 6. Estado de ejecución (APK 4093)

### 6.1 Paso 5.4 (medida fina de la preparación): hecho

- `just_audio_track_engine.dart` registra `audio_player_timeline` (estados y milisegundos del reproductor) y, **solo** en compilaciones con `--dart-define=AUDIO_PROBE=true`, `audio_probe`: una petición aparte a la misma URL con conexión nueva que mide `connectMs` (TCP + TLS) y `firstByteMs`.
- Hallazgo del registro de estados: el reproductor pasa de `loading` (a los ~5 ms) directamente a `ready`; **no** hay un estado intermedio que separe red de preparación, así que el cronómetro de estados no sirve para eso. La sonda de red sí.
- Sonda en 10 canciones (APK de medición 4091): conexión **31–195 ms**; primer byte **8–980 ms** (muy variable: 8–11 ms en unas y 440–980 ms en otras). La preparación medida junto a ellas fue de 466–2008 ms.
- Lectura: la preparación se parece a **un suelo de ~0,45 s** (preparación de ExoPlayer y búfer inicial de 250 ms) **más el primer byte, que es lo variable** (de 0 a ~1 s). Ese primer byte es justo lo que el primer tramo en memoria del escritorio oculta. Es un ajuste aproximado de 10 puntos, no una ley: confirma la **dirección** de 5.3, y estima su ganancia en **~0,2–0,5 s de media (hasta ~1 s en las lentas)** con un suelo de ~0,45 s que el proxy no baja. La ganancia que se había supuesto (de 1,1 s a 0,4 s) es **optimista**; el rango realista es de ~1,1 s a ~0,7–0,9 s en media.

### 6.2 Paso 5.1 (calentar al poner el dedo): implementado, efecto sin confirmar

- Nativo: `DevicePlaybackResolver.kt` tiene el método `touch`: resuelve ya, **sin validar**, y cancela los vuelos de segundo plano de otras canciones y la anticipación (igual que un toque real), para que un toque que llegue después se una a esa resolución. Se registra `device_touch`.
- Dart: `PlaybackSourceResolver.touch`, `TrackAudioEngine.touch`, `TrackPlaybackController.touchTrack` (ignora archivo local, audio licenciado y muestras), widget `TouchWarm` (`Listener` translúcido: no impide tocar, desplazar ni mantener pulsado) aplicado a las filas, las tarjetas de estante, los rankings de "Lo más oído" y las casillas del collage, con un descarte de repeticiones del mismo toque en menos de 1 s.
- Pruebas: 151 pasan (controlador, resolvedor, widget).
- **Medición**: en 3 canciones realmente frías, el toque con el dedo de 120 ms dio 1,48 y 1,52 s de primer sonido y el instantáneo 1,78 s; la resolución pasó de 964 ms a 970 y 745 ms. Son **demasiado pocas y desiguales** (cada fila es otra canción con otro tiempo de extractor) para afirmar una mejora: el resultado es **inconcluso**. La mayoría de las filas probadas ya estaban resueltas por la caché que persiste entre sesiones.
- Pendiente: una tanda de ≥ 8 canciones frías por caso (filas profundas o una cuenta con otras canciones), alternando toque instantáneo y con dedo, que se interrumpió al desconectarse el teléfono.
- **No hecho**: calentar la página de una playlist o álbum al contacto. `MusicModeController.page` no deduplica peticiones iguales: la petición del calentado y la de la pantalla recién abierta serían dos, sin ganancia de red. Requiere antes compartir la petición en vuelo.

### 6.3 Paso 5.2 (resolver con una sola petición `player`): implementado

- `VisionOsClient.kt`: pide `visitorData` a `sw.js_data` (se guarda 12 h en memoria y en `visionos_visitor.json`) y hace **una** petición `player` con el cliente VISIONOS, igual que `resolver.rs` del escritorio. Elige el itag 140 y, si falta, el mayor bitrate mp4/webm. `LOGIN_REQUIRED` renueva el visitante una vez. Plazo de 4 s.
- El perfil del cliente es **un dato**: se puede sustituir con `visionos_client.json` en los archivos privados de la app (validado: textos cortos e imprimibles); lo que va dentro del APK es solo el valor por defecto. Decisión sobre las dos preguntas de 5.5: va dentro del APK con ese archivo opcional de sustitución; no hay servidor propio de perfiles.
- `DevicePlaybackResolver.kt` intenta primero el directo y **cae a NewPipe** si falla o la URL no es de `googlevideo.com`. Tres fallos seguidos lo pausan 10 minutos (un cambio de API cuesta una resolución lenta, no una por canción). Tras un fallo del reproductor (`refresh`) se salta el directo y se renueva con NewPipe validando la cola. Las URLs directas se piden con el `User-Agent` del perfil: se guardan junto a la fuente y se entregan al reproductor como cabecera (o las usa el proxy).
- Interruptor en Ajustes: «Resolver directo con YouTube» (archivo `fast_resolve.txt`, activado por defecto).
- Medido en el teléfono: la resolución directa tarda **0,2–0,7 s** con visitante ya caliente (1,4 s la primera vez del día) frente a ~1,0 s de NewPipe.

### 6.4 Paso 5.3 (proxy local con el primer tramo): implementado

- `LocalAudioProxy.kt`: servidor HTTP en `127.0.0.1` con puerto efímero y un **token aleatorio por ejecución** en la ruta (`/a/<token>/<id>`); otra app del teléfono no puede pedirle audio. Guarda en memoria los primeros 256 KB (hasta 12 canciones, 180 s) de las canciones calentadas (`warm`, `touch`, `prefetch`); la petición `bytes=0-` del reproductor se responde desde memoria. El resto lo pide a YouTube en tramos de 512 KB (hasta el primer MB) y luego de 2 MB, reenviándolo según llega, y ante 403/410 renueva la URL una vez.
- Seguridad de fallo: tras `refresh` el resolvedor devuelve la URL de origen, nunca el proxy, así un proxy roto no atrapa una canción en bucle. En Dart solo se acepta `http://127.0.0.1/a/…` o `googlevideo.com`.
- Interruptor en Ajustes: «Primer tramo en memoria» (`head_proxy.txt`, activado por defecto).
- Medido (un pase, pocas muestras): con el primer tramo ya en memoria el primer byte sale en **~3 ms** (`proxy_first_byte … from=memoria`) y el reproductor llega a `ready` a los **94–239 ms** del toque, frente a ~0,9 s antes. Es una **muestra pequeña y favorable** (canciones calentadas); falta la tanda comparativa con canciones realmente frías.

### 6.6 Navegación completa del APK 4093 y calentado ampliado (APK 4094)

Recorrido de Inicio, Buscar, Recientes, Me gusta, playlist, artista y álbum en el moto g04s; tiempo del toque al primer avance (`audio_first_progress`). Toques con `adb`: orden de magnitud, no decimales.

**APK 4093 (antes).** Con el primer tramo calentado: mediana ≈ 200 ms (103–273, n ≈ 14). Sin calentar: mediana ≈ 980 ms (377–1424, n = 15). Causas halladas: solo se calentaban 4 canciones; el primer tramo caducaba a los 180 s (una canción con la URL guardada tardó 978 ms por eso); cada calentado hacía una sonda de validación en serie; el primer byte de googlevideo tardó 360–1070 ms en los casos lentos y 2–12 ms con el tramo en memoria. La etiqueta `from=memoria` del proxy también se escribe cuando espera una descarga en curso.

**APK 4094 (cambios).** `WARM_LIMIT` (Kotlin) y `warmLimit` (Dart) de 4 a 12, con las repetidas descartadas en Dart; el calentado no valida (`validate = false`: la descarga del primer tramo ya comprueba la URL); 24 tramos en memoria (6 MB) con 15 min de vida (antes 12 y 180 s); 4 descargas de tramos en paralelo (antes 2). Al abrir, el registro muestra 12 resoluciones de ~140 ms y los tramos llegando en paralelo.

| Caso | Antes (4093) | Después (4094) |
|---|---|---|
| Buscar, filas 1 / 6 / 8 | 245 / 860 / 1096 ms | 203 / 250 / 189 ms |
| Recientes | 978 ms (fila 6) | 214 / 220 / 231 / 388 ms |
| Playlist, filas 3 / 6 / 8 | 559 / 1182 / 377 ms | 261 / 267 / 188 ms |
| Artista, filas 5 / 3 | 1182 / 240 ms | 276 / 286 ms |
| Álbum, pistas 2 / 6 / 7 | 235 / 1099 / 182 ms | 198 / 136 / 129 ms |
| Me gusta, dos filas profundas | 666 / 463 ms | 244 / 222 ms |
| Me gusta, filas no calentadas (pasan de las 12 primeras) | — | 498 y 1422 ms |
| Inicio, estante fuera de las 12 primeras | 1198 ms | 1015 ms |

Límite que queda: lo que pasa de las 12 primeras filas de una lista sigue en frío (0,5–1,4 s), porque el calentado solo ocurre al cargar la página. Siguiente paso posible: calentar las filas visibles al detenerse el desplazamiento.

### 6.7 Calentar al detenerse el desplazamiento (APK 4095 y 4096) y vídeos largos

`TouchWarm` (en `music_tiles.dart`) calienta una fila cuando lleva 400 ms construida, **está a la vista y la lista está quieta**; si no, reintenta hasta 24 veces. La primera versión (4095) calentaba toda fila que llevara 400 ms construida: en un scroll de tres páginas se encolaron 69 calentados (en serie, ~140 ms cada uno) y las filas donde el usuario se detenía quedaron al final de la cola (602–1191 ms). Con la versión 4096, tras seis páginas de scroll se calentaron 26 eventos.

Medido en Me gusta (APK 4096), tiempo del toque al primer sonido:

| Filas | Primer sonido |
|---|---|
| Zona ya vista en la medición anterior (6 filas, antes 602–1191 ms) | 193–342 ms |
| Zona **nueva**, nunca tocada (6 filas) | 211–280 ms (mediana ≈ 220) |

Vídeos largos nuevos (resultados de la búsqueda «2 hour mix jazz»), APK 4096:

| Vídeo | Duración | Primer sonido |
|---|---|---|
| Álbum «[full album]» de la playlist jpop | 41 min | 237 ms |
| Cafe Jazz Blues (2 Hours…) | ~2 h | 263 ms |
| Jazz Cafe Music – Coffee Shop Ambience | 121 min | 427 ms |
| Jazz Coffee Shop Music – Relaxing Cafe | 130 min | 414 ms |

Saltos de posición en el vídeo de 130 min (arrastrando la barra): 15 %, 50 %, 65 % y ~97 % funcionan; tras el salto al 97 % la posición ya avanzaba a tiempo real a 1,5 s del gesto (126:15 → 126:21 → 126:26) y el estado del reproductor era `PLAYING`.

**Por qué los saltos no pasaban por el proxy.** En ese teléfono «Guardar el audio escuchado» estaba **activado** (447,6 MB guardados; el valor por defecto es apagado). Con él, `just_audio_track_engine.dart` usa `LockCachingAudioSource`: ExoPlayer lee de un servidor local de `just_audio` (una conexión fija `127.0.0.1` del reproductor a ese servidor) y este descarga el archivo desde la URL del proxy de Mysic (`LocalAudioProxy`). Observado en `/proc/net/tcp6`: con el guardado activado, minutos después de empezar un vídeo de 130 min **no había ninguna conexión abierta hacia el proxy** y la reproducción seguía por el disco, sin red; los saltos no generan `proxy_first_byte`. Lo que no se verificó es que el archivo estuviera ya completo; es lo que cuadra con lo observado.

Con el guardado **apagado** (se restauró después), en un vídeo nuevo de 3 h (180:41, ~175 MB), primer sonido 236 ms, y los saltos sí pasan por el proxy, una petición nueva por salto (`proxy_first_byte … start=<byte>`):

| Salto | Primer byte desde el proxy | Aprox. desde el final del gesto hasta el primer byte |
|---|---|---|
| al 50 % (byte 87,6 M) | 251 ms | ≈ 0,5 s |
| al 95 % (byte 166,6 M) | 841 ms | ≈ 1,1 s |
| atrás al 12 % (byte 19,9 M) | 222 ms | ≈ 0,5 s |

Consecuencias: (1) todas las mediciones de este documento con el guardado activado pasan por esa cadena (proxy → servidor local de `just_audio` → ExoPlayer); la medición de la sección 4 no encontró diferencia en el primer sonido. (2) Con el guardado activado, un vídeo largo se baja entero en segundo plano aunque solo se escuche un momento. **Medido** (APK 4096, wifi, `/proc/net/dev` de `wlan0`, vídeo nuevo «60 Minutes of Relaxation Music», ruido de fondo previo 0,1 KB/s): se recibieron 1,1 MB al 1,2 s y **59,3 MB a los 11,5 s**, a ~6,5 MB/s constantes, sin esperar a la reproducción; el ritmo se frenó al final (55,8 → 59,3 MB en el último segundo), que es cuando el archivo se completa. El «Audio en el teléfono» de Ajustes pasó de 447,6 a **503,2 MB** (+55,6 MB). Es decir, ≈ 58 MB por hora de vídeo, bajados en segundos aunque se escuche un minuto; extrapolando (en el vídeo de 3 h el byte del 95 % era el 166,6 M, total ≈ 175 MB), uno de 2–3 h son ~115–175 MB. El tope de 512 MB del caché (`AudioDiskCache.maxBytes`) hace que el siguiente archivo grande desaloje audio guardado más antiguo. La medición se cortó a los 11,5 s con una guardia (la app se detuvo con `am force-stop` al pasar 56 MB) para no desalojar el audio del usuario; solo cubre un vídeo de 1 h, el resto es extrapolación.

### 6.5 Siguiente

Medir con ≥ 8 canciones frías por caso (interruptores encendidos y apagados), terminar la medición de 6.2 y vigilar que el cliente VISIONOS siga respondiendo (el registro `device_visionos success=` lo indica).