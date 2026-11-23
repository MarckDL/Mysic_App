# 21 · Arquitectura vigente de la app móvil (YouTube Music directo)

Estado: APK 4090 (22 nov 2026). Este documento **sustituye**, para la app móvil, a lo que dicen `01-arquitectura.md`, `02-base-de-datos.md`, `03-requisitos.md`, `youtube-oauth.md`, `youtube-music-mode.md`, `youtube-android.md` y `youtube-library.md` sobre Firebase, Render, Supabase/PostgreSQL y la vinculación con Mysic de escritorio. Esos documentos se conservan como historia del proyecto.

## 1. Qué cambió y por qué

| Antes | Ahora |
|---|---|
| Inicio de sesión con Google y Firebase Auth | Inicio de sesión **de YouTube Music** (ventana web oficial) |
| API en Render + Supabase (PostgreSQL) para perfil, playlists, favoritos, calificaciones, comentarios e historial | **Sin servidor propio** en el camino de los datos |
| Biblioteca vía la YouTube Data API y OAuth | Biblioteca, Inicio y Me gusta vía **InnerTube** (la API interna de YouTube Music) con la cookie de sesión |
| Vinculación con Mysic de escritorio | Eliminada |
| Historial en el servidor | Historial en **SQLite del teléfono** |

Motivo: el Inicio, las recomendaciones y los Me gusta de verdad solo existen dentro de la sesión de YouTube Music; cada salto por un servidor añadía latencia (Render dormido, base de datos en la UE y usuario en Perú). Limusic funciona igual (ver `19` y `20`).

## 2. Identidad y sesión

- `YtmLoginActivity.kt`: WebView a `accounts.google.com` con `continue` a `music.youtube.com`. Quita la marca `; wv` del agente de usuario (Google rechaza las vistas incrustadas con ella). Siempre empieza sin cookies previas. Al llegar a `music.youtube.com` espera hasta 6 × 500 ms a que exista la cookie `SAPISID` y devuelve la cookie completa.
- `YtmSessionStore.kt`: guarda la cookie **cifrada con AES-GCM** con una clave del Keystore de Android (no exportable), en `filesDir/ytm_session.bin`. Un archivo copiado a otro teléfono no se puede leer.
- `lib/features/ytm/data/ytm_session.dart`: canal `com.mysic/ytm` (`login`, `load`, `clear`), extracción de `SAPISID` y firma `SAPISIDHASH` = SHA-1 de `"{segundos} {SAPISID} {origen}"`.
- `ytm_auth_repository.dart` (`YtmAuthRepository`, implementa `AuthRepository`): estado de sesión, `verify()` (llama a `account/account_menu`), cierre de sesión y caché de la cuenta (`ytm_account.json`: nombre, @canal, foto).
- **Identificador de cuenta (`uid`)**: SHA-256 del `@canal` o del nombre, no de la cookie (la cookie cambia al volver a entrar; el canal no). Sin cuenta conocida usa un identificador provisional derivado de la cookie.
- **Verificación**: un rechazo (401/403) cierra la sesión; un fallo de red solo se informa y la app abre con la cuenta guardada.
- El perfil (`MysicProfile`) se construye localmente; el apodo se guarda en el teléfono (`profile.json`).

## 3. Datos de música

`MusicModeClient` (`lib/features/connected_library/data/music_mode_client.dart`) decide de dónde sale cada pantalla:

| Pantalla | Fuente |
|---|---|
| Inicio, Biblioteca (canciones), Me gusta, playlists, álbumes guardados, artistas seguidos, una playlist | **InnerTube** (`YtmClient`, `browse`) |
| Búsqueda de canciones, fichas de artista y álbum | **Catálogo público** del VPS (`PublicCatalogClient`), sin credenciales |
| Recientes, Lo más oído | **SQLite local** (`mysic_listens.db`) |
| Audio | Cliente VISIONOS directo (`VisionOsClient.kt`, una petición `player`) con **NewPipe Extractor** de respaldo (`DevicePlaybackResolver.kt`); proxy local con el primer tramo en memoria (`LocalAudioProxy.kt`, ver `docs/22`) |

