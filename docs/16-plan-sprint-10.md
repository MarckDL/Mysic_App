# Sprint 10 — Historial de escucha

Estado: implementación y aceptación asistida verificadas; backend desplegado en
Render, migración aplicada en Supabase y CI correcto. Publicación formal de cierre
preparada para `sprint-10-v0.10.1`; verificar commit/push/etiqueta con el script de
cierre antes de declarar completado el versionado. US-010, RF-047 a RF-050.

## Reglas

Escucha válida: 30 segundos o la mitad de la duración normalizada, lo primero que
ocurra. Duración desconocida: 30 segundos. Pausas, carga, interrupciones y seek no
acumulan tiempo. El reloj monotónico mide actividad del motor, no audición humana.
Cada selección explícita crea un UUID v4; pausa y reanudación conservan el UUID.
Completed exige final natural y al menos 90 % de la duración conocida.

## API

Todas las rutas requieren Firebase ID token y perfil sincronizado. El propietario
se resuelve desde Firebase UID, nunca desde datos del cliente.

- PUT /api/v1/history/:playbackSessionId: catalogTrackId, startedAt ISO UTC,
  listenedMs entero, completed booleano. Devuelve 204.
- GET /api/v1/history: limit 1–50 (20 por defecto), cursor opaco; devuelve items y
  nextCursor, ordenados por startedAt e id descendentes.

La sesión tiene identidad, canción y fecha inmutables. PostgreSQL actualiza el
máximo acumulado y OR de completed atómicamente. Conflictos devuelven 409; datos
inválidos 400; fallos operativos 503. El servidor valida umbral y tiempo transcurrido,
con tolerancia de reloj de cinco segundos y máximo 24 horas por sesión.

## Android

ListeningTracker se inyecta en TrackPlaybackController. Envía checkpoints cada diez
segundos y en transiciones; nunca espera la red para reproducir. La pantalla Mi
historial pagina y abre el detalle de canción, desde donde se puede reproducir.

Decisión respecto del plan: la cola pequeña usa preferencias privadas nativas de
Android mediante MethodChannel, evitando una dependencia SQLite para un único
mapa acotado. Conserva hasta 100 sesiones pendientes por cuenta, sin tokens ni URLs
de audio. La cola se restaura al volver a la misma cuenta, y nunca se envía con otra
identidad. Una cola llena no admite nuevas sesiones hasta liberar espacio.
Los checkpoints no garantizan conservar el último tramo ante terminación abrupta;
se requiere medir el margen en dispositivo. Las preferencias usan escritura
asíncrona nativa; PostgreSQL continúa como fuente de verdad confirmada.

## Verificación local

- Cinco pruebas nuevas de reglas de servicio correctas.
- Typecheck, lint y build backend correctos.
- Suite backend completa bloqueada parcialmente por EPERM al abrir puertos:
  90 pruebas pasaron, 65 fallaron por permisos de escucha y 14 PostgreSQL se omitieron.
- Flutter CLI bloqueado al escribir en el SDK montado de solo lectura.
- Análisis Dart directo ejecutado sobre implementación y pruebas nuevas.
- Añadidas tres pruebas PostgreSQL de concurrencia, conflictos de propietario,
  paginación, RLS y cascada; omitidas localmente por falta de TEST_DATABASE_URL.
- Añadidas cuatro pruebas Flutter de medición, reintentos persistentes, cambio de
  cuenta y nueva sesión. Su ejecución sigue bloqueada por el SDK de solo lectura.
- Eliminado acumulador redundante y permitido inyectar reloj para pruebas.

## Pendiente antes de cerrar

Pruebas PostgreSQL reales de migración, idempotencia concurrente y aislamiento;
pruebas Flutter de medición, persistencia y paginación; build Kotlin/APK, tamaño;
aceptación física con dos cuentas, segundo dispositivo, segundo plano, seek,
reconexión, cambio de cuenta y recuperación tras cierre. Desplegar migración
revisada a Supabase y backend HTTPS, comprobar CI y documentar evidencia.
No se ha publicado ni etiquetado sprint-10-v0.10.0.

