# 23 · Descargas, límite de vídeos largos y modo sin conexión

Fecha: 23 nov 2026 (APK 4097–4101). Probado en el moto g04s con wifi y datos apagados por `adb shell svc`.

## 1. Qué hay

| Pieza | Dónde | Qué hace |
|---|---|---|
| Límite de vídeos largos | `audio_disk_cache.dart` (`maxTrackSeconds`, `worthKeeping`), `just_audio_track_engine.dart` | El audio guardado automáticamente («Guardar el audio escuchado») solo cubre pistas de **duración conocida y ≤ 20 min**. Sin él, un vídeo de 1 h se bajaba entero en segundo plano (≈58 MB en 11 s medidos) aunque solo se escuchara un momento. |
| Descargas | `features/downloads/` (`DownloadStore`, `downloads_screen.dart`) | «Descargar» en el menú ⋮ de las listas y del reproductor. Archivo en la carpeta de datos de la app (`mysic_downloads/<id>`), portada `<id>.jpg` e índice `index.json`. No las borra el recorte de 512 MB. Una a una, con aviso de fallo. Se rechazan los vídeos de más de 20 min y los archivos de más de 48 MB. Si la canción ya está en el audio guardado se **copia sin gastar datos**. |
| Reproducir lo descargado | `JustAudioTrackEngine.load` | Antes de resolver nada mira si la canción está descargada y suena del archivo (también estando en línea). |
| Solo canciones descargadas | `core/network/offline_mode.dart`, ajuste `offlineOnlyProvider` | La app no abre ninguna conexión: interceptor de Dio en `YtmClient`, `PublicCatalogClient` y las letras; portadas (`DiskImageCache`) y carátula de la notificación; resolvedor, calentado, precarga y descargas. Las pestañas se sustituyen por `OfflineHome` (lista de descargas con aviso). |
| Arranque sin internet | `CatalogNavigator._checkConnection`, `OfflineMode.checkAtStartup` | Al abrir comprueba DNS + conexión TCP al puerto 443. Sin internet y con descargas, activa el modo **solo esa sesión** (no cambia el ajuste) con botón «Reintentar». Sin descargas no cambia nada. No retrasa el primer fotograma. `main()` restaura antes el ajuste guardado y el índice. |

## 2. Medido en el teléfono (APK 4097 y 4100)

- Descargar el vídeo de 3 h: «Los vídeos de más de 20 minutos no se descargan», 0 MB.
- Descargar «Faraway» (ya en el audio guardado): 0,02 MB (portada), 4:13 · 3,9 MB en la lista.
- Con «Solo canciones descargadas»: 0,9 KB en 20 s en reposo; reproducir «Faraway», 18 KB en ~15 s, primer sonido 256 ms, sin `device_resolution` ni `proxy_*` en el registro.
- Arranque con wifi y datos apagados (APK 4100 y 4101): abre en Descargas con «Sin conexión: solo se reproducen las canciones descargadas», «Faraway» suena (0:09 de 4:12, primer sonido 222 ms). «Reintentar» con la red de vuelta regresa a las pestañas.

## 3. Dos fallos antiguos que impedían abrir sin conexión

1. `MysicProfile.fromJson` exigía un UUID como `id`, pero desde que la identidad es la sesión de YouTube Music el `id` es un hash hexadecimal de 24 caracteres: el perfil guardado nunca se podía leer. Ahora acepta las dos formas.
2. `verifiedSessionProvider` miraba `authStateProvider` sin esperar a que terminara de restaurarse: en cada arranque lanzaba «Inicia sesión» y el `AuthGate`, al ver un error que no era «inalcanzable», **borraba el perfil guardado antes de leerlo** (el registro mostraba `profile_cache clear` antes de `read=missing`). Con red se reescribía tras verificar; sin red se perdía. Ahora espera con `authStateProvider.future`.

## 3b. Bloqueo de YouTube y velo del Inicio (APK 4102–4103)

- **Canciones nuevas que no se reproducen.** Desde ~23:30 del 22 nov, YouTube devuelve `LOGIN_REQUIRED` al cliente VISIONOS y el extractor falla con `SignInConfirmNotBotException` («confirmar que no eres un bot») desde esta red. NewPipeExtractor `v0.27.1` (10 nov) ya es la última versión: no hay actualización que lo arregle. No se pudo comprobar si es de la red (los datos móviles del teléfono no tenían salida). La app ahora lo dice en el reproductor («YouTube está pidiendo confirmar que no eres un bot desde esta red… Las canciones descargadas siguen sonando»), usa el código de error `RESOLUTION_BLOCKED` y `PlaybackSourceFailure(blocked: true)`, y deja de lanzar calentados durante 5 min (`blockedUntil`). Comprobado en el teléfono: el mensaje sale, y «Faraway» (descargada) suena en 340 ms durante el bloqueo.
- **Velo sobre las pastillas.** El fondo desenfocado de Inicio (`HomeBackdrop`) subía con la lista dentro de un recorte fijo y dejaba una banda de color; con «Reducir efectos» no aparecía. Ahora no se desplaza: se desvanece con el scroll (opacidad sobre un `RepaintBoundary`). Medido: salto máximo de brillo entre filas contiguas de 2–5 (antes ~49).
- **Caché vaciada.** Tras instalar el APK 4102, «Audio en el teléfono» pasó de 503 MB a 0 KB y la caché de portadas también se vació; las descargas (carpeta de datos) sobrevivieron. No había falta de espacio (42 % libre) y ningún código de la app borra esas cachés al arrancar; no se pudo determinar la causa (probablemente el instalador del teléfono al actualizar).

