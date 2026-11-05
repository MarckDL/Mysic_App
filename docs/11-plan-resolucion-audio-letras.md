# Plan técnico — Resolución completa de audio y letras

Fecha: 4 de noviembre de 2026.  
Estado: en ejecución; Fases 0 a 3 completadas, Fase 4 pendiente.
Decisión: R-007 fue eliminada por instrucción del propietario del proyecto.

## 1. Objetivo

Eliminar el corte reproducible alrededor de 1:09, reducir la latencia de inicio,
habilitar rangos/seek y agregar letras normalizadas sin copiar código GPL de Limusic.

La retirada de R-007 cambia el alcance técnico, pero no convierte las APIs internas
en estables ni elimina riesgos de condiciones de servicio, copyright, bloqueo de IP,
rotación de desafíos, consumo de red o licencias. Esos riesgos se registran y se
aceptan o mitigan por separado; no se presentará el resultado como integración oficial.

## 2. Evidencia y causa actual

- El stream SABR actual reproduce aproximadamente un minuto y después entra en error.
- El estado no es una pausa de `just_audio`; el worker pierde acceso a segmentos.
- Las URLs directas IOS/TV probadas entregan un volumen de bytes proporcional a
  aproximadamente un minuto y luego responden 403.
- `bgutils-js` documenta que StreamProtectionStatus 2 permite inicialmente 1–2 MB
  y que el estado 3 requiere un PoToken válido para continuar.
- Limusic resuelve el mismo problema con firma/`n`, PoToken, varios clientes,
  validación del final del archivo y entrega por rangos.

## 3. Componentes evaluados

### Adaptar mediante implementación propia

1. Registro ordenado de clientes y fallback por capacidad.
2. Firma y transformación `n` dentro de un trabajador aislado.
3. Token de sesión y token ligado al video con caché por TTL.
4. Prueba del último rango antes de aceptar un formato.
5. Lista temporal de combinaciones video/cliente rechazadas.
6. Proxy autenticado de HTTP Range con backpressure y cancelación.
7. Worker persistente y caliente para evitar recrear player/sesión por canción.
8. Proveedores desacoplados de letras, coincidencia por duración y caché.

### Dependencias candidatas

- `youtubei.js` 18.3.0: conservar como cliente InnerTube principal.
- `bgutils-js` 4.x, MIT: candidato Node para BotGuard/PoToken. La versión 4 eliminó
  el generador monolítico; el spike debe usar sus exports actuales, sin copiar ejemplos
  antiguos de la versión 3.
- `jsdom` 26.1.0, MIT y compatible con Node >=18: solo dentro del worker de tokens.
- `googlevideo` 5.0.1: conservar SABR como fallback hasta validar URL directa completa.
- LRCLIB: proveedor inicial de letras; API pública, servidor MIT y sin clave obligatoria.

### No adoptar en la primera versión

- Código de Limusic: GPL-3.0-or-later; solo se reutilizan patrones e ideas.
- Rust/Tauri/Svelte: no pertenecen al stack oficial de Mysic.
- `rustypipe-botguard` como sidecar: agrega toolchain Rust, binario y proceso nuevo.
  Solo se reconsidera si el spike Node no puede producir tokens aceptados.
- `libmpv` en Android: aumenta APK, JNI/NDK y complejidad de `audio_service`.
  ExoPlayer mediante `just_audio` ya reproduce AAC/M4A y soporta HTTP Range.
- BotGuard dentro del APK: expone el runtime al cliente, consume más memoria/batería
  y complica actualizaciones. Se mantiene en backend.
- Cookies de cuenta YouTube en Flutter o PostgreSQL.
- Proveedores de letras Netease/QQ/Kugou/Boidu en el primer incremento: requieren
  revisión individual de API, atribución, disponibilidad y condiciones.
- Almacenamiento completo de canciones en disco o PostgreSQL.

## 4. Arquitectura objetivo

```text
Flutter / just_audio
        |
        | Firebase token + Range
        v
Express /api/v1/playback/audio/:sourceId
        |
        v
PlaybackStreamService
   |        |             |
   |        |             +-- StreamFailureCache
   |        +-- YoutubePlaybackResolver
   |                       |
   |                       +-- youtubei.js client chain
   |                       +-- isolated Token/Cipher Worker
   |
   +-- RangeProxy --------> temporary googlevideo URL
```

El proceso Express nunca evalúa JavaScript remoto. El worker:

- no recibe credenciales Firebase/Admin ni `DATABASE_URL`;
- tiene destinos HTTPS permitidos explícitamente;
- expone por IPC operaciones concretas, no evaluación arbitraria;
- limita tiempo, memoria, cantidad de tokens y tamaño de respuestas;
- no imprime tokens, URLs firmadas, cookies o desafíos completos;
- conserva en memoria player, visitorData y tokens hasta su expiración;
- puede reiniciarse sin derribar Express.

## 5. Fases de implementación

### Fase 0 — Licencias, versiones y prueba aislada

