# Sprint 10 — Historial de escucha

Estado: implementación local; pendiente de aceptación y cierre. US-010, RF-047 a RF-050.

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
