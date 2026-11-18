# Mysic — Roadmap y planificación de sprints

- **Metodología:** Scrum adaptado
- **Duración de Sprint:** 2 semanas
- **Total planificado:** 16 sprints
- **Horizonte:** 32 semanas
- **Estado:** Planificación actualizada

## 1. Objetivo

Desarrollar Mysic mediante entregas incrementales, verificables y versionadas.

El alcance incluye Flutter, Google Sign-In, Express, PostgreSQL, catálogo experimental con youtubei.js, reproductor, biblioteca social e historial.

## 2. Reglas de trabajo

### 2.1 Duración

Cada Sprint dura 10 días laborables de referencia.

### 2.2 Planificación

Al comenzar cada Sprint:

1. Revisar el Product Backlog.
2. Seleccionar historias prioritarias.
3. Dividir historias en tareas técnicas.
4. Estimar capacidad real del equipo.
5. Definir Sprint Goal.
6. Confirmar criterios de aceptación.

### 2.3 Definition of Ready

Una historia está lista cuando:

- Tiene descripción clara.
- Incluye criterios de aceptación.
- Tiene dependencias identificadas.
- Puede probarse.
- Está estimada.
- Se relaciona con requisitos documentados.

### 2.4 Definition of Done

Una historia se considera terminada cuando:

- Su implementación está completa.
- Pasa lint y análisis estático.
- Pasa las pruebas aplicables.
- Cumple los criterios de aceptación.
- No contiene secretos.
- Tiene documentación actualizada.
- Ha sido revisada y demostrada.

## 3. Regla obligatoria de control de versiones

**Al finalizar y verificar cada Sprint, se DEBE realizar un `git commit` y `git push` formal etiquetando la versión/sprint.**

Esta regla es obligatoria y no puede omitirse.

Procedimiento:

1. Confirmar que las tareas comprometidas estén terminadas o documentar las pendientes.
2. Ejecutar pruebas y validaciones.
3. Actualizar la documentación.
4. Revisar `git status`.
5. Crear commit de cierre.
6. Subir los commits al repositorio remoto.
7. Crear una etiqueta Git anotada.
8. Subir la etiqueta.
9. Registrar la versión y el resultado del Sprint.

Ejemplo para Sprint 1:

```bash
git status
git add .
git commit -m "chore(sprint-01): complete foundation"
git push origin main
git tag -a sprint-01-v0.1.0 -m "Sprint 01 verified"
git push origin sprint-01-v0.1.0
```

Antes de ejecutar estos comandos, verificar que:

- Se está en la rama correcta.
- No hay secretos o credenciales preparados para commit.
- Los cambios han sido revisados.
- Las pruebas han pasado.
- No se sobrescribe trabajo remoto.

Si se utilizan ramas de feature, primero integrar mediante pull request y después etiquetar el commit integrado en `main`.

No crear etiquetas de sprints que no hayan sido verificados.

Las etiquetas publicadas deben tratarse como inmutables.

## 4. Convención de commits

Formato:

`tipo(alcance): descripción`

Tipos permitidos:

- feat
- fix
- refactor
- test
- docs
- chore
- ci

Ejemplos:

```text
feat(auth): implement Firebase Google Sign-In
feat(playlists): add authenticated CRUD
fix(catalog): handle provider timeout
test(users): verify cross-user isolation
docs(sprint-03): update database decisions
```

## 5. Sprint 01 — Fundamentos

### Objetivo

Establecer la estructura del monorepo y el entorno de desarrollo.

### Historia US-001

Como desarrollador, quiero disponer de una estructura modular para mantener frontend y backend separados.

Tareas:

- Crear `mobile/` con Flutter.
- Crear `backend/` con Express y TypeScript.
- Configurar ESLint, Prettier y análisis Dart.
- Configurar Git y GitHub.
- Crear README, AGENTS.md y docs.
- Definir `.env.example`.
- Configurar endpoint `/api/v1/health`.
- Configurar CI inicial.

Aceptación:

- Flutter inicia.
- Express responde a health.
- El repositorio no contiene secretos.
- La CI ejecuta verificaciones básicas.

