# Sprint 06 — Audio del catálogo y reproductor

Fecha de planificación: 27 de octubre de 2026.
Estado: APK y controles de fondo probados en Android; la navegación de cola fue
corregida y CI aprobada. El transporte del proveedor se corta alrededor de 1:09,
por lo que el Sprint continúa abierto y no se etiqueta.
Historia: US-006 y continuación explícita de viabilidad US-005.
Versión prevista: sprint-06-v0.6.0.

## Objetivo del usuario

Vincular las canciones obtenidas en búsqueda y detalle con su fuente reproducible
mediante youtubei.js, usando el mismo source/sourceId. La intención es intentar
reproducir cualquier resultado seleccionado del catálogo, sin descargar masivamente
los resultados ni asumir que todas las pistas tengan audio accesible/compatible.

La resolución de audio es el primer entregable del sprint. No se sustituye por otra
demo local para dar por cumplida la integración YouTube. Una pista restringida,
eliminada o no compatible debe mostrar su motivo, sin representar éxito ficticio.

Fuentes: arquitectura, RF-017–024 y Sprint 06 del roadmap. Sprint 05 quedó verificado
con demo propia; la viabilidad de audio YouTube fue trasladada aquí por el usuario.

## Estado inicial y cambios necesarios

1. YoutubeProvider ya implementa búsqueda/detalle, pero resolvePlayback devuelve
   unavailable incondicionalmente. No se ha intentado resolver el audio real.
2. PlaybackService solo permite direct para el asset demo registrado.
3. PlaybackResult no tiene todavía la variante direct con entrega HTTPS.
4. PlaybackResolution Flutter y ApiPlaybackRepository también bloquean fuentes
   distintas de la demo. La UI de catálogo solo comprueba indisponibilidad.
5. El motor actual es una prueba de 8 s, pausada al salir/fondo. No hay cola,
   mini player, audio_service ni reproducción bloqueada/segundo plano.

Por tanto, la conexión requiere modificar proveedor, contratos, validación del
backend, cliente móvil y motor; no basta con quitar el mensaje unavailable.

## Flujo que se implementará

1. Búsqueda devuelve Track: id, source, sourceId, título, artista, duración y miniatura.
2. Al tocar Reproducir, Flutter envía el source/sourceId de ese mismo Track a
   POST /api/v1/playback/resolve con token Firebase.
3. Express verifica identidad, valida entrada y consulta el MusicProvider registrado.
4. YoutubeProvider obtiene información del ID solicitado y selecciona un formato
   de audio compatible mediante la API de la versión instalada de youtubei.js.
5. El backend normaliza la resolución y comprueba que corresponde a la pista.
6. Flutter conserva los metadatos del Track y carga la fuente permitida en just_audio.
7. PlayerController y audio_service comparten pista, estado, posición y controles.

La caché de búsquedas no es una caché de URLs de reproducción. El audio se resuelve
bajo demanda al reproducir o renovar una fuente caducada.

## Etapa A — Prueba real de audio, antes de ampliar el reproductor

- Revisar la API y código de youtubei.js 18.3.0 instalada: formatos de audio,
  resolución de URL, restricciones, caducidad y requerimientos de ejecución.
- Crear un diagnóstico reproducible en backend con un ID de contenido propio o
  autorizado; validar estado real y formatos, sin imprimir URLs firmadas ni cookies.
- Usar los mecanismos normales de la biblioteca cuando sean compatibles con el
  acceso permitido; no eludir DRM, autenticación ni restricciones del proveedor.
- Registrar codec, contenedor y MIME. Probar AAC/M4A u otro formato que Android
  soporte realmente; no asumir compatibilidad solo por tener una URL.
- Verificar acceso HTTPS desde Android, duración/decodificación, primera reproducción
  y seek cuando el origen admita rangos. No enviar Firebase ID token al CDN.
- Comprobar la diferencia entre restricciones del proveedor, URLs caducadas,
  indisponibilidad de red y formato no reproducible.
- Evidencia mínima: el audio seleccionado se oye en Android y corresponde a sus
  metadatos. Una prueba de metadatos o una respuesta 200 no cumple esta etapa.

