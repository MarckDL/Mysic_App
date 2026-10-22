
# Mysic — Roadmap y planificación de sprints

**Metodología:** Scrum adaptado  
**Duración de Sprint:** 2 semanas  
**Total inicial:** 14 sprints  
**Horizonte:** 28 semanas  
**Estado:** Planificación base

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
- Integrar audio autorizado de prueba.
- Validar just_audio en Android.
- Probar interrupciones y errores.
- Documentar decisión de viabilidad.

Aceptación:

- Audio autorizado reproducible.
- Fallos del proveedor se manejan correctamente.
- Existe decisión técnica documentada sobre streaming.
- No se implementan mecanismos de evasión de restricciones.

Etiqueta: `sprint-05-v0.5.0`

## 10. Sprint 06 — Reproductor

### Objetivo

Construir experiencia de reproducción móvil.

### Historia US-006

Como usuario, quiero controlar la reproducción incluso cuando la app está en segundo plano.

Tareas:

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

Aceptación:

- Playlists persistidas en PostgreSQL.
- Solo el propietario puede modificarlas.
- La información se recupera después de reinstalar la app.

Etiqueta: `sprint-07-v0.7.0`

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

Etiqueta: `sprint-10-v0.10.0`

## 15. Sprint 11 — Estadísticas

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
- Diseñar dashboard.
- Probar coherencia de cálculos.

Aceptación:

- Métricas coinciden con historial.
- Los filtros funcionan.
- Ningún usuario accede a estadísticas privadas ajenas.

Etiqueta: `sprint-11-v0.11.0`

## 16. Sprint 12 — Optimización

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

Etiqueta: `sprint-12-v0.12.0`

## 17. Sprint 13 — Calidad y pruebas

### Objetivo

Validar integralmente la aplicación.

### Historia US-013

Como responsable del proyecto, quiero garantizar que los flujos críticos sean demostrables.

Tareas:

- Pruebas end-to-end.
- Pruebas con dos cuentas Google.
- Pruebas de permisos.
- Pruebas de reproducción autorizada.
- Pruebas de regresión.
- Pruebas de conectividad.
- Revisión de seguridad.
- Corrección de defectos bloqueantes.

Aceptación:

- Flujos críticos pasan.
- No hay defectos bloqueantes conocidos.
- Resultados de pruebas documentados.

Etiqueta: `sprint-13-v0.13.0`

## 18. Sprint 14 — Entrega académica

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
- Demo reproducible con fuente autorizada.
- Documentación completa.

Etiqueta: `sprint-14-v1.0.0`

## 19. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Cambios en youtubei.js | Alto | Adaptador MusicProvider |
| Restricciones de reproducción | Crítico | Validación temprana y audio autorizado |
| Errores de Firebase | Alto | Pruebas desde Sprint 2 |
| Acceso entre usuarios | Crítico | Autorización y pruebas multiusuario |
| Cuotas gratuitas | Medio | Monitoreo y hosting local alternativo |
| Tiempo insuficiente | Alto | Priorización del backlog |
| Problemas Android | Medio | Pruebas en dispositivo físico |

## 20. Seguimiento

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