Etiqueta: `sprint-01-v0.1.0`

## 6. Sprint 02 — Google Sign-In

### Objetivo

Implementar autenticación obligatoria.

### Historia US-002

Como usuario, quiero iniciar sesión con Google para acceder a mi cuenta Mysic.

Tareas:

- Crear proyecto Firebase.
- Registrar aplicación Android.
- Configurar Google Sign-In.
- Configurar SDK Flutter.
- Implementar pantalla de login.
- Obtener Firebase ID token.
- Inicializar Firebase Admin SDK.
- Crear middleware `requireAuth`.
- Implementar logout.
- Probar tokens inválidos y revocados.

Aceptación:

- Inicio de sesión funcional.
- Backend verifica tokens.
- Rutas privadas devuelven 401 sin credenciales.
- Cierre de sesión funcional.

Etiqueta: `sprint-02-v0.2.0`

## 7. Sprint 03 — PostgreSQL y usuarios

### Objetivo

Persistir perfiles y garantizar aislamiento multiusuario.

### Historia US-003

Como usuario, quiero conservar mi perfil y mis datos independientemente de otros usuarios.

Tareas:

- Configurar Supabase PostgreSQL.
- Configurar Prisma.
- Crear esquema `users`.
- Implementar migraciones.
- Crear `/api/v1/auth/sync`.
- Asociar Firebase UID con UUID interno.
- Almacenar Google ID cuando esté disponible.
- Implementar `/api/v1/users/me`.
- Crear pruebas de aislamiento.
- Preparar estrategia de eliminación de cuenta.

Aceptación:

- Dos cuentas crean registros distintos.
- Un usuario no puede consultar datos privados ajenos.
- El perfil persiste entre sesiones.

Etiqueta: `sprint-03-v0.3.0`

## 8. Sprint 04 — Catálogo experimental

### Objetivo

Implementar búsqueda musical mediante backend.

### Historia US-004

Como usuario, quiero buscar canciones por nombre o artista.

Tareas:

- Instalar youtubei.js en backend.
- Crear interfaz MusicProvider.
- Crear YoutubeProvider.
- Implementar búsqueda.
- Normalizar resultados.
- Crear `/api/v1/search`.
- Crear `/api/v1/tracks/:id`.
- Implementar caché LRU.
- Implementar UI de búsqueda.
- Probar errores y resultados vacíos.

Aceptación:

- Flutter muestra resultados normalizados.
- youtubei.js no está instalado en Flutter.
- Fallos externos producen respuestas controladas.

Etiqueta: `sprint-04-v0.4.0`

## 9. Sprint 05 — Viabilidad de reproducción

### Objetivo

Validar el mecanismo de reproducción antes de ampliar el reproductor.

### Historia US-005

Como usuario, quiero reproducir una pista cuando exista una fuente compatible.

Tareas:

- Definir contrato PlaybackResult.
- Crear endpoint `/api/v1/playback/resolve`.
- Evaluar límites de youtubei.js.
- Documentar restricciones de acceso.
- Integrar audio de prueba y validar que el stream alcance el final.
- Validar just_audio en Android.
- Probar interrupciones y errores.
- Documentar decisión de viabilidad.

Aceptación:

- Audio completo reproducible.
- Fallos del proveedor se manejan correctamente.
- Existe decisión técnica documentada sobre streaming.
- La prueba detecta streams limitados al primer minuto y no los declara completos.

Etiqueta: `sprint-05-v0.5.0`

### Ajuste de alcance acordado

El usuario validó la demo del Sprint 05 y acordó trasladar la prueba de resolución
real de audio de youtubei.js al Sprint 06. Sprint 05 verifica audio sintético propio
con just_audio y el contrato de disponibilidad; no acredita reproducción del catálogo.
La decisión y los límites de evidencia se registran en docs/09-sprint-05-viabilidad.md.

## 10. Sprint 06 — Reproductor

### Objetivo

Construir experiencia de reproducción móvil.

### Historia US-006