## 4. Pendiente

- **Descargar por red una canción nueva no se pudo comprobar en el teléfono.** Durante las pruebas YouTube devolvió `LOGIN_REQUIRED` al cliente VISIONOS y el respaldo (NewPipe) también falló (`reason=xe`) para toda canción no resuelta antes; el calentado de los resultados falló igual. La ruta `_httpFetch` (petición al proxy local, avance, comprobación de tamaño) solo está probada con un descargador simulado en `download_store_test.dart`; en el teléfono solo se ejercitó la ruta de copia desde el audio guardado.
- Si el modo sin conexión se activa a mitad de sesión por el ajuste, las páginas abiertas por encima de las pestañas (álbum, artista) no se cierran solas.
- No hay aviso al perder la conexión durante la sesión; solo se comprueba al abrir.

## 5. Hojas inferiores y cola real (APK 4105–4106)

- **Hojas inferiores al estilo Limusic** (`features/search/presentation/item_sheet.dart`, medidas de `ModalBottomSheet.kt` de Limusic `dev`): tarjeta con esquinas superiores de 20 dp, velo negro al 50 %, tirador de 32×4, cabecera de 52 dp, cuadrícula 2×2 de 56 dp y filas de 48 dp. Una hoja por tipo: canción (listas y reproductor), playlist/álbum abiertos («Reproducir» con aleatorio), y tarjetas de playlist, álbum y artista. Abren sobre la barra de pestañas (`useRootNavigator`) y sin el tirador del tema. No se replican Guardar en playlist, Radio manual, Me gusta/No me gusta, atajos ni Editar/Borrar playlist: Mysic no escribe en la cuenta.
- **Cola real** (`TrackPlaybackController`, `RadioFetcher`, `YtmClient.radio`, `parseYtmRadio`): una canción suelta (Inicio, búsqueda, artista) es la cola de esa sola canción y detrás va su radio (`next` con `RDAMVM<id>`); una lista entra entera (hasta 500, ya no en trozos de 100) con lo ya pasado detrás. Con ≤ 2 pistas por delante pide 20 más con el cursor, sin repetir; si la última termina antes de que conteste la radio, espera. «Añadir a la cola» va delante de lo que propuso la radio, «a continuación» tras la actual; lo que el usuario añade deja de ser autoplay. Reordenar arrastrando (`move`), «Vaciar siguientes», interruptor de autoplay (con repetir activado no hay), «anterior» reinicia con > 3 s, el aleatorio solo baraja lo que sigue, historial recortado a 200.
- **Probado en el teléfono (APK 4106):** una playlist entera entra a la cola (2 reproducidas, la actual, 61 siguientes); arrastrar una pista la reordena y «siguiente» respeta el orden nuevo; una canción suelta pide la radio (`next` → 200 a pesar del bloqueo de YouTube a `player`) y muestra 20 canciones marcadas «Radio»; apagar el autoplay las quita y encenderlo las vuelve a pedir (una petición). 201 pruebas automáticas.
- **Pendiente:** el reproducir real de las canciones de la radio sigue sujeto al bloqueo de YouTube de las canciones nuevas (sección 3b). Aún no se ha escuchado una pista de la radio entera por esa causa.

## 6. Descarga por red de una canción nueva: comprobada (APK 4107, 23 nov ~02:03)

Canción nunca reproducida («Poseído del Alba», Pescado Rabioso, 3:42), desde la hoja de canción (mantener pulsado → Descargar): **3,51 MB recibidos en ~2 s por wifi** y la descarga se detuvo (el tamaño de la canción); la hoja pasó a «Descargada» con «Quitar descarga»; Ajustes pasó a «2 · 7,3 MB». Con wifi y datos apagados y la app reiniciada abre en «Descargas», muestra las dos canciones y reproduce «Poseído del Alba» (primer sonido 286 ms, estado `PLAYING`). Esta vez el resolvedor respondió (`device_resolution success=true`), es decir, el bloqueo de YouTube a canciones nuevas había cesado en ese momento. La ruta `_httpFetch` (petición al proxy local, avance y comprobación de tamaño) queda así probada en el teléfono.