## Pruebas adicionales — 14 de noviembre de 2026

### Resultados comprobados

- Backend: 83 pruebas correctas en 11 archivos que no necesitan sockets, incluidas
  cinco pruebas de HistoryService y seis de la ruta Express. Estas últimas
  ejecutan autorización, validación, conflicto y paginación en proceso mediante
  IncomingMessage/ServerResponse; no son una prueba HTTP sobre la red.
- Flutter: ocho casos de listening_tracker_test.dart ejecutados directamente en
  flutter_tester con kernel compilado y servicio VM deshabilitado. Diez casos de
  queue_playback_test.dart también pasaron con el mismo mecanismo.
  Un harness temporal sustituye exclusivamente registro/ejecución de casos y
  aplica los matchers a sus aserciones; estos resultados no equivalen a haber
  ejecutado la suite convencional de flutter test ni las pruebas de widgets.
- PostgreSQL 18.6 real: cluster desechable independiente, inicializado en scratch,
  ejecución monousuario sin servidor. Las seis migraciones se aplicaron desde
  cero, generando las nueve tablas. Aserciones SQL verificaron máximo acumulado,
  OR de completed, reintento idempotente, rechazo de cambio de propietario,
  RLS, ausencia de SELECT para anon/authenticated, límites CHECK y cascada.
  Este procedimiento no prueba concurrencia ni el adaptador Prisma.
- MainActivity.kt compiló con Kotlin 2.4.0 y clases reales Android 37, Flutter,
  audio_service y el resolvedor previamente compilado. Es una comprobación de
  compilación del canal, no un nuevo APK ni una prueba de preferencias en Android.
- Typecheck, lint y formato backend; análisis Dart y git diff --check correctos.

### Defectos corregidos y cubiertos

1. Cambio de cuenta: el último checkpoint se conserva bajo la cuenta original
   sin enviarlo con la identidad nueva.
2. Cierre durante restauración: ya no se descartan registros persistidos antes
   de que termine la lectura local.
3. Cola llena: el límite de 100 impide añadir sesiones nuevas, pero permite
   seguir enviando las existentes al recuperar conectividad.

### Límites que permanecen

La copia temporal del SDK permite compilar kernel, pero el runner convencional
Flutter no puede abrir su socket local (EPERM). Docker no es accesible y no hay
TEST_DATABASE_URL configurada. Por ello siguen pendientes las tres pruebas
Prisma/PostgreSQL con servidor, concurrencia real, las demás pruebas HTTP con
listener y la suite convencional Flutter/widgets. Faltan APK completo, tamaño,
aceptación con dos cuentas/dispositivos y despliegue HTTPS. Sprint aún abierto.

## Reintento de validación — 14 de noviembre de 2026

- `pnpm test`: 101 pruebas correctas, 65 fallos por `listen EPERM`, 17 omitidas
  por ausencia de `TEST_DATABASE_URL`. Los fallos de apertura de sockets no
  demuestran defectos funcionales ni cuentan como pruebas correctas.
- Backend: lint, typecheck, formato y build correctos.
- `flutter analyze --no-pub`: sin incidencias usando la copia temporal escribible
  del SDK y telemetría deshabilitada.
- `flutter test --no-pub --no-enable-impeller`: los 16 archivos fallan durante la
  carga del runner por `Failed to create server socket`, antes de ejecutar casos.
- Herramientas Python: cinco pruebas correctas.
- APK debug: no generado en este reintento. Con caché Gradle escribible, Gradle
  falla creando `FileLockContentionHandler` porque no puede determinar una IP
  wildcard utilizable. Los APK preexistentes no validan estos cambios.
- ADB: no puede iniciar el listener local (`Operation not permitted`); no se
  ejecutó aceptación física. No se alteraron Supabase ni el despliegue remoto.

### Validación automática desde la terminal del equipo