Como usuario, quiero controlar la reproducción incluso cuando la app está en segundo plano.

Tareas:

- Probar resolución real de audio de youtubei.js, atestación, URL completa y
  reproducción Android más allá del primer minuto.
- Registrar viabilidad y limitaciones. No asumir que cualquier pista del catálogo
  se puede reproducir ni prometer su disponibilidad antes de verificarla.
- Si una URL solo entrega el primer segmento, descartarla y continuar con otro
  cliente/proveedor antes de iniciar la reproducción.
- Crear PlayerController.
- Implementar play/pause.
- Implementar seek cuando corresponda.
- Implementar cola.
- Crear mini player.
- Crear pantalla completa.
- Integrar audio_service.
- Gestionar audio focus e interrupciones.
- Probar pantalla bloqueada.

Aceptación:

- Controles básicos funcionan.
- La cola conserva el orden.
- Reproducción en segundo plano funciona con fuente compatible.

Etiqueta: `sprint-06-v0.6.0`

### Ajuste de alcance del 4 de noviembre de 2026

R-007 fue retirada por decisión del propietario. El corte a 1:09 se abordará con
un spike de PoToken/atestación, resolvedor multi-cliente, validación del rango final
y proxy HTTP Range aislado. El detalle, fases, riesgos y criterios medibles están en
`docs/11-plan-resolucion-audio-letras.md`.

Las fases 0 a 5 quedaron implementadas y verificadas: PoToken, worker persistente,
fallback, validación final, proxy Range con seek y prueba Android prolongada. El 6
de noviembre de 2026 se verificaron cola de cinco pistas, pantalla bloqueada,
controles multimedia, tres fuentes de más de dos minutos, desconexión/reintento y
limpieza de sesión. Sprint cerrado como `sprint-06-v0.6.0`.

Letras simples/sincronizadas pasan a alcance deseable, pero no bloquean la etiqueta
del Sprint 6. Se implementan después de estabilizar el transporte mediante una
interfaz `LyricsProvider`, inicialmente LRCLIB y YouTube Music como fallback.

### Ajuste Android durante Sprint 07 — 11 de noviembre de 2026

Render recibe rechazo del proveedor para todos los clientes de reproducción aun
cuando la misma pista supera las pruebas de rangos desde la red del dispositivo.
Se aprobó sustituir la restricción anterior de R-005 por un adaptador nativo Android:
`youtubei.js` sigue limitado al backend y `NewPipeExtractor` queda aislado detrás
de `PlaybackSourceResolver`. La app transmite por HTTP Range, limita la caché a tres
resoluciones y ejecuta una sola extracción simultánea. La aceptación requiere prueba
física prolongada y controles de notificación antes de cerrar Sprint 07.

El 11 de noviembre se implementó la optimización de inicio: cliente HTTP reutilizable,
extracción mínima de audio, caducidad derivada de la URL, single-flight, cancelación
nativa de anticipación, calentamiento tras autenticación y prefetch de metadatos para
primera búsqueda estable/siguiente pista. La línea base ARM64 previa era 22.294.411
bytes y el resultado optimizado es 22.369.054 bytes, un aumento de 74.643 bytes que
permanece bajo el límite. El 12 de noviembre, 20 inicios anticipados alcanzaron p95
0,588 s y 20 cambios de cola p95 0,865 s. Las 20 selecciones calientes no anticipadas
quedaron en p50 1,601 s y p95 1,723 s; el PSS aumentó 36,3 MiB. Latencia anticipada
y APK cumplen. La latencia no anticipada y la repetición de la matriz mediante la
red móvil del operador se conservan como línea base y trabajo del Sprint 13; no
bloquean los requisitos funcionales RF-025 a RF-031 de playlists.

El 12 de noviembre de 2026 se completó la aceptación física final mediante una red
Wi-Fi externa ordinaria, sin `adb reverse`: dos cuentas Google mostraron bibliotecas
aisladas, y se verificaron creación, cambio de privacidad, incorporación,
reproducción, retiro, persistencia remota y eliminación. El backend público, las
migraciones y las baterías automatizadas quedaron en verde. Sprint cerrado como
`sprint-07-v0.7.0`. La prueba por red móvil del operador no se ejecutó por falta de
datos y queda documentada para el Sprint 13.