Punto de control: si no hay audio accesible/compatible en el entorno, documentar
la causa concreta. No construir el resto fingiendo que esa fuente está resuelta
ni declarar completo el objetivo de conexión de audio YouTube.

## Etapa B — Contratos y backend

### PlaybackResult

Conservar direct/asset para demo y unavailable con motivo; añadir direct/https:

- mode: direct.
- delivery: https.
- url: URL temporal de medio, solo al cliente autenticado y sin logs.
- contentType: MIME validado del formato elegido.
- expiresAt: solo si se obtiene una expiración fiable; no inventar vigencia.
- seekable: solo cuando se conozca el soporte; no prometerlo por defecto.
- source y sourceId o identidad equivalente para comprobar correspondencia.

Mantener embedded como modalidad distinta; un reproductor embebido no equivale a
una URL de audio nativa. No sustituir silenciosamente la experiencia solicitada.

### Resolución y seguridad

- Ampliar PlaybackService para entrega HTTPS emitida por proveedores registrados.
- Validar esquema, dominio CDN y destino conforme a la fuente; no convertir la API
  en resolvedor de URLs arbitrarias ni en acceso a localhost/redes privadas.
- No reenviar Authorization Firebase a URLs externas ni registrar respuestas SDK.
- No persistir URLs temporales en PostgreSQL ni incluirlas en metadatos duraderos.
- Resolver sin descargas completas ni proxy de retransmisión en este incremento.
  Si el acceso directo falla, registrar el motivo antes de decidir otra arquitectura.
- Mantener autenticación, límite por UID, no-store, timeout y abort.
- Responder unavailable ante restricciones conocidas; 503/504 ante fallos operativos.
- Diseñar renovación acotada ante expiración: conservar posición cuando sea válido
  y no crear bucles de reintento ni tratar todo 403 como expiración.

## Etapa C — Flutter: reproducir desde búsqueda y detalle

- Extender PlaybackResolution y ApiPlaybackRepository con entrega HTTPS validada.
- Vincular Reproducir en búsqueda/detalle al Track elegido, sin otra búsqueda por
  nombre que pueda seleccionar una versión distinta.
- Crear PlayerController y repositorio/motor separados de los widgets.
- Estados: inactivo, resolviendo, cargando, reproduciendo, pausa, finalizado,
  no disponible y error recuperable. Mostrar el motivo específico cuando exista.
- Play/pause, reinicio, posición/duración y seek solo cuando esté soportado.
- Si el usuario selecciona B mientras A carga, cancelar/descartar A y no permitir
  que una respuesta tardía cambie de nuevo la pista o active sonido anterior.
- Una sola instancia de reproducción y una sola fuente de estado para todos
  los controles; evitar dobles reproducciones entre pantallas.
- La demo autorizada se conserva como diagnóstico separado de las pistas YouTube.

## Etapa D — Cola, mini player y pantalla completa

- Cola en memoria con orden explícito, pista actual, anterior/siguiente y fin.
- Resolver el audio de cada elemento al reproducirlo; no resolver todo el catálogo.
- Tratar no disponibles con mensaje y política de salto acotada, sin bucles.
- Mini player visible al navegar dentro de la sesión; abre pantalla completa.
- Metadatos coherentes: portada, título, artista y duración de la pista seleccionada.
- La cola no es una playlist persistida ni un historial (sprints posteriores).
- Logout/cambio de cuenta detiene audio, vacía cola y elimina URLs de la anterior.

## Etapa E — Segundo plano e interrupciones

- Integrar audio_service con audio_session y just_audio compatibles con el SDK.
- Configurar servicio Android, permisos y notificación multimedia necesarios según
  la documentación de las versiones elegidas; evitar permisos no requeridos.
- Unificar controles de app, notificación y pantalla bloqueada en el mismo handler.
- Sustituir la pausa al fondo de la demo por una política explícita del reproductor
  principal: mantener reproducción con sesión válida y servicio activo.
- Mantener la demo con su comportamiento diagnóstico separado.
- Gestionar pérdida/recuperación de foco, auriculares y errores de dispositivo.
  Reanudar solo en circunstancias definidas, nunca después de logout o cambio de pista.