- `ytm_client.dart`: `POST https://music.youtube.com/youtubei/v1/{browse|account/account_menu|like/like|like/removelike}`, contexto `WEB_REMIX` con versión de la fecha de hoy (`1.AAAAMMDD.01.00`), cabeceras `Authorization: SAPISIDHASH …`, `Cookie`, `Origin`, `X-Goog-AuthUser: 0`. Las continuaciones llevan el token en el cuerpo y en la dirección (`ctoken`, `continuation`, `type=next`).
- `ytm_parser.dart`: porte a Dart del analizador del backend (`music-account-catalog.ts`). Reconoce canciones (estudio, vídeo musical, subidas de usuario), álbumes, playlists y artistas; saca el título de cada estante del Inicio (`shelfTitle`); produce el mismo JSON que ya leía `MusicPage.fromJson`. Una respuesta sin sesión → `MUSIC_ACCESS_DENIED`; una sin contenido reconocible → `MUSIC_CATALOG_RESPONSE`; una **continuación vacía es el final de la lista**, no un error.
- Capacidades de la conexión: todas las pantallas (`ytmCapabilities`). Cada superficie sin capacidad mostraba "Esta función no está habilitada para la cuenta".
- Páginas guardadas en disco (`MusicBootCache`, hasta 24 archivos por cuenta) para pintar al abrir.

## 4. Datos en el teléfono

| Archivo / base | Contenido |
|---|---|
| `ytm_session.bin` (cifrado) | Cookie de YouTube Music |
| `ytm_account.json` | Nombre, @canal y foto de la cuenta |
| `profile.json` | Perfil y apodo (para abrir sin red) |
| `mysic_listens.db` (SQLite v2) | Tabla `listen` por cuenta; Recientes y Lo más oído son consultas sobre ella |
| `liked_ids.json` | Canciones con Me gusta (para pintar el corazón); se refresca si tiene más de 30 min |
| Páginas del `MusicBootCache` | Primeras páginas de cada pantalla **y el collage de Inicio** |
| `notification_art/*.png` | Portadas cuadradas generadas para la notificación (máx. 30) |
| Audio guardado, caché de URLs resueltas, caché de portadas | Ajustes → Almacenamiento |

- **Historial**: una escucha cuenta a los 30 s o a la mitad de una pista corta (`ListeningTracker`, ya sin red). Recientes = una fila por canción, hasta 5000. Lo más oído = ≥ 2 escuchas en 30 días, hasta 500. El ajuste "Registrar escuchas en Mysic" pausa el registro (en memoria: **no se recuerda al reiniciar**) y "Borrar actividad" vacía la base de la cuenta.
- **Migración de identidad**: `adoptLegacy()` pasa a la cuenta nueva el historial guardado con el identificador anterior (28 caracteres, el de Firebase) si la nueva aún no tiene escuchas.

## 5. Reproducción

- Token fijo `device`: el resolvedor de Android lo ignora (solo exige que no esté vacío). Ya no se pide ningún token de servidor.
- Caché de URLs en memoria y disco, calentado de las primeras canciones a la vista y precarga de la siguiente pista (ver `20`, sección 2).
- La cola, el reproductor y las letras no cambiaron.

## 6. Interfaz

- **Inicio** = el Inicio real de YouTube Music (estantes con su título) más los accesos de la biblioteca y el collage.
- **Collage "Accesos directos"**: 9 tarjetas (3 × 3) con lo más escuchado, lo último que sonó y los Me gusta, mezclados, y una playlist cada tercera tarjeta. Se compone **una sola vez** y se guarda; al abrir se pinta el de la vez anterior (sin esperar a la red) y el nuevo queda guardado para la siguiente apertura. Sin collage guardado se ve un esqueleto, nunca uno provisional. "Actualizar" lo renueva a mano. No rota solo.
- **Sin actualizaciones automáticas**: el scroll infinito solo avanza cuando la persona desplaza (o si la lista no llena la pantalla); cambiar de pestaña no vuelve a pedir Inicio. Abrir la app pasó de ~13 a 2–3 peticiones.
- Páginas con portada propia: Playlist (mosaico), Me gusta (corazón), Recientes (reloj con flecha), Lo más oído (flechas de repetir).
- Animación de entrada en cascada y respuesta al toque en las tarjetas; se apagan con **Ajustes → Reducir efectos**.
- Barra superior transparente arriba y opaca al desplazar.

## 7. Me gusta

`YtmClient.rate()` llama a `like/like` o `like/removelike`. `LikedTracks` (`liked_tracks.dart`) guarda el conjunto de canciones con Me gusta, cambia el corazón **al instante** y confirma en segundo plano; si YouTube falla, lo deshace. Hasta 10 páginas (1000 canciones) al refrescar.

## 8. Notificación, pantalla de bloqueo y widget