Ejecutar desde la raíz del proyecto, en el host con Docker disponible, Flutter,
Android SDK y dependencias de desarrollo instaladas:

```bash
bash tool/verify-sprint-10.sh
```

El script reproduce los controles de CI, crea un PostgreSQL 17 desechable en un
puerto local asignado por Docker, aplica las seis migraciones y ejecuta toda la
suite backend, incluidas las pruebas Prisma de concurrencia. Después ejecuta
formato, análisis, suite Flutter convencional, pruebas Python y compilación APK
debug, con tamaño y SHA-256. Los logs se guardan en una carpeta temporal cuya
ruta se imprime al finalizar. El contenedor se elimina al salir. No utiliza
`backend/.env` ni modifica Supabase. Este script ha sido revisado sintácticamente;
su ejecución completa sigue pendiente fuera del entorno restringido.

### Aceptación física que sigue pendiente

Usar una compilación configurada con Firebase y el backend HTTPS con la migración
de historial desplegada; el APK debug genérico de CI no acredita ese flujo.

1. Cuenta A: escuchar menos del umbral y comprobar que no aparece; superar el
   umbral y comprobar una sola sesión pese a varios checkpoints.
2. Pausar, reanudar, hacer seek y usar segundo plano; comprobar que solo se suma
   tiempo de reproducción y que un seek al final no marca finalización completa.
3. Desconectar red, escuchar y reconectar; verificar envío sin duplicados.
4. Cambiar a cuenta B con envíos pendientes; comprobar aislamiento. Volver a A
   y confirmar recuperación, incluyendo cierre y reapertura de la app.
5. Abrir la cuenta A en otro dispositivo y comprobar persistencia centralizada;
   comprobar orden cronológico, cargar más, refrescar y abrir el detalle.

No cerrar ni etiquetar el sprint hasta registrar los resultados automáticos y
la aceptación física, además de verificar despliegue y CI.

## Ejecución en el host — 14 de noviembre de 2026, 20:40 UTC−5

Evidencia leída de `/tmp/mysic-sprint10-validation.tIhaVo/`:

- PostgreSQL 17 Docker: las seis migraciones aplicadas correctamente.
- Backend: 182 pruebas correctas y una fallida de 183, sin omisiones. Lint,
  typecheck y formato correctos. El script detuvo esa rama antes del build.
- El fallo real se produjo en la primera inserción concurrente de una canción:
  `tx.track.upsert` con `update: {}` recibió una violación de unicidad
  `tracks_source_source_id_key`.
- Flutter: formato correcto, análisis sin incidencias, suite convencional
  completa con 70 casos correctos y cinco pruebas Python correctas.
- APK debug generado: 177389237 bytes (169,2 MiB), SHA-256
  `8627abeae227eb659bd7e91302c56c4beaf09e1b6bcbe127b7eaf8f59a3c2d1d`.
  Esta compilación genérica no verifica autenticación real ni aceptación física.

Corrección posterior: la creación de la canción en el repositorio de historial
usa ahora `INSERT ... ON CONFLICT ... RETURNING id`, parametrizado y dentro de
la misma transacción, conservando los metadatos existentes. La prueba original
se reforzó a ocho checkpoints concurrentes de la primera canción. Lint,
typecheck, formato, build backend y las once pruebas de servicio/rutas de historial
pasaron después del cambio. Falta repetir en el host la suite Prisma completa
para confirmar la corrección bajo concurrencia real; no se considera validada
por esos controles estáticos y de servicio. El script suprime la pregunta
opcional de Prisma con `--no-hints`.

## Revalidación posterior a la corrección — 14 de noviembre de 2026

Logs revisados: `/tmp/mysic-sprint10-validation.z6nLCg/`, backend iniciado a las
20:43:45 (hora de Lima).

- Backend: 183 de 183 pruebas correctas en 24 archivos, sin omisiones. Incluye
  las tres pruebas Prisma de historial y la carrera de ocho checkpoints con
  creación inicial de la canción. La regresión de unicidad queda verificada en
  PostgreSQL 17 real. Seis migraciones aplicadas correctamente; validación,
  generación Prisma, lint, tipos, formato y build correctos.