- Verificar qué sucede al cerrar la UI, bloquear pantalla o destruir el proceso;
  no prometer reproducción tras muerte forzada sin implementación específica.

## Pruebas y aceptación

### Backend

- Selección/normalización de formatos mediante fixtures y dobles, sin red en CI.
- Correspondencia sourceId, ausencia de formato, restricciones, timeout y expiración.
- Validación de URL/CDN y rechazo de destinos arbitrarios o no autorizados.
- Firebase/ownership existentes, límite, no-store y ocultación de datos sensibles.
- Mantener migraciones y pruebas PostgreSQL previas sin cambios destructivos.

### Flutter

- Parser de fuentes HTTPS/asset/unavailable y rechazo de contratos inválidos.
- Controlador: play/pause/seek, fin de pista, cola y cambio rápido de selección.
- Fuente vencida con renovación limitada, errores de red y recuperación.
- Un solo reproductor; controles sincronizados entre vistas y servicio.
- Logout/cambio de cuenta durante carga o reproducción y descarte de respuestas tardías.
- Widgets de mini player/pantalla completa y servicio mediante dobles.

### Prueba real Android

- Fuente propia/autorizada obtenida por youtubei.js y audible en Android.
- Búsqueda → selección → audio con los mismos metadatos/ID.
- Probar varios IDs autorizados y registrar resultados por caso; no concluir
  disponibilidad universal a partir de una única pista.
- Pausa, seek cuando se soporte, anterior/siguiente y orden de cola.
- Navegar, bloquear pantalla y controlar desde notificación.
- Interrupciones/foco y desconexión de auriculares cuando el dispositivo lo permita.
- Caducidad/red, logout y cambio de cuenta sin audio residual.

## Cierre

- Registrar fuentes/IDs de prueba, versiones, compatibilidad y límites observados.
- Actualizar arquitectura, requisitos y seguimiento con el contrato final.
- Análisis, pruebas, build backend, pruebas PostgreSQL, suites Flutter y APK en CI.
- No confundir pruebas unitarias de formatos con prueba de escucha real.
- Commit de cierre y etiqueta sprint-06-v0.6.0 sobre el commit probado, después
  de verificar CI y criterios reales. No se publica aún ninguna etiqueta.

## Primer entregable al ejecutar el plan

Diagnóstico de resolución de audio del catálogo con youtubei.js y una prueba de
reproducción Android del mismo ID. La ampliación de controles y segundo plano
viene después de ese resultado, para no repetir la validación solo con tonos.

## Primera ejecución técnica

Se inició la evaluación usando el mismo ID obtenido desde búsqueda, mediante
getBasicInfo de la API normal del SDK instalado. Caso observado: sourceId
4D7u5KF7SP8, identidad coincidente, estado UNPLAYABLE, motivo Video unavailable,
0 formatos de audio, 0 URLs directas y 0 formatos con cipher. No se intentó
eludir el rechazo ni se descargó audio. El resultado corresponde a esa pista y
entorno; no prueba indisponibilidad de todo el catálogo.

Se añadió pnpm playback:probe [VIDEO_ID] para comparar otros IDs y el entorno del
usuario. Sin ID, busca una pista con el mismo ejemplo de catalog:check. El comando
reporta estado, conteos y MIME sin revelar enlaces firmados ni credenciales. Cuenta
formatos sin DRM, pero no resuelve firmas ni reproduce audio; audioPlaybackVerified
permanece false. Un diagnóstico que devuelve OK no equivale a audio audible.

La integración de fuentes HTTPS en API/Flutter sigue pendiente del primer resultado
real que proporcione una fuente compatible. No se ha habilitado una reproducción
ficticia ni se ha cerrado Sprint 06.

Segundo caso diagnóstico: aqz-KE-bpKQ también devolvió UNPLAYABLE, sin formatos
de audio ni candidatos directos. Sigue pendiente comparar desde la terminal normal
y otros IDs; no se concluye imposibilidad universal ni se atribuye una causa no
confirmada (IP, región o acceso) al mensaje genérico del proveedor.