- `MysicAudioHandler` publica en la sesión de medios: anterior, reproducir/pausa, siguiente y **dos acciones propias**: **Me gusta** (corazón vacío/lleno según el estado real) y **Repetir canción** (atenuado = desactivado; con un "1" = activado). Con dos acciones propias Android no añade el botón de aleatorio.
- **Portada** (`notification_art.dart`): Android la usa como imagen grande. Las portadas de Google se piden a 544 × 544; las miniaturas de vídeo de YouTube (4:3, con franjas negras y de 120 × 90) se descargan en 480 × 360 y se recortan al cuadrado central de 544 × 544. Antes llegaba un bitmap de 84 × 63 estirado que se salía del recuadro.
- `res/raw/keep.xml` **debe** listar los iconos referenciados solo por nombre (`ic_notif_heart`, `ic_notif_heart_on`, `ic_notif_repeat`, `ic_notif_repeat_on`): el optimizador de recursos los borra y `audio_service` falla con `You must specify an icon resource id to build a CustomAction` (la notificación entera desaparece).
- **Widget de pantalla de inicio** (`MysicWidgetProvider.kt`, diseño `mysic_widget.xml`): portada de fondo recortada a esquinas redondeadas (`clipToOutline`), título, artista, anterior, pausa, siguiente y corazón. Dart le envía el estado por el canal `com.mysic/widget`; los botones usan teclas multimedia y una acción personalizada para el corazón. Se añade a mano desde el escritorio del teléfono.

## 9. Funciones eliminadas

Comentarios y moderación, calificaciones, favoritos y playlists propios de Mysic, historial en el servidor, vinculación con el canal por OAuth, Mysic de escritorio, pantallas de prueba de audio, detalle de canción. `AuthenticatedApiClient`, `ApiConfig`, `BackendSessionClient`, los repositorios `Api*` y las dependencias `firebase_core`, `firebase_auth`, `google_sign_in` ya no existen.

## 10. Verificación

- **Pruebas**: 148 automáticas pasan (`flutter test`); el análisis estático no da avisos. Nuevas: analizador de InnerTube, firma `SAPISIDHASH`, repositorio de sesión (incluida una carrera de cierre de sesión), Me gusta con deshacer, estado del widget, portadas, repetir una canción, collage estable.
- **En el teléfono (moto g04s)**: login aceptado por Google; Inicio personalizado ("Favoritos olvidados", "Recaps"); reproducción; collage idéntico en dos aperturas; 2–3 peticiones al abrir; sin peticiones de Inicio al cambiar de pestaña; en la sesión de medios aparecen las dos acciones propias; icono grande de la notificación de 84 × 84.
- **No verificado visualmente**: el aspecto del widget de escritorio, el de la pantalla de bloqueo con portada, tocar el corazón y repetir desde ahí, y bajar hasta el final de una playlist larga.

## 11. Riesgos y deuda

- **API no oficial.** InnerTube con cookie no es una API pública: YouTube puede cambiar los formatos (el analizador se rompe) o limitar la cuenta, y su uso puede ir contra sus condiciones. El analizador separa "sin sesión" de "formato ilegible" para que el fallo se vea. Hay que vigilar `ytm_unreadable` en el registro.
- **Cuenta real expuesta.** La cookie da acceso a la cuenta de Google del usuario: nunca se registra (el registro de diagnóstico solo muestra **nombres** de cookies) y solo vive cifrada.
- **Servidores sin uso**: Render, Supabase y el backend de escritorio siguen existiendo pero la app móvil ya no los llama. El VPS público sigue siendo necesario para búsqueda, artistas y álbumes. Decidir si se apagan (ahorro) o se mantienen.
- Pendiente: recordar la pausa de "Registrar escuchas" al reiniciar; corazón en el mini reproductor y en el reproductor de la app; los chips de ambiente (Relax, Entreno…) como Inicios reales de YouTube (hoy son búsquedas); aviso de sesión caducada a mitad de uso.
- **Lección operativa**: durante las pruebas en el teléfono se dejó "Reducir efectos" activado y el Inicio parecía estático. Restaurar los ajustes que se cambien al probar.

## 12. Cronología (APK)

| APK | Cambio |
|---|---|
| 4070–4076 | Recientes y Lo más oído con portada propia; Inicio sin "Canal de YouTube"; Cuenta sin vinculación |
| 4077–4079 | Inicio de sesión de YouTube Music; corrección: una llamada residual a Render cerraba la sesión |
| 4080–4082 | Reproducción sin token; todas las capacidades; collage con historial |
| 4083 | Sin Firebase ni Render |
| 4084 | Widget de pantalla de inicio y corazón |
| 4085–4087 | Notificación con corazón y repetir; iconos conservados; portada cuadrada |
| 4088–4089 | Sin actualización automática; collage estable; menos peticiones |
| 4090 | Portada restaurada (cuadrada y grande) |