- Flutter: 70 de 70 pruebas convencionales correctas, análisis sin incidencias,
  formato sin cambios y cinco pruebas Python correctas.
- APK debug generado nuevamente: 177389237 bytes, SHA-256
  `8627abeae227eb659bd7e91302c56c4beaf09e1b6bcbe127b7eaf8f59a3c2d1d`.

La validación automática local queda completada. Continúan pendientes aceptación
física con dos cuentas/dispositivos, despliegue revisado a Supabase y backend
HTTPS, comprobación de CI y cierre formal con commit, push y etiqueta.

### Preparación de aceptación USB local

`bash tool/device-sprint-10.sh` prepara un PostgreSQL desechable con las seis
migraciones y un backend local actualizado, usando la configuración Firebase
existente. Compila e instala el APK debug configurado para ese backend en
`kfz5cugawodihaj7` (se puede pasar otro serial como primer argumento). Utiliza
`adb reverse` en el puerto 33010, sin modificar la configuración permanente ni
Supabase. No reemplaza un reverse previo en ese puerto.

La terminal debe permanecer abierta y el teléfono conectado. El script muestra
la secuencia de aceptación manual, conserva logs y un resumen agregado sin
identificadores de usuario, y elimina el contenedor y su reverse al finalizar.
La base temporal se pierde al terminar. No declara aprobadas pruebas físicas:
requiere observación y resultados del operador. El script se verificó con
`bash -n`; su ejecución en el host está pendiente. Esta prueba local no acredita
HTTPS, conectividad externa, recuperación de red ni segundo dispositivo.

### Preparación de despliegue HTTPS y actualización Android

El primer intento de instalación física falló con
`INSTALL_FAILED_VERSION_DOWNGRADE`: la app instalada tenía código 2009 (release
ARM64 del Sprint 9) y el APK debug genérico código 9. La instalación no reemplazó
la app; por tanto, la ausencia de Mi historial en ese intento no demuestra un
problema de navegación del código nuevo.

Versión preparada: `0.10.0+10`. El APK release ARM64 dividido usa código 2010;
la prueba debug local fija también `--build-number=2010`. Se conserva la firma
debug usada por el release de desarrollo existente y se utiliza `adb install -r`,
sin desinstalar ni borrar los datos de la app.

El usuario autorizó publicar en Render para continuar la aceptación física contra
HTTPS. `tool/publish-sprint-10.sh` prepara únicamente los archivos del Sprint 10,
crea un commit de funcionalidad y hace push normal a `origin/main`. No publica
etiqueta ni declara cierre. El Blueprint existente está configurado para desplegar
después de CI e incluye `prisma migrate deploy` antes del arranque.

Después de confirmar CI, migración y despliegue live, ejecutar
`bash tool/install-sprint-10-cloud.sh` desde el host: comprueba HTTP 401 de la
ruta de historial sin token, compila con Firebase y URL HTTPS, instala el APK
ARM64 y reinicia la app. La comprobación 401 no acredita por sí sola la migración
ni las operaciones autenticadas. Los scripts se comprobaron sintácticamente;
publicación, despliegue y nueva instalación siguen pendientes. El conector GitHub
de esta sesión no tiene permiso de escritura en el repositorio; el push debe
realizarse desde la terminal del host con su acceso SSH configurado.

## Despliegue verificado — 14 de noviembre de 2026