## 11. Sprint 07 — Playlists

### Objetivo

Implementar biblioteca personal centralizada.

### Historia US-007

Como usuario, quiero crear playlists que estén disponibles al iniciar sesión desde otro dispositivo.

Tareas:

- Crear tablas playlists y playlist_tracks.
- Implementar CRUD.
- Añadir y quitar canciones.
- Reordenar pistas con transacciones.
- Crear pantallas Flutter.
- Validar propiedad del recurso.
- Crear pruebas de integración.
- Desplegar una instancia preliminar del backend con HTTPS.
- Configurar el APK contra la URL remota y probarlo fuera de la red local.

Aceptación:

- Playlists persistidas en PostgreSQL.
- Solo el propietario puede modificarlas.
- La información se recupera después de reinstalar la app.
- El backend es accesible por HTTPS y la app funciona desde una red externa, sin
  depender de `adb reverse` ni de servicios locales. La matriz por red móvil del
  operador se registra para el Sprint 13 cuando no haya datos disponibles.

Etiqueta: `sprint-07-v0.7.0`

Plan de ejecución: `docs/12-plan-sprint-07.md`.

## 12. Sprint 08 — Favoritos y ratings

### Objetivo

Persistir preferencias musicales por usuario.

### Historia US-008

Como usuario, quiero guardar favoritos y calificar canciones.

Tareas:

- Crear tablas favorites y ratings.
- Implementar endpoints.
- Aplicar restricciones únicas.
- Implementar UI de favoritos.
- Implementar calificación de 1 a 5.
- Calcular promedio.
- Probar aislamiento y duplicados.

Aceptación:

- Favoritos persistentes.
- Una calificación activa por usuario y canción.
- Promedio calculado correctamente.

Etiqueta: `sprint-08-v0.8.0`

Plan y seguimiento: `docs/14-plan-sprint-08.md`.

Estado al 14 de noviembre de 2026: Sprint cerrado. Implementación, CI con PostgreSQL
efímero, migración Supabase y despliegue Render completados. La aceptación física
con dos cuentas confirmó aislamiento, promedio compartido, actualización sin
duplicados, persistencia y retiro reversible. Versión `sprint-08-v0.8.0`.

## 13. Sprint 09 — Comentarios

### Objetivo

Incorporar interacción social moderada.

### Historia US-009

Como usuario, quiero comentar canciones y consultar opiniones de otros usuarios.

Tareas:

- Crear tablas comments y comment_reports.
- Implementar publicación y edición.
- Implementar eliminación.
- Crear listado paginado.
- Aplicar límites y validación.
- Implementar reportes.
- Crear moderación básica.
- Probar permisos.

Aceptación:

- Comentarios identifican autor.
- Solo autor o moderador autorizado puede modificar.
- Reportes quedan registrados.
- Comentarios ocultos no aparecen públicamente.

La cola de moderación se abre desde el perfil de Android con un permiso
verificado por Firebase. Ver [contrato y operación](15-plan-sprint-09.md).

Sprint verificado con 169 pruebas backend, 62 Flutter, migración de Supabase,
despliegue Render activo y aceptación física de publicación, edición, reporte,
moderación, revocación del permiso y eliminación.

Etiqueta: `sprint-09-v0.9.0`

## 14. Sprint 10 — Historial

### Objetivo

Registrar actividad de escucha centralizada.

### Historia US-010

Como usuario, quiero consultar las canciones que he escuchado.

Tareas:

- Crear listening_history.
- Definir umbral de escucha válida.
- Crear identificadores idempotentes.
- Implementar registro de sesiones.
- Crear consulta cronológica.
- Implementar UI.
- Probar eventos duplicados.

Aceptación:

- Historial privado persistente.
- No se duplican eventos por reintentos.
- La información se recupera desde otro dispositivo.