Verificación de este incremento: lint, tipos, formato y build correctos; 104 pruebas
backend correctas y 3 PostgreSQL omitidas localmente. Las tres nuevas pruebas de
diagnóstico verifican correspondencia de ID, separación metadata/audio y ocultación
de URLs/firmas; no sustituyen escucha real. No se ha hecho commit ni etiqueta.

## Corrección del contexto del player y nueva evidencia

El diagnóstico anterior desactivaba retrieve_player como la búsqueda de metadatos.
Eso omitía el contexto del reproductor/signatureTimestamp usado por getBasicInfo.
Se corrigió únicamente playback:probe para cargar el player de forma normal con
retrieve_player:true. El catálogo conserva su inicialización ligera de metadatos.

Prueba controlada del mismo ID 4D7u5KF7SP8: sin player devolvió UNPLAYABLE/0 formatos;
con player y timestamp presentes devolvió OK/4 formatos de audio, AAC y Opus,
sin DRM indicado. Por tanto, los primeros resultados NO prueban una restricción
real ni indisponibilidad de la pista; estaban condicionados por nuestra configuración.

La respuesta actual no entrega URLs individuales ni manifiestos DASH/HLS, pero sí
server_abr_streaming_url. El diagnóstico se amplió para informar estas capacidades
sin mostrar endpoints firmados. SABR requiere una integración de transporte distinta:
no se puede pasar su endpoint como si fuera un archivo MP3 a just_audio. Que haya
formatos y estado OK tampoco confirma escucha ni autorización de cualquier contenido.

Próxima investigación: compatibilidad de SABR/UMP con entrega al reproductor nativo,
usando los componentes documentados del ecosistema (googlevideo) o integración
oficial apropiada. Una adaptación mediante backend de medios cambiaría la arquitectura
de entrega directa del plan y deberá documentar acceso, recursos, autorización,
cancelación, seek y compatibilidad antes de habilitarse. No se ha añadido un proxy,
ni desafíos de autenticación, ni reproducción YouTube ficticia en este incremento.

Fuentes técnicas:
- https://ytjs.dev/api/classes/Player
- https://github.com/LuanRT/YouTube.js/blob/main/src/Innertube.ts
- https://ytjs.dev/googlevideo/
- https://github.com/LuanRT/kira

## Prueba de transporte SABR — punto de control