1. Confirmar licencia/versiones de `bgutils-js`, `jsdom` y dependencias transitivas.
2. Crear un spike fuera de las rutas HTTP, con Big Buck Bunny como caso fijo.
3. Obtener visitorData y ejecutar el flujo BotGuard en un proceso hijo restringido.
4. Entregar el token a una sesión `youtubei.js` de la misma identidad.
5. Resolver AAC/M4A y solicitar:
   - primeros 256 KiB;
   - rango posterior al minuto;
   - últimos 256 bytes según `contentLength`.
6. Aceptar el spike solo si los tres rangos responden y la identidad/tokens coinciden.

Criterio de salida: URL completa demostrada sin descargar el archivo entero.

Resultado del 4 de noviembre de 2026: completado. El diagnóstico aislado
`pnpm playback:probe:potoken` generó tokens ligados a la misma sesión y al video,
seleccionó VISIONOS con AAC/M4A y recibió `206 Partial Content` con 256 KiB en
los rangos inicial, posterior a 90 segundos y final. YTMUSIC no fue reproducible
en este caso y WEB no entregó una URL descifrable, por lo que el fallback quedó
respaldado por evidencia. El diagnóstico no imprime tokens ni URLs firmadas.

### Fase 1 — TokenBroker y worker persistente

1. Definir `PlaybackTokenBroker` en aplicación/dominio.
2. Implementar adaptador Node en infraestructura.
3. Mantener una sesión caliente y caché TTL en memoria.
4. Separar token de sesión y token ligado al video según la API vigente.
5. Invalidar una vez ante 403; regenerar y reintentar una sola vez.
6. Implementar apagado, timeout y recuperación de worker caído.

Pruebas: TTL, concurrencia, fallo de bootstrap, reinicio, redacción de logs y
prohibición de entregar un token para otro visitor/video.

Resultado del 4 de noviembre de 2026: completado. `PlaybackTokenBroker` expone
solo un lease opaco con pista y vencimiento; visitorData, tokens y sesión caliente
permanecen en un worker persistente sin acceso a variables privadas de la app. El
adaptador comparte solicitudes concurrentes, conserva leases por TTL, permite
invalidación por video, limita tiempos y reinicia el worker tras fallo. Las pruebas
cubren concurrencia, cancelación, vencimiento, respuesta ligada a otro video y
recuperación. Una prueba real confirmó bootstrap, IPC y reutilización en memoria
con latencia de caché inferior a 1 ms, sin exponer el token.

### Fase 2 — Resolvedor con fallback y validación final

Orden inicial a validar, no hardcodear sin evidencia:

1. WEB_REMIX con firma, `n` y PoToken.
2. VISIONOS cuando entregue URL directa completa.
3. TV_SIMPLY con firma/PoToken.
4. SABR con token como fallback acotado.

Por cada candidato:

1. Verificar playability, solo audio, MIME, codec, DRM y `contentLength`.
2. Descifrar URL sin exponerla fuera del worker/resolvedor.
3. Adjuntar los tokens exigidos por ese cliente.
4. Solicitar el último rango del archivo.
5. Rechazar candidatos que solo entreguen el primer MiB.
6. Guardar el fallo video/cliente con TTL corto y continuar.

Resultado normalizado: cliente, itag, MIME, tamaño, caducidad y URL privada.

Resultado del 4 de noviembre de 2026: completado. El resolvedor persistente prueba
YTMUSIC/WEB_REMIX, WEB, VISIONOS y TV_SIMPLY en orden, exige audio sin DRM con
tamaño y duración válidos, prefiere AAC/M4A y valida los últimos 256 bytes con
`206 Partial Content`. Los fallos video/cliente se conservan dos minutos. Un 403
invalida el token ligado al video y permite exactamente un nuevo intento antes de
continuar con el siguiente cliente. La URL firmada solo viaja por IPC y memoria
interna; se valida nuevamente antes de aceptarla y no se registra ni se entrega en
la API. La prueba real seleccionó VISIONOS, validó 10 271 496 bytes y 634 624 ms,
con 2,8 s en frío y menos de 1 ms desde caché.

### Fase 3 — Proxy HTTP Range y seek

1. Ampliar la ruta autenticada para aceptar rangos válidos.
2. Responder 200 o 206 con `Content-Length`, `Content-Range`, `Accept-Ranges` y MIME.
3. Reenviar rangos al CDN sin cargar el cuerpo completo en RAM o disco.
4. Mantener backpressure, abort al desconectar y máximo de bytes/conexiones.
5. Re-resolver una vez si la URL caduca, conservando el rango solicitado.
6. Evitar que el `RangeProxy` acepte URLs o hosts enviados desde Flutter.
7. Habilitar seek en Flutter solo cuando el backend confirme rangos completos.

Pruebas: rangos inicial/intermedio/final, solicitudes inválidas, cancelación,
renovación, dos usuarios, reemplazo siguiente/anterior y límite global.