Versión verificada: 0.10.1. Etiqueta de cierre: `sprint-10-v0.10.1`.

## 15. Sprint 11 — Rediseño de interfaz y navegación

### Objetivo

Facilitar el acceso al catálogo y a la biblioteca personal sin interrumpir la
reproducción al cambiar de sección.

### Historia US-015

Como usuario, quiero encontrar mi música y mi actividad desde secciones claras y
volver a mi búsqueda o al reproductor sin perder contexto.

- Organizar Inicio, Buscar y Biblioteca como destinos de una barra inferior.
- Mostrar las cinco escuchas recientes en Inicio y agrupar playlists, favoritos e
  historial en Biblioteca.
- Mover perfil, cierre de sesión y moderación autorizada a Cuenta.
- Rediseñar el acceso con Google, limitar el saludo a dos líneas y permitir un
  apodo opcional de hasta 24 caracteres desde Cuenta.
- Integrar el minirreproductor y adaptar los estilos a los temas claro y oscuro.

### Aceptación

- Playlists, favoritos e historial se abren en dos toques desde una pestaña principal.
- La búsqueda y la reproducción se conservan mientras se recorre la app.
- Cambiar de cuenta descarta el estado privado y aplica los permisos de la nueva sesión.
- El apodo se guarda por cuenta y actualiza el saludo. Quitar el apodo recupera
  el nombre de Google.
- Dos cuentas en Android verifican el flujo y los controles permanecen utilizables con texto ampliado.

Versión verificada: `0.11.0`. Etiqueta de cierre: `sprint-11-v0.11.0`.

Plan y seguimiento: [Sprint 11](17-plan-sprint-11.md).

## 16. Sprint 12 — Estadísticas

### Objetivo

Visualizar hábitos de escucha.

### Historia US-011

Como usuario, quiero ver mis canciones favoritas y tiempo de escucha.

Tareas:

- Implementar agregaciones SQL.
- Calcular minutos escuchados.
- Calcular canciones más frecuentes.
- Calcular artistas más frecuentes.
- Crear filtros temporales.
- Diseñar el dashboard y abrirlo desde Biblioteca.
- Añadir a Inicio «Tus canciones más escuchadas» y «Tus artistas más escuchados»
  con las escuchas confirmadas de los últimos 30 días.
- Añadir «Tendencias en Mysic», con el ranking agregado de canciones de los
  últimos siete días. Mostrar resultados agregados sin identidades ni historiales
  individuales.
- Probar coherencia de cálculos.

Aceptación:

- Métricas coinciden con historial.
- Los filtros funcionan.
- Ningún usuario accede a estadísticas privadas ajenas.
- El ranking personal se calcula para la cuenta activa. Tendencias muestra el
  mismo ranking agregado a todas las cuentas.

Etiqueta: `sprint-12-v0.12.0`

## 17. Sprint 13 — Optimización

### Objetivo

Mejorar rendimiento, seguridad y resiliencia.

### Historia US-012

Como usuario, quiero que Mysic gestione fallos de red sin perder mis datos.

Tareas:

- Optimizar consultas PostgreSQL.
- Revisar índices.
- Ajustar caché.
- Implementar reintentos controlados.
- Revisar rate limiting.
- Mejorar logging.
- Revisar expiración de sesión.
- Validar estados offline.
- Ejecutar pruebas de rendimiento.

Aceptación:

- No hay pérdida de datos confirmados.
- Fallos externos no bloquean toda la app.
- Se cumplen objetivos medibles prioritarios.

Etiqueta: `sprint-13-v0.13.0`

## 18. Sprint 14 — Importación desde YouTube Music

### Objetivo

Facilitar la transición con copias privadas de playlists y canciones guardadas
a partir de Google Takeout.

### Historia US-016

Como usuario de YouTube Music, quiero elegir las listas de mi exportación,
revisar las canciones disponibles y guardar una copia en mi biblioteca Mysic.

Tareas y aceptación:

- Leer ZIP y CSV en Flutter, dividir listas en partes de hasta 500 pistas y
  mostrar filas inválidas, pistas reconocidas, ausencias y fallos reintentables.