- Commit publicado en `main`: `a3f753ada30695bf35e63ae4497247e818453810`.
- GitHub Actions [Quality #93](https://github.com/MarckDL/Mysic_App/actions/runs/43666264843):
  jobs backend y mobile completados con `success`, incluidos pruebas y APK.
- Workspace Render confirmado por el usuario: Marck's workspace.
- Servicio `mysic-api-k03u`, deploy `dep-dbshbctckfvc73dldokg`, commit exacto
  `a3f753a`: estado `live` confirmado a las 21:16:51 de Lima.
- Logs de build: `20261115020000_create_history` aplicada correctamente sobre
  Supabase a las 21:15:49, seis migraciones encontradas, build exitoso.
- Logs de runtime: `server_started` en el puerto 10000 y servicio live, con
  health check configurado en `/api/v1/health`.
- URL: `https://mysic-api-k03u.onrender.com`.

No se ha completado todavía una solicitud autenticada de historial ni instalado
el APK HTTPS nuevo en el teléfono. El siguiente paso es ejecutar desde el host
`bash tool/install-sprint-10-cloud.sh`, comprobar instalación y continuar con
aceptación física. El script comprobará también la respuesta 401 sin token.
La consulta pública directa mediante la herramienta web de esta sesión no pudo
acceder a los endpoints y no se cuenta como verificación HTTP independiente.
No se publicó etiqueta de cierre.

## Aceptación física asistida — resultados comunicados por el usuario

- El usuario confirmó que la actualización quedó instalada en su teléfono.
- Umbral de escucha: una canción de Ado reproducida durante 10 segundos no
  apareció en el historial; otra reproducida durante 40 segundos sí apareció,
  una sola vez, según la confirmación del usuario a la secuencia propuesta.
  Títulos recordados de forma aproximada: «Eien no Akuruhi» y «Tsumi to Batsu»;
  no se verificaron los títulos ni su orden exacto.
- Estos resultados son observaciones del operador en el teléfono; no se
  observaron directamente por ADB ni se inspeccionaron filas autenticadas.
- Nueva selección: el usuario reprodujo una canción identificada como Luma,
  después dos de Ado y volvió a seleccionar Luma; apareció una nueva entrada
  posterior a Ado, compatible con una nueva sesión explícita.
- Pausa/reanudación: siguiendo la secuencia de pausar, esperar 10 segundos,
  continuar desde el reproductor 15 segundos y refrescar, el usuario confirmó
  que no se agrega otra entrada. No se inspeccionó el acumulado de milisegundos.
- Persistencia: después de la secuencia propuesta de pausar, forzar detención
  desde Android y reabrir con la misma cuenta, el usuario confirmó que todo sigue
  bien: canciones conservadas en el mismo orden y sin entradas nuevas.
- Segundo plano: el usuario confirmó reproducción continua y una sola entrada
  nueva tras seleccionar otra canción de más de un minuto, permanecer 45 segundos
  en la pantalla de inicio de Android, regresar, pausar y refrescar el historial.
- Seek: el usuario confirmó que una canción de más de dos minutos, escuchada
  cinco segundos y adelantada a unos diez segundos del final, no apareció en el
  historial al terminar. El salto no se convirtió en escucha válida.
- Aislamiento y cambio de cuenta: siguiendo la secuencia de cerrar sesión,
  entrar con otra cuenta Google, consultar historial y volver a la original,
  el usuario confirmó que la segunda no muestra escuchas de la primera y que
  el historial original se mantiene intacto al regresar.
- Continúan pendientes recuperación de red con cola persistida y otro dispositivo.
- Intento sin red: el usuario reportó que el audio se detiene antes de completar
  los 35 segundos adicionales y que el indicador vuelve al segundo 10, posición
  donde pausó para desactivar datos. La prueba de cola persistida queda
  inconclusa, no aprobada ni fallida. El motor configura un búfer máximo de 15
  segundos; el procedimiento solicitaba más reproducción offline de la que
  garantiza ese búfer. La vuelta del indicador al segundo 10 no se diagnosticó
  con logs y queda como observación pendiente.
- Recuperación posterior: al reactivar internet y pulsar continuar, el usuario
  confirmó que la canción reinició desde el principio y luego se agregó al
  historial. Esto verifica que volvió a reproducir/registrar, pero revela una
  pérdida de posición y no acredita conservar la sesión ni recuperar la cola.

### Corrección de recuperación de audio — pendiente de nueva aceptación

Se identificó en `TrackPlaybackController.resume` que los estados de error se
recuperaban con `jump`, que reiniciaba posición y UUID. La recarga por error ahora
conserva la sesión de historial y hace seek a la última posición conservada antes
de reproducir. Los eventos nativos posteriores a un error no sobrescriben esa
posición. Pausar durante buffering de una fuente ya cargada conserva el motor,
mientras cancelar una carga inicial sigue impidiendo autoplay tardío.

Cuatro regresiones nuevas cubren posición tras error, pausa durante buffering,
fallo de una recuperación y cambio de pista durante recuperación. Una prueba
integrada de controlador y tracker verifica mismo UUID y 45 segundos acumulados
tras 30 segundos de reproducción, 60 sin reproducir y otros 15 reproduciendo.

Comprobaciones locales: análisis Flutter sin incidencias, formato correcto,
14 casos de cola y nueve de tracker correctos en el motor Flutter directo con
harness temporal (no equivalen al runner convencional). Cinco casos son nuevos.
La suite convencional completa queda pendiente del host: el script de
instalación HTTPS ahora ejecuta formato, análisis y tests antes de compilar.

Versión preparada `0.10.1+11`, APK release ARM64 código 2011. La instalación y
aceptación de esta corrección siguen pendientes, al igual que su commit/push.
El backend desplegado permanece compatible. El script de publicación incluye
las pruebas y el fake de motor nuevos; admite un mensaje de commit como argumento.

### Revalidación 0.10.1 en el host y teléfono

Logs revisados de `/tmp/mysic-sprint10-cloud-apk.0LkfYH/`:

- Suite Flutter convencional: 75 casos correctos, incluidos los cinco de
  regresión de recuperación nuevos. Análisis Flutter sin incidencias.
- Release ARM64 compilado correctamente: 22517494 bytes, SHA-256
  `8f1f8ac57866991749d3d3b1abb560a965783c96ba72f5f8dc3b2bc3673c883e`.
- Tras probar la actualización, el usuario confirmó que continuar después de
  una desconexión conserva el avance y que la escucha se registra al segundo
  30. Se valida recuperación de reproducción según su observación, sin una
  inspección física directa de UUID o milisegundos en la base.
- No pudo mantener los 35 segundos adicionales de audio offline por agotamiento
  del búfer; la recuperación de una escucha nueva elegible y persistida durante
  esa desconexión sigue inconclusa en dispositivo, aunque existe cobertura
  automatizada de reintentos y persistencia del tracker.
- Pendientes: segundo dispositivo, comprobación física de cola sin red y
  publicación del parche 0.10.1 (commit/push y CI). No se cierra el sprint.

### Publicación del parche y estado de cierre

- Parche publicado en `main` como
  `56718a56c9ffe175d4ad1d10216c023d2b3d38ec`, mensaje
  `fix(playback): preserve position and listening session on retry`.
- CI [Quality](https://github.com/MarckDL/Mysic_App/actions/runs/43670846697)
  todavía en curso al comprobar el cierre; no se declara aprobado aún.
- Render continúa sirviendo el backend compatible `a3f753a`; este parche cambia
  reproducción móvil, pruebas, herramientas y documentación, sin cambios backend.
- El usuario no dispone de otro teléfono y no se le solicita iniciar su cuenta
  Google en un dispositivo ajeno. La aceptación de recuperación desde otro
  dispositivo sigue pendiente; un emulador propio puede servir como segundo
  cliente independiente si se configura con la misma cuenta.
- Recuperación física de una escucha elegible persistida sin red: inconclusa por
  el búfer; cubierta en automatización, sin sustituir la evidencia física.
- Sin commit de cierre ni etiqueta remota `sprint-10-*`. Sprint aún abierto:
  los criterios pendientes no se marcan cumplidos por falta de dispositivo.

### Preparación del segundo cliente en emulador propio

El usuario propone usar su emulador Android Studio con la misma cuenta Google.
Se encontraron `Pixel_7` y `Medium_Phone_API_37.0`, ambos x86_64 con imagen Google
Play. El instalador HTTPS acepta ahora `emulator` como argumento: selecciona un
único emulador conectado, comprueba arranque y ABI, genera el release x86_64 y lo
instala solo en ese serial. Para el teléfono ARM64 mantiene el APK correspondiente.
Comando desde el host: `bash tool/install-sprint-10-cloud.sh emulator`.
No utiliza datos ni copias locales del teléfono ni `adb reverse`: se comprobará
la recuperación desde Supabase mediante login independiente en el emulador.
Instalación y aceptación de este segundo cliente todavía pendientes.

CI del parche `56718a5` volvió a comprobarse: workflow `43670846697` completado
con conclusión `success`. El instalador adaptado se verificó con `bash -n`;
su ejecución requiere la terminal del host con acceso a ADB.

### Segundo cliente — aceptación en emulador

Después de instalar en el emulador e iniciar sesión con la misma cuenta siguiendo
la secuencia propuesta, el usuario confirmó que funciona y que su historial se
sigue guardando. Se registra como aceptación asistida de recuperación del
historial desde un segundo cliente independiente contra Render/Supabase, sin
copiar datos del teléfono. No se afirma una inspección directa por ADB ni de las
filas de producción. El criterio de segundo dispositivo queda cubierto con el
teléfono y el emulador propio.

Logs del instalador en `/tmp/mysic-sprint10-cloud-apk.rfgagO/`: análisis sin
incidencias, 75 pruebas Flutter correctas y release x86_64 generado de 24074490
bytes, SHA-256 `db3dfde644f7eb9a033d19f8c86f20289fe0771e25f99cd50f747ea9dc0c43e4`.

La comprobación pendiente de cola sin red se ajusta al búfer: escuchar 25 segundos
online, pausar, desconectar Wi-Fi y datos, continuar al menos ocho segundos
audibles offline, pausar y esperar cinco segundos de persistencia. Forzar cierre,
reconectar y reabrir; verificar una sola entrada de esa sesión. El tiempo audible
offline es necesario para superar el umbral de 30 segundos mientras el backend
no está accesible; si no se logra, el resultado sigue inconcluso.

## Aceptación final y cierre preparado

El usuario confirmó «ya cargó, sí, solo una entrada» después de la prueba ajustada
de 25 segundos online, pausa, corte de Wi-Fi/datos, ocho segundos audibles offline,
pausa y espera de persistencia, cierre forzado y reapertura con internet. Se
registra como aceptación asistida de recuperación de una escucha elegible
pendiente persistida sin duplicado. Como el resto de pruebas físicas, es evidencia
comunicada por el operador, sin inspección directa por ADB ni extracción de tokens.

Los tres criterios de US-010 quedan cubiertos: historial privado persistente,
reintentos sin duplicados y recuperación desde un segundo cliente (teléfono y
emulador propio). Backend: 183 pruebas con PostgreSQL real; Flutter: 75 casos
convencionales y cinco pruebas Python. CI correcto para el código de aplicación
`56718a56c9ffe175d4ad1d10216c023d2b3d38ec`. El instalador de emulador y su APK
se comprobaron posteriormente en el host y por aceptación asistida.

El cierre usa `sprint-10-v0.10.1`, en lugar de la etiqueta inicial prevista
`sprint-10-v0.10.0`, porque incorpora la corrección de recuperación instalada como
versión 0.10.1. No se crea ni se reescribe ninguna etiqueta anterior.

Ejecutar desde el host: `bash tool/close-sprint-10.sh`. El script verifica rama,
remoto y que el código de aplicación coincide con el commit probado; prepara solo
README, seguimiento y herramientas de instalación/cierre, crea el commit
`chore(sprint-10): complete listening history`, hace push normal y crea/publica una
etiqueta anotada. Comprueba que el HEAD y la etiqueta remotos apuntan al commit
de cierre. No desinstala apps ni modifica datos de Supabase. La ejecución y
verificación remota final están pendientes al preparar este documento.
