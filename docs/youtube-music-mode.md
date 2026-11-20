# YouTube Music en Mysic_App

## Verificación de la cuenta musical

El vínculo OAuth por sí solo confirma el canal a través de YouTube Data API. El servidor comprueba por separado la biblioteca privada y el Inicio de Music con el permiso del usuario. Solo anuncia la personalización si ambas respuestas son válidas y contienen evidencia de una sesión identificada. Un rechazo de Music conserva el vínculo que sí funciona para el canal. Una cuota agotada o una respuesta temporal mantiene el acceso pendiente de comprobación.

En ese estado, la búsqueda de música, las playlists propias con pistas musicales y las suscripciones musicales siguen utilizando YouTube Data API. Las listas sin música se omiten. Las pistas musicales disponibles llegan al reproductor de Mysic. La API no reemplaza las recomendaciones, los Me gusta ni los álbumes privados de Music por datos del canal. El contrato v2 permite que el APK 4026 reciba inmediatamente las funciones verificadas.

## Revisión 4026

La app mantiene su sesión Firebase y el reproductor Android de Mysic. Para la cuenta musical utiliza el vínculo OAuth de lectura del canal elegido en Google. La referencia de escritorio consulta el Inicio de Music, la lista musical de «Me gusta» y la biblioteca de discos en operaciones distintas. La revisión 4026 incorpora ese recorrido a la API móvil. [Mysic original, rama de escritorio](https://github.com/jesustheprograme/Mysic/tree/dc408a744c0a083f85f5e7ce0ecd49d6be500832)

- **Inicio** muestra las recomendaciones que devuelve YouTube Music con el permiso de la cuenta vinculada. **Biblioteca** ofrece canciones guardadas, «Me gusta de YouTube Music», playlists musicales y álbumes guardados. Las tarjetas de álbum abren sus pistas dentro de la app.
- **Playlists** comprueba el contenido de cada lista del catálogo musical. Incluye una lista mixta cuando encuentra una canción, aunque figure en una página posterior. Dentro de la lista conserva las canciones en el orden original y sus repeticiones. Las grabaciones oficiales y los videoclips musicales se reconocen por su tipo en Music. Para videos subidos por usuarios se comprueba la categoría musical y la disponibilidad en YouTube Data API con el mismo permiso.
- **Reproducción** envía la pista y su título al reproductor de Mysic. Da prioridad al archivo asociado en el teléfono, luego al audio configurado para esa grabación y, para pistas del catálogo musical, puede usar el mecanismo de reproducción que ya emplea el catálogo de la app. La disponibilidad del audio depende de la pista y del proveedor. El botón de la biblioteca de Me gusta del reproductor abre la colección del canal en modo de lectura.
- **Servidor y sesión**. El APK 4026 consulta `/api/v2/integrations/youtube-music` en el backend de `Mysic_App`. Las versiones anteriores mantienen su contrato en `/api/v1`. Si el servidor todavía no ofrece v2, la app lo indica y permite elegir expresamente la biblioteca propia de Mysic. La pantalla del vínculo se dedica al consentimiento y a la gestión del canal.

Para validar en un teléfono con una cuenta real, compara una playlist musical, otra de cursos, un álbum guardado y dos canciones de «Me gusta» con esa misma cuenta en YouTube Music. Comprueba que Inicio carga las recomendaciones de la cuenta y que al tocar una canción los controles, la cola y el audio permanecen en Mysic. El proveedor puede personalizar el orden entre dispositivos y las recomendaciones pueden cambiar entre consultas.

## Historial de la revisión 4025

La revisión móvil 4025 parte de la 4024 (`cbb9d97`) y conserva el reproductor nativo de Mysic. Android vincula el canal mediante Google y consulta el backend de Mysic_App. La aplicación web de escritorio sirvió de referencia para el recorrido de cuenta, biblioteca y reproductor. La integración se despliega en el proyecto móvil, con su propio callback. [Rama web utilizada como referencia](https://github.com/jesustheprograme/Mysic/tree/dc408a744c0a083f85f5e7ce0ecd49d6be500832)

### Recorrido en Android 4025

1. Abre **Cuenta → Vincular YouTube Music** y elige el canal en Google. Al regresar, Mysic abre la Biblioteca una vez que el servidor confirma el vínculo. Si Google devuelve el control sin confirmación automática, la app muestra **Confirmar este canal**. El cambio a un canal distinto exige confirmar el reemplazo.
2. En **Biblioteca**, abre **Canciones** para recorrer las grabaciones de tus playlists sin duplicarlas. También puedes consultar **Me gusta de YouTube**, **Playlists** y **Canales musicales que sigues**. La opción **Más de este canal** de una grabación abre otras grabaciones del mismo canal.
3. Abre una playlist. La app conserva el título, el orden y las apariciones repetidas de una canción. Informa cuántos elementos se omitieron en las páginas consultadas. **Cargar más** continúa la lectura.
4. Toca una pista con audio disponible. Se abre el reproductor de Mysic. **Reproducir** y **Aleatorio** arman una cola con hasta 100 canciones reproducibles de las páginas cargadas. Desde el menú de una canción puedes colocarla a continuación o al final mientras sigue sonando la actual. **Opciones de cola** aplica la misma acción a las canciones disponibles en la lista cargada. **Copiar enlace** copia el enlace del tema o de la playlist.
5. Para una pista marcada **Solo biblioteca**, abre su menú y selecciona **Vincular archivo de audio** si tienes una copia. Android la vincula a esa grabación, cuenta y dispositivo. Volver a autorizar el mismo canal conserva los archivos y las escuchas. Al reemplazar o desvincular el canal, la app retira sus copias privadas. **Retirar archivo de Mysic** elimina la copia privada que hizo la app. El archivo original sigue donde lo elegiste.
6. Abre **Inicio → En repetición** para ver las canciones que más escuchas en Mysic durante los últimos 30 días. El icono de historial en Inicio o Biblioteca abre **Recientes en Mysic**. En **Cuenta** puedes pausar el registro o borrar tu actividad.
7. Desde **Cuenta** puedes usar la biblioteca propia de Mysic, volver al canal, cambiar la cuenta o desvincularla. El consentimiento de Google y el inicio de sesión en Mysic tienen ciclos de vida independientes.

### Funciones del proveedor directo en 4025

| Función | Fuente y alcance |
| --- | --- |
| Identidad y playlists | El vínculo OAuth identifica el canal y se guarda en PostgreSQL. Se leen las playlists creadas por ese canal, incluidas las privadas. Una lista mixta aparece al identificar al menos una grabación elegible, incluso en una página posterior. Las listas guardadas de otros propietarios quedan fuera de esta consulta. |
| Canciones y Me gusta | La fuente es YouTube Data API v3. La selección reconoce grabaciones disponibles en la categoría musical con las dos líneas de atribución de un Art Track. Es un filtro conservador. Puede omitir canciones reales con otros metadatos. Los Me gusta proceden del canal de YouTube. |
| Búsqueda | Consulta videos de la categoría musical y verifica los metadatos antes de mostrar resultados. La búsqueda del proveedor directo devuelve grabaciones. |
| Biblioteca por canciones | Recorre todas las páginas consultadas de las playlists propias. Una grabación aparece una vez en esta vista. El detalle de cada playlist conserva sus repeticiones y orden. |
| Artistas | La lista de suscripciones del canal se filtra con los temas musicales publicados por Google. Las grabaciones de un canal también se pueden abrir desde una canción identificada. Algunas suscripciones musicales carecen de esta clasificación. |
| Reproducción | El reproductor de Mysic usa primero el archivo vinculado en el dispositivo y, en su ausencia, el audio HTTPS que el administrador haya asociado a la grabación. Las canciones sin ninguna de esas fuentes quedan disponibles para consulta. |
| Actividad de Mysic | Se conserva un máximo de 600 eventos por vínculo. Una escucha requiere 30 segundos de audio efectivo o la mitad de la canción si dura menos de un minuto. Dos escuchas consecutivas de la misma pista con menos de 30 segundos de separación cuentan una vez. «En repetición» muestra hasta 50 pistas con al menos dos escuchas en 30 días. |
| Pendiente de una fuente autorizada | Canciones y álbumes guardados de YouTube Music, Inicio personalizado, lectura del historial remoto y registro de escuchas en esa cuenta. La app solo presenta las funciones que anuncia el proveedor. |

Fuentes del contrato de datos y reproducción. [Playlists del canal](https://developers.google.com/youtube/v3/docs/playlists/list) · [Entradas de playlist](https://developers.google.com/youtube/v3/docs/playlistItems/list) · [Videos marcados con Me gusta](https://developers.google.com/youtube/v3/docs/videos/list) · [Suscripciones de YouTube](https://developers.google.com/youtube/v3/docs/subscriptions/list) · [Clasificación de un canal](https://developers.google.com/youtube/v3/docs/channels) · [Cálculo de actividad de Mysic web](https://github.com/jesustheprograme/Mysic/blob/dc408a744c0a083f85f5e7ce0ecd49d6be500832/Frontend/src/features/youtube/playHistory.js) · [Art Tracks](https://support.google.com/youtube/answer/6007071) · [Políticas de la API](https://developers.google.com/youtube/terms/developer-policies)

## Activación del backend móvil y Android

El backend usa `YOUTUBE_LINK_ENABLED=true`, la configuración OAuth y el cifrado del vínculo existentes. El callback de Google y la ruta de regreso a Android pueden residir en el mismo host HTTPS del backend móvil. Configura el App Link y la huella autorizada del APK según la [guía de Android](youtube-android.md). La referencia de variables está en [backend/.env.example](../backend/.env.example).

Antes de activar esta revisión del backend, aplica la migración `20261120010000_channel_music_listens` mediante `pnpm db:deploy` desde `backend/`.

Para ofrecer una grabación propia en todos los dispositivos, puedes asociarla mediante `MYSIC_LICENSED_AUDIO_JSON` en el backend. Su forma es `{"ABCDEFGHIJK":"https://media.example.test/tema.mp3"}`. Sustituye ambos valores por el ID real y un archivo con derechos de reproducción dentro de Mysic. Para las demás canciones del catálogo musical, el APK 4026 utiliza su fuente habitual de reproducción en Android.

En el archivo local de compilación de Android configura Firebase, Google Sign-In, `API_BASE_URL`, `YOUTUBE_MUSIC_MODE_ENABLED=true` y `YOUTUBE_APP_LINK_HOST`. Este último es el nombre del host HTTPS que recibe el retorno, sin protocolo ni ruta. Incluye la huella de la firma prevista en Firebase y en la asociación del dominio. La bandera del modo musical habilita también el flujo de vinculación. Para generar la actualización con la configuración y firma del piloto, desde `mobile/` ejecuta el comando siguiente.

```sh
flutter build apk --release --build-number=4026 --dart-define-from-file=/ruta/local/firebase.android.json
```

El proyecto hereda la configuración de firma de la rama del APK 4023. Antes de distribuir, comprueba con `apksigner verify --print-certs` que el certificado coincide con el APK instalado. El paquete debe ser `com.mysic.mysic`. Para una actualización en el teléfono usa un APK sin divisiones por ABI o compara el código de versión efectivo de cada APK.

## Pruebas y cierre del plan

En la revisión 4026 pasaron 270 pruebas del backend, 122 de Flutter y cinco de las herramientas de Android. Se verificaron las migraciones con PostgreSQL, el análisis estático y la compilación de TypeScript. El APK universal contiene ARM de 32 y 64 bits y x86 de 64 bits. Su certificado coincide con los APK del piloto 4023 y 4025. El consentimiento real, la personalización de la cuenta y la salida de audio se comprueban en el teléfono.

| Caso | Cobertura automatizada | Comprobación pendiente en teléfono |
| --- | --- | --- |
| Vinculación | Flutter simula el retorno, confirma el canal y abre Biblioteca. La API exige identidad y lee un vínculo real de PostgreSQL con proveedor Google de prueba. | Consentimiento real de dos cuentas y restauración al reabrir. |
| Biblioteca | La respuesta de Music alimenta cada colección. Se prueban listas mixtas, cursos, podcasts, videoclips subidos por usuarios, álbumes, orden y repeticiones, paginación y aislamiento entre dos cuentas. | Comparar las listas, un álbum y dos Me gusta con la misma cuenta en YouTube Music. |
| Aislamiento | Rechazo de cursores ajenos, cambios de generación durante consultas, desvinculación tardía y limpieza de la cola. | Cambiar de canal mientras suena una pista y tras cerrar Android. |
| Reproducción | Selección de fuente HTTPS o archivo privado, cancelar o reemplazar una copia, controles de cola, avance nativo y restauración del orden tras reproducir en aleatorio. | Reproducir un archivo habilitado en el teléfono y verificar audio, avance y cola. |
| Actividad de Mysic | Tiempo audible, separación entre cuentas, reintentos sin duplicados y descarte de una página que estaba cargando al borrar actividad desde otro dispositivo. | Comprobar Recientes y En repetición en dos teléfonos del mismo usuario. |
| Inicio y actividad | Una respuesta simulada de Inicio comprueba el orden del feed y la selección de una pista abre la cola nativa. El historial de escuchas pertenece a Mysic. | Contrastar las recomendaciones con el canal seleccionado y comprobar que la reproducción continúa en segundo plano. |

Para el ensayo con datos sintéticos usa un backend aislado con `YOUTUBE_MUSIC_PREVIEW_ENABLED=true` y los UID explícitos `YOUTUBE_MUSIC_PREVIEW_UID_A` y `YOUTUBE_MUSIC_PREVIEW_UID_B`. Los demás usuarios siguen el flujo OAuth. La simulación se identifica en pantalla y mantiene sus datos en memoria.