- Crear borradores privados de 24 horas, resolver metadatos mediante MusicProvider
  y confirmar cada lista de forma transaccional e idempotente.
- Verificar autenticación, aislamiento, orden, red interrumpida y confirmación concurrente.
- Aceptar una exportación real en Android con dos cuentas Google y verificar
  reproducción de una pista compatible.

Estado al 18 de noviembre de 2026: implementación adelantada por solicitud del
propietario. Los Sprints 12 y 13 conservan su lugar y criterios pendientes.
El backend está desplegado, la migración aplicada en Supabase y la versión
0.11.1 instalada en Android. La aceptación de campo y el cierre formal quedan
pendientes según [seguimiento](18-sprint-14-importacion-youtube-music.md).

Etiqueta de cierre prevista: `sprint-14-v0.14.0`.

## 19. Sprint 15 — Calidad y pruebas

### Objetivo

Validar integralmente la aplicación.

### Historia US-013

Como responsable del proyecto, quiero garantizar que los flujos críticos sean demostrables.

Tareas:

- Pruebas end-to-end.
- Pruebas con dos cuentas Google.
- Pruebas de permisos.
- Pruebas de reproducción completa, rangos y caducidad.
- Pruebas de regresión.
- Pruebas de conectividad.
- Revisión de seguridad.
- Corrección de defectos bloqueantes.

Aceptación:

- Flujos críticos pasan.
- No hay defectos bloqueantes conocidos.
- Resultados de pruebas documentados.

Etiqueta: `sprint-15-v0.15.0`

## 20. Sprint 16 — Entrega académica

### Objetivo

Preparar Mysic para presentación y evaluación.

### Historia US-014

Como estudiante, quiero presentar una aplicación funcional con arquitectura documentada.

Tareas:

- Generar APK de demostración.
- Verificar configuración Firebase Android.
- Desplegar backend.
- Verificar PostgreSQL.
- Actualizar README.
- Completar diagramas.
- Documentar limitaciones.
- Preparar presentación.
- Grabar o ensayar demo.
- Cerrar backlog académico.

Aceptación:

- APK instalable.
- Google Sign-In funcional.
- Backend accesible.
- Datos centralizados.
- Demo reproducible sin corte al primer minuto.
- Documentación completa.

Etiqueta: `sprint-16-v1.0.0`

## 21. Riesgos

| Riesgo                         | Impacto | Mitigación                                        |
| ------------------------------ | ------- | ------------------------------------------------- |
| Cambios en youtubei.js         | Alto    | Adaptador MusicProvider                           |
| Rotación de atestación/streams | Crítico | Worker aislado, fallback y pruebas de rango final |
| Errores de Firebase            | Alto    | Pruebas desde Sprint 2                            |
| Acceso entre usuarios          | Crítico | Autorización y pruebas multiusuario               |
| Cuotas gratuitas               | Medio   | Monitoreo y hosting local alternativo             |
| Tiempo insuficiente            | Alto    | Priorización del backlog                          |
| Problemas Android              | Medio   | Pruebas en dispositivo físico                     |

## 22. Seguimiento

Cada Sprint debe registrar:

- Objetivo.
- Historias seleccionadas.
- Tareas completadas.
- Pruebas realizadas.
- Problemas encontrados.
- Trabajo pendiente.
- Commit de cierre.
- Etiqueta Git publicada.
- Enlace a la versión en GitHub.

El Sprint no se considera cerrado hasta completar la validación y el procedimiento de versionado.

## Seguimiento Sprint 10

Historial validado con 183 pruebas backend, 75 Flutter, CI correcto del parche
`56718a5` y aceptación asistida en teléfono y emulador propio contra Render y
Supabase. Incluye persistencia, aislamiento, segundo plano, seek y recuperación
de escucha pendiente tras cierre sin red. Ver [evidencia](16-plan-sprint-10.md).
Publicación formal mediante `tool/close-sprint-10.sh`, etiqueta
`sprint-10-v0.10.1`; comprobar el push antes de declarar cerrado el versionado.