Resultado del 4 de noviembre de 2026: completado. La ruta autenticada conserva
`/api/v1/playback/audio/:sourceId`, pero reemplaza SABR por un proxy con
backpressure y rangos simples `start-end`, `start-` y `-suffix`. Responde 200/206
con tamaño, MIME, `Accept-Ranges` y `Content-Range` normalizados; rechaza rangos
múltiples o fuera del archivo con 416. El proxy limita estrictamente los bytes,
cancela al desconectar, conserva el rango tras una única re-resolución por 403 y
solo sigue redirecciones HTTPS dentro de `googlevideo.com`. La prueba real recibió
exactamente 256 KiB al inicio, después de 90 segundos y al final. Flutter habilita
seek en el reproductor y en los controles del sistema. El worker SABR de producción
fue retirado; el diagnóstico aislado permanece como referencia de regresión.

### Fase 4 — Latencia y cola

1. Calentar worker/player al iniciar backend sin resolver canciones.
2. Reutilizar sesión, player y token mientras sean válidos.
3. Mantener una caché pequeña de resoluciones por video hasta antes de expirar.
4. Prefetch solo de resolución para la siguiente pista; nunca del cuerpo completo.
5. Cancelar prefetch cuando cambia/vacía la cola o cierra sesión.
6. Medir por separado token, `/player`, prueba final y primer byte.

Objetivos iniciales de medición:

- primer arranque: menos de 8 s en la red de prueba;
- worker caliente: menos de 3 s hasta el primer byte;
- siguiente/anterior: cambio visible inmediato y audio en menos de 4 s;
- cero nueva consulta Firebase cuando el ID token vigente está en caché.

### Fase 5 — Validación Android

1. Big Buck Bunny: reproducir al menos 3 minutos y llegar al final de una muestra
   elegida sin corte al 1:09.
2. Tres IDs del catálogo: superar 2 minutos, pausar/continuar y seek intermedio.
3. Bloqueo de pantalla y segundo plano durante más de 3 minutos.
4. Anterior/siguiente desde notificación con cola de cinco pistas.
5. Caducidad simulada, desconexión USB/red y reintento único.
6. Logout: detener proxy, worker asociado y metadatos de sesión.

El Sprint 6 solo puede cerrarse si la prueba real supera el límite temporal y CI
permanece verde. Después: commit de cierre, integración en `main` y etiqueta.

### Fase 6 — Letras

1. Crear interfaz `LyricsProvider` independiente de `MusicProvider`.
2. Implementar `LrclibLyricsProvider` desde su documentación pública:
   - identificación `User-Agent`/aplicación;
   - `/api/get` exacto con título, artista, álbum y duración;
   - `/api/search` como fallback;
   - respetar 429/503 y `Retry-After`.
3. Implementar `YoutubeLyricsProvider` como fallback:
   - obtener `lyricsBrowseId` desde `next`;
   - cliente móvil para líneas temporizadas;
   - WEB_REMIX para texto/atribución cuando no haya tiempos.
4. Normalizar `source`, `synced`, `instrumental` y líneas con `startMs/endMs/text`.
5. Seleccionar coincidencia por duración; no aceptar otra versión/remix por nombre.
6. Caché LRU compartida: aciertos largos, fallos definitivos 24 h y errores de red
   sin caché negativa prolongada.
7. Ruta `GET /api/v1/tracks/:sourceId/lyrics`, autenticada y con atribución.
8. Panel Flutter conectado a la posición del mismo controlador de audio, autoscroll
   y estado claro cuando no haya letras.

No se incorporan ocho proveedores de una vez. LRCLIB + YouTube permiten probar el
contrato, la sincronización y la UI antes de ampliar fuentes.

## 6. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Rotación de BotGuard/player | Versiones fijadas, worker reemplazable, pruebas de humo |
| Bloqueo de IP/429 | Límites, caché, backoff y observabilidad por etapa |
| Token ligado a identidad incorrecta | Una sesión coherente y pruebas visitor/video |
| Ejecución de JS remoto | Proceso hijo sin secretos, permisos y destinos acotados |
| Consumo de ancho de banda | Rango bajo demanda, cancelación y cuotas por UID |
| URL caducada durante seek | Re-resolución única del mismo rango |
| Dependencia GPL de Limusic | No copiar ni enlazar su código; implementación propia |
| Letras de versión incorrecta | Coincidencia estricta por duración y atribución |
| Cambio de API LRCLIB | Adaptador aislado, timeout, Retry-After y fixtures |

## 7. Definition of Done del incremento

- El audio no se corta a 1:09 en los casos Android documentados.
- Inicio, seek, anterior/siguiente, fondo y bloqueo funcionan con el mismo estado.
- No se almacenan canciones completas ni URLs/tokens en logs o PostgreSQL.
- Tokens y código dinámico permanecen fuera del proceso Express.
- Pruebas backend, PostgreSQL, Flutter y APK pasan en CI.
- La prueba manual Android queda registrada con tiempos e IDs.
- Documentación de dependencias, licencias, fallos y rollback actualizada.
- Sprint 6 se integra y etiqueta solo después de cumplir lo anterior.