Se revisó el ejemplo oficial de googlevideo y la API de SabrStream, versión 5.0.1.
Se instaló únicamente una copia temporal para evaluación, sin añadirla como
dependencia de backend ni modificar su lockfile. La prueba usó aqz-KE-bpKQ,
Big Buck Bunny, obra abierta de Blender (https://peach.blender.org/about/),
con atribución de referencia (c) 2008 Blender Foundation / bigbuckbunny.org,
CC BY 3.0. La prueba posterior conserva únicamente una muestra temporal local con atribución;
no se añade audio de YouTube al repositorio ni se redistribuye.

Se obtuvo contexto player normal con signatureTimestamp; se utilizó la resolución
normal de URL del SDK y el adaptador SABR/UMP. La transformación de URL se ejecutó
solo en la prueba temporal, con contexto VM separado y límite de ejecución; no se
ha incorporado evaluador remoto al servidor de producción ni se considera vm una
frontera de seguridad suficiente para un servicio público.

La primera ejecución abortó al recibir pending (2), antes de que terminara la
negociación. Esa detención fue un error del diagnóstico: pending no equivale a
rejected (3). No permite concluir que el proveedor impidiera la entrega de audio.
La repetición y sus resultados se describen abajo. El Sprint 06 sigue abierto.

Referencias técnicas revisadas:
- https://github.com/LuanRT/googlevideo/blob/main/examples/downloader/vod-example.ts
- https://github.com/LuanRT/googlevideo/blob/main/examples/downloader/utils/sabr-stream-factory.ts
- https://ytjs.dev/googlevideo/api/exports/sabr-stream/classes/SabrStream

## Preferencia confirmada: reproducción nativa de solo audio

El usuario eligió expresamente reproducción nativa de solo audio. Se mantiene
just_audio/audio_service como destino y no se sustituirá la experiencia por un
reproductor visible/embebido. La propuesta de reproductor oficial visible no fue
seleccionada; no se incorporará como cambio implícito de alcance.

Antes de concluir una restricción definitiva de transporte se revisa el diagnóstico:
la primera prueba SABR detuvo tanto pending (2) como rejected (3), por lo que solo
confirmaba que se solicitó verificación, no el código final concreto. Se repite con
registro de estados numéricos, plazo acotado y sin generadores de tokens. Pending
se deja evolucionar de manera normal; rejected detiene la prueba. No se fuerza
ninguna aprobación. El resultado se registrará sin revelar endpoints ni credenciales.


## Resultado de la prueba de audio nativo

Al dejar evolucionar pending (2), SABR entregó una cabecera y segmentos de medio
para aqz-KE-bpKQ. Muestra local: 486303 bytes, MP4 fragmentado con moof/mdat,
pista AAC. FFprobe identificó únicamente audio; FFmpeg decodificó la muestra sin
errores. La duración declarada por la cabecera pertenece al vídeo completo y NO
representa la duración descargada de esta muestra parcial.

Esto valida recepción y decodificación de audio, no escucha en Android ni acceso
universal al catálogo. Se corrige la conclusión anterior de bloqueo: no se necesitó
ningún generador de tokens ni cookies para esta prueba.

Se incorpora playback:probe:native como diagnóstico CLI separado del servidor.
Utiliza googlevideo 5.0.1, fuente abierta fija Big Buck Bunny y muestra temporal
privada con atribución. Limita tiempo a 25 segundos, tamaño a 2 MB y cancela el
transporte al obtener segmentos. No registra URLs firmadas. El evaluador del SDK
permanece exclusivo de esta herramienta, no se instala en Express.

Ejecución desde backend:

```bash
pnpm install --frozen-lockfile
pnpm playback:probe:native
```

La salida informa samplePath. Para verificarlo, utilizar esa ruta concreta:

```bash
ffprobe -v error -show_streams /ruta/indicada/big-buck-bunny.m4a
ffmpeg -v error -i /ruta/indicada/big-buck-bunny.m4a -f null -
```

Siguiente incremento: documentar e implementar el puente autenticado SABR →
MP4/AAC → just_audio. Es un cambio respecto a la entrega HTTPS directa inicialmente
prevista: el endpoint SABR no es un archivo reproducible por just_audio. Requiere
cancelación al desconectar, límites por usuario, gestión de sesión y un mecanismo
adecuado de aislamiento del transformador del SDK. No se habilita aún el puente
ni se prometen seek, cola o segundo plano antes de comprobar audio en Android.
La experiencia confirmada sigue siendo nativa de solo audio.

## Incremento implementado: conexión para prueba Android

Se implementó el puente autenticado de medios y el motor nativo de Flutter.
La entrega final de este incremento es api-stream, no una URL de CDN enviada
al teléfono. Se documentan el cambio arquitectónico y los límites en la sección
19 de docs/01-arquitectura.md. La ruta original de demo conserva su comportamiento.

Backend: GET /api/v1/playback/audio/:sourceId, Firebase validado, ID exacto,
MP4/AAC secuencial, no-store, sin rangos/seek, máximos por usuario/instancia,
backpressure y cancelación. Worker separado con permisos Node restringidos y sin
credenciales de la aplicación; no reutiliza el evaluador en el proceso Express.

Flutter: botón Reproducir audio en detalle, pausa/continuación/detener, errores
recuperables; motor just_audio con token solamente al backend. Se detiene al
salir, ir al fondo y cambiar/cerrar sesión. No se habilitan aún servicio de fondo,
cola, mini player ni seek. No se declara cerrado el sprint.

Se añade «Probar audio de YouTube» en Inicio para abrir la prueba autorizada
Big Buck Bunny, aqz-KE-bpKQ, independiente de la clasificación de YouTube Music:
el SDK de catálogo musical no devolvió metadatos de ese vídeo en esta prueba.
La pantalla identifica la fuente y su atribución explícitamente. Las canciones
obtenidas por búsqueda mantienen su detalle y botón para el mismo ID.

Evidencia real del puente: un cliente HTTP con verificador Firebase simulado para
el ensayo recibió HTTP 200 audio/mp4 desde Express, usando el transporte real de
YouTube; FFmpeg decodificó cinco segundos, salida 0 y cero bytes de errores. Se
cerró la conexión y se canceló el worker. No equivale a Firebase real ni a escucha
en Android; esas dos comprobaciones siguen pendientes en el entorno del usuario.

Validación automatizada: 116 pruebas backend correctas; 3 PostgreSQL omitidas.
Lint, tipos, build y formato backend correctos. Dart format y análisis móvil sin
problemas. Se añaden pruebas de controlador/contrato, logout, cancelación y widget.
No se pudieron ejecutar suites Flutter aquí: el SDK rechaza escribir engine.stamp
por sistema de archivos de solo lectura. No se presentan esas pruebas como aprobadas.

### Pasos para el usuario

Detener backend anterior con Ctrl+C y ejecutar:

```bash
cd /home/dino/programacion/mysic_app/backend
pnpm install --frozen-lockfile
pnpm dev
```

En otra terminal, detener Flutter anterior con q y ejecutar:

```bash
cd /home/dino/programacion/mysic_app/mobile
flutter pub get &&
  flutter analyze &&
  flutter test --no-enable-impeller &&
  flutter run --dart-define-from-file=config/firebase.android.json
```

1. Iniciar sesión y abrir Inicio → Probar audio de YouTube → Reproducir audio.
   Esperar la preparación inicial (hasta unos 30 segundos) y confirmar audio real.
2. Pausar, continuar y detener; iniciar otra vez desde el principio.
3. Salir del detalle/prueba y llevar la app al fondo: debe detenerse el audio.
4. Volver a buscar una pista propia/libre/autorizada, abrir su detalle y reproducir.
   Verificar que el sonido corresponde a su título/ID; no usar éxito de metadatos
   como sustituto de esta prueba.
5. Revisar logout/cambio de cuenta, auriculares y error de red. Un error permite
   reintentar manualmente; no hay reintentos infinitos ni reproducción de otra pista.

No existe garantía universal para todo el catálogo. Si una pista falla, registrar
su ID y el mensaje de la app sin compartir tokens, .env ni URLs firmadas.


## Corrección tras prueba de usuario: renovación de token

FirebaseAuthRepository observa idTokenChanges. Cada getIdToken(forceRefresh:true)
al iniciar audio puede emitir un AuthUser nuevo con el mismo UID. Antes,
authStateProvider propagaba ese evento, verifiedSessionProvider volvía a cargar
y AuthGate desmontaba CatalogNavigator y el reproductor. La escucha podía
cancelarse antes de abrir el transporte aunque el backend funcionase.

Se filtran eventos consecutivos con el mismo UID en authStateProvider. Cambiar
cuenta o cerrar sesión continúa invalidando el perfil y deteniendo el audio;
los tokens siguen renovándose y verificándose en backend. La prueba de búsqueda,
detalle y logout ahora emite el evento de renovación y reproduce la dependencia
real del perfil: comprueba conservación de pantalla/motor y reproducción del ID
seleccionado antes del logout. Análisis estático sin problemas. Ejecución de la
prueba Flutter y escucha Android siguen pendientes: SDK local de solo lectura y
sin dispositivo ADB disponible para el agente. No se atribuyen todos los posibles
fallos al token ni se declara verificada la escucha del usuario.

## Estado actual: cola y reproducción en segundo plano implementadas

Este apartado sustituye las limitaciones provisionales de navegación/fondo de los
incrementos anteriores. El usuario confirmó que la búsqueda y escucha de Unravel y
Ravensky de Ado funcionan, y que las comprobaciones del primer incremento se cumplen.
La latencia inicial se conserva como mejora pendiente de medición, no se declara
optimizada ni se atribuye todavía a una causa única.

Se implementaron:

- Reproductor único mantenido por la sesión verificada; audio continuo al navegar.
- Mini reproductor global con acceso a pantalla completa, pausa y siguiente.
- Cola de hasta 100 elementos, añadir, elegir, quitar, vaciar, anterior/siguiente y
  avance automático al finalizar. Error detiene avance automático y permite salto
  manual/reintento; no hay bucles de pistas fallidas.
- Acciones en búsqueda: reproducir una canción, añadirla y reproducir resultados.
- Progreso/duración del motor y metadatos de la pista actual en pantalla completa.
- audio_service 0.18.19 y configuración Android de actividad/servicio/receptor,
  permisos y notificación multimedia con controles del mismo controlador.
- Continuidad al bloquear/ir al fondo, con política de detener/vaciar al retirar
  tarea y de eliminar audio/cola/metadatos al cerrar o cambiar sesión.
- Cancelación de cargas anteriores y de autoplay ante interrupciones durante carga.
- La demo local limpia el reproductor principal antes de su diagnóstico separado.

Seek no se implementa: el contrato del transporte real sigue siendo secuencial.
El progreso es informativo; un slider que fingiera seek no cumple el requisito.
Se mantiene explícitamente esta limitación y se evaluará una ampliación del
transporte por posición en un incremento posterior. La cola no se persiste.

Las pruebas de controlador, contrato, handler, navegación, mini reproductor y logout
se ejecutan con motor simulado. La suite Flutter ya puede ejecutarse en un entorno
temporal del SDK, sin modificar el SDK instalado: no continúa bloqueada como en los
primeros incrementos. Eso no acredita por sí solo notificación/audio con Android
bloqueado. No se ha construido ni verificado aquí un APK con el nuevo servicio.

### Próxima prueba manual Android

Con backend encendido, salir de Flutter con q (el cambio nativo exige recompilar):

```fish
cd /home/dino/programacion/mysic_app/mobile
flutter pub get && flutter analyze && flutter test --no-enable-impeller && flutter run --dart-define-from-file=config/firebase.android.json
```

1. Buscar, reproducir desde un resultado y volver a Inicio: debe seguir sonando y
   mostrarse el mini reproductor con título/artista correctos.
2. Añadir dos pistas, abrir el reproductor y probar orden, anterior/siguiente,
   quitar una pista no actual y vaciar. Reproducir resultados reemplaza la cola.
3. Dejar terminar una pista: debe avanzar una vez; al final de la cola debe parar.
   Una pista fallida debe permitir reintentar o pulsar siguiente sin bucle automático.
4. Pulsar Inicio de Android y bloquear pantalla: comprobar audio, notificación,
   título/artista, pausa/continuación, siguiente/anterior y volver a la app.
5. Desconectar auriculares/provocar pérdida de foco: pausa sin auto-resume. Mientras
   carga, cambiar rápidamente de canción o detener: no debe sonar la carga anterior.
6. Cerrar sesión desde Inicio con audio activo y entrar con otra cuenta: silencio,
   cola vacía y sin metadatos de la cuenta anterior. Retirar la tarea debe detener.
7. Confirmar que el progreso avanza pero no ofrece seek. No prometer duración
   superior al límite actual de 20 min de cada conexión del backend.

Pendiente para cierre: pruebas manuales del nuevo servicio en Android, instalación
del APK en el dispositivo, CI final, documentación de resultados y publicación del
commit/etiqueta verificados.
No se cierra ni etiqueta Sprint 06 en este incremento.

Verificación local del 3 de noviembre de 2026: 42 pruebas Flutter y las 5 pruebas
Python de configuración aprobadas, análisis sin problemas, formato de 47 archivos
sin cambios y APK debug compilado con la configuración Firebase local. Backend:
116 pruebas aprobadas, lint, tipos, formato y build correctos; 3 pruebas PostgreSQL
se omitieron localmente porque Docker estaba inactivo y no había servidor PostgreSQL.
Se corrigió la carrera de dos restricciones únicas durante sync concurrente y la
prueba de integración ahora repite cinco altas simultáneas.

GitHub Actions Quality 41767903575 aprobó la rama de cierre: backend con migraciones,
PostgreSQL real, 13 archivos y 119 pruebas aprobadas sin omisiones, además de lint,
tipos, formato y build; mobile con análisis, pruebas Flutter, 5 pruebas Python y APK
debug correctos. Las advertencias del runner sobre acciones basadas en Node 20 y la
futura imagen Ubuntu 26 no afectaron el resultado y quedan como mantenimiento de CI.

El diagnóstico autorizado SABR tuvo un primer `stream-error` transitorio y pasó al
repetirlo: 486303 bytes MP4/AAC de Big Buck Bunny, con `moof`/`mdat`; FFprobe detectó
una única pista AAC y FFmpeg decodificó la muestra sin errores. Esto no garantiza
disponibilidad universal. El dispositivo Android 16 fue detectado y se configuró
el reenvío USB del puerto 3000, pero Android rechazó la primera instalación con
`INSTALL_FAILED_USER_RESTRICTED`; notificación, bloqueo de pantalla y ejecución del
APK siguen pendientes hasta autorizar la instalación mediante USB en el teléfono.

## Prueba Android posterior y límite del proveedor

La instalación se autorizó después y el APK se ejecutó en el dispositivo Android 16.
El usuario confirmó que la reproducción, segundo plano y notificación aparecen, pero
reportó tres problemas: corte reproducible alrededor de 1:09, nueva resolución lenta
al reintentar y anterior/siguiente sin audio desde la notificación.

Los comandos Android de anterior/siguiente sí llegaron al MediaSession, cambiaron
el índice y publicaron los metadatos de la pista correspondiente. La causa adicional
encontrada estaba en Express: la solicitud de la nueva pista podía llegar antes de
que el cierre HTTP anterior liberase el UID y recibía 429. La ruta ahora reemplaza
atómicamente solo el stream anterior del mismo usuario, conserva el máximo global
de dos usuarios y evita que el cierre viejo elimine el registro nuevo. Hay pruebas
de reemplazo y del límite global. Commit `742ab1f`.

GitHub Actions Quality 41774836469 aprobó este cambio: backend con migraciones y
PostgreSQL, 120 pruebas totales sin omisiones, lint, tipos, formato y build; mobile
con análisis, pruebas Flutter/Python y APK debug. Falta repetir anterior/siguiente
en el teléfono cuando ADB vuelva a reconocerlo.

### Evaluación de URL directa sugerida

No se adoptó `new Function` en Express. El SDK ya evalúa el transformador dentro
del worker hijo restringido mediante `vm.Script`; moverlo al proceso principal
ampliaría innecesariamente el riesgo. Se comprobó la versión estable instalada,
youtubei.js 18.3.0, con la fuente autorizada Big Buck Bunny.

YTMUSIC y TV no entregaron `streaming_data` utilizable en este entorno. IOS y
TV_SIMPLY entregaron AAC/M4A directo y los rangos iniciales respondieron, pero los
rangos posteriores recibieron 403 al alcanzar aproximadamente un minuto de audio.
Cambiar bitrate o tamaño de bloque solo desplazó el límite proporcionalmente; no
resolvió la sesión completa. No se incorporó ni se dejó código experimental roto.

El mantenedor de YouTube.js identifica los 403 actuales de URLs directas como casos
en que el proveedor espera un Proof-of-Origin token; la librería puede adjuntarlo,
pero no lo genera. Automatizar navegador/BotGuard/DroidGuard para obtenerlo sería
un mecanismo de atestación destinado a desbloquear restricciones y contradice R-007.
Referencias: https://github.com/LuanRT/YouTube.js/issues/724 y
https://github.com/LuanRT/YouTube.js/issues/674. SABR también tiene una incidencia
abierta por `Attestation required`: https://github.com/LuanRT/YouTube.js/issues/947.

El corte a 1:09 queda confirmado como bloqueo de transporte, no como pausa normal
de just_audio. Para cerrar el Sprint se necesita una fuente de audio autorizada que
permita la canción completa, o una decisión explícita de producto para usar el
reproductor oficial visible. No se generará PoToken, no se afirmará reproducción
completa y no se creará la etiqueta `sprint-06-v0.6.0` mientras esto siga pendiente.
