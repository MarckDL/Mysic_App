# Plan del Sprint 07 — Playlists

## 1. Propósito

Implementar una biblioteca de playlists centralizada, multiusuario y persistida en
PostgreSQL. Un usuario autenticado podrá crear y administrar sus playlists, añadir,
retirar y reordenar canciones, configurar su privacidad y recuperar la misma
información al iniciar sesión desde otra instalación o dispositivo.

Versión objetivo: `sprint-07-v0.7.0`.

## 2. Alcance obligatorio

| Requisito | Resultado verificable |
|---|---|
| RF-025 | El usuario crea una playlist asociada a su identidad interna. |
| RF-026 | El propietario edita nombre y descripción. |
| RF-027 | El propietario elimina su playlist. |
| RF-028 | El propietario añade y retira ocurrencias de canciones. |
| RF-029 | El propietario reordena todas las canciones en una transacción. |
| RF-030 | Las playlists se recuperan desde otra instalación con la misma cuenta. |
| RF-031 | El propietario cambia la visibilidad entre `private` y `public`. |

El Sprint incluye backend, migración, interfaz Flutter, pruebas automatizadas,
un despliegue preliminar HTTPS, verificación desde una red externa en un dispositivo
Android físico, documentación y cierre formal en Git/GitHub.

## 3. Estado de partida

- Sprint 06 cerrado en `main` y etiquetado como `sprint-06-v0.6.0`.
- Firebase Auth, sincronización de usuarios y cliente HTTP autenticado ya existen.
- PostgreSQL y Prisma contienen actualmente el modelo `User`; faltan `Track`,
  `Playlist` y `PlaylistTrack`.
- El catálogo ya entrega identificadores normalizados como `youtube:<videoId>`.
- Flutter aún no contiene el feature `playlists` ni sus rutas.
- Los endpoints existentes ya usan `/api/v1`, errores estructurados y verificación
  del Firebase ID token.

## 4. Decisiones de diseño

### 4.1 Identidad y autorización

- Ningún endpoint aceptará `userId`, `firebaseUid` ni otro selector de propietario.
- Después de validar el token de Firebase, el backend resolverá `firebase_uid` a
  `users.id`. Si el perfil no está sincronizado responderá `404 USER_NOT_SYNCED`.
- Todas las escrituras incluirán `user_id = authenticatedUser.id` en la consulta.
- Un recurso privado ajeno responderá `404 PLAYLIST_NOT_FOUND` para no revelar su
  existencia.
- Una playlist pública podrá ser consultada por otro usuario autenticado, pero solo
  el propietario podrá modificarla.

### 4.2 Persistencia

La migración Prisma añadirá:

- `Track`: referencia externa normalizada y única por `(source, source_id)`.
- `Playlist`: propietario, nombre, descripción, visibilidad y fechas.
- `PlaylistTrack`: ocurrencia de una pista, posición y fecha de incorporación.
- Relaciones con borrado en cascada desde playlist a sus ocurrencias.
- Índices por propietario y por playlist/posición.
- Unicidad de `(playlist_id, position)` para impedir órdenes ambiguos.

Se permitirán canciones repetidas: cada incorporación tendrá su propio
`playlist_tracks.id`, por lo que retirar una ocurrencia no eliminará las demás.

### 4.3 Canciones y proveedor musical

- Flutter enviará únicamente un ID de catálogo válido, por ejemplo
  `youtube:qhmrt3ZNgcs`.
- El backend resolverá ese ID mediante la capa de catálogo y la interfaz
  `MusicProvider`, normalizará sus metadatos y hará `upsert` de `Track`.
- No se guardarán URLs temporales de audio ni respuestas internas de youtubei.js.
- Añadir una canción no descargará audio ni bloqueará la creación de la playlist.

### 4.4 Orden y concurrencia

- Las posiciones serán enteros contiguos desde cero.
- Añadir, retirar y reordenar usarán transacciones Prisma.
- Reordenar recibirá la lista completa de IDs de ocurrencia de la playlist.
- El backend rechazará IDs faltantes, repetidos o ajenos con `400 INVALID_ORDER`.
- Para conservar la restricción única se aplicará una actualización en dos pasos
  dentro de una transacción serializable.
- Una colisión concurrente agotada responderá `409 PLAYLIST_CONFLICT`; Flutter
  recargará el detalle y conservará un mensaje visible para el usuario.

### 4.5 Límites iniciales

- Nombre: 1 a 150 caracteres después de recortar espacios.
- Descripción: opcional, máximo 2 000 caracteres.
- Visibilidad: `private` o `public`; valor inicial `private`.
- Máximo inicial: 500 ocurrencias por playlist.
- Los cuerpos se validarán con Zod o una validación de frontera equivalente y no
  se aceptarán propiedades desconocidas.

Si durante la implementación se cambia alguno de estos límites, se actualizarán
los requisitos y el contrato antes de incorporar el cambio.

## 5. Contrato HTTP propuesto

Todos los endpoints requieren Bearer token verificado.

| Método y ruta | Uso | Autorización |
|---|---|---|
| `GET /api/v1/playlists` | Listar playlists propias | Usuario autenticado |
| `POST /api/v1/playlists` | Crear playlist | Usuario autenticado |
| `GET /api/v1/playlists/:playlistId` | Consultar detalle y orden | Propietario o playlist pública |
| `PATCH /api/v1/playlists/:playlistId` | Editar metadatos o visibilidad | Solo propietario |
| `DELETE /api/v1/playlists/:playlistId` | Eliminar playlist | Solo propietario |
| `POST /api/v1/playlists/:playlistId/tracks` | Añadir una ocurrencia | Solo propietario |
| `DELETE /api/v1/playlists/:playlistId/tracks/:itemId` | Retirar una ocurrencia | Solo propietario |
| `PUT /api/v1/playlists/:playlistId/tracks/order` | Reemplazar el orden completo | Solo propietario |

Las respuestas usarán objetos de presentación propios del módulo, no objetos
Prisma. Las listas propias se ordenarán por `updatedAt` descendente y el detalle
de canciones por `position` ascendente.

## 6. Plan de ejecución

### Fase 0 — Contrato y línea base

1. Confirmar herramientas, conexión PostgreSQL, Firebase de desarrollo y dispositivo.
2. Registrar la batería actual de análisis y pruebas antes de modificar código.
3. Crear los DTO de petición/respuesta y la tabla de errores del módulo.
4. Confirmar que no hay secretos ni cambios ajenos en el árbol de trabajo.

Salida: contrato revisado y línea base verde.

### Fase 1 — Datos y dominio

1. Añadir modelos y relaciones al esquema Prisma.
2. Crear y revisar una migración SQL versionada.
3. Regenerar Prisma Client y validar el esquema.
4. Definir entidades, errores y puertos de repositorio del dominio playlists.
5. Añadir pruebas PostgreSQL de restricciones, cascadas y aislamiento por usuario.

Salida: migración reproducible y modelo de dominio independiente de Prisma.

### Fase 2 — Aplicación e infraestructura backend

1. Implementar resolución segura del usuario autenticado.
2. Implementar repositorios Prisma de playlists y pistas.
3. Implementar casos de uso CRUD y cambio de privacidad.
4. Implementar incorporación y retiro con actualización consistente de posiciones.
5. Implementar reordenamiento serializable y manejo de conflictos.
6. Resolver y normalizar canciones exclusivamente mediante `MusicProvider`.

Salida: casos de uso probados sin depender de Express.

### Fase 3 — API `/api/v1`

1. Implementar rutas, validación de parámetros y cuerpos, y DTO de salida.
2. Integrar los códigos `400`, `401`, `404`, `409` y `503` al formato común.
3. Montar el router en `app.ts` mediante inyección de dependencias comprobable.
4. Añadir pruebas de rutas y de autenticación con repositorios simulados.
5. Añadir pruebas de integración PostgreSQL para propiedad y privacidad.

Salida: API completa con aislamiento multiusuario verificable.

### Fase 4 — Feature Flutter

1. Crear `features/playlists/domain`, `data`, `application` y `presentation`.
2. Implementar modelos estrictos y repositorio sobre `AuthenticatedApiClient`.
3. Crear estado Riverpod para listado, detalle y mutaciones.
4. Crear pantallas de listado, creación/edición y detalle.
5. Integrar añadir a playlist desde el detalle de una canción.
6. Implementar retirar y reordenar con estados de carga, error y vacío.
7. Añadir la entrada `Mis playlists` y rutas al navegador autenticado.
8. Invalidar todo el estado del feature al cerrar o cambiar de cuenta.

Salida: flujo funcional de extremo a extremo sin lógica de negocio en widgets.

### Fase 5 — Pruebas y endurecimiento

1. Probar validación, errores, estados vacíos y recuperación de fallos en Flutter.
2. Probar creación, edición, borrado, repetidos y reordenamiento en backend.
3. Ejecutar la matriz multiusuario definida en la sección 7.
4. Verificar que logs, respuestas, commits y artefactos no contienen secretos.
5. Ejecutar análisis estático, formato, compilación y todas las pruebas.

Salida: CI local verde y evidencias trazables por requisito.

### Fase 6 — Despliegue preliminar HTTPS

1. Preparar un despliegue reproducible del backend desde GitHub.
2. Configurar Node LTS, `PORT`, health check y arranque mediante `pnpm`.
3. Proveer `DATABASE_URL`, Firebase Admin y demás secretos desde el alojamiento,
   nunca desde el repositorio ni desde Flutter.
4. Aplicar las migraciones Prisma versionadas contra Supabase.
5. Verificar `/api/v1/health`, autenticación real, catálogo, playlists y audio por
   rangos sobre la URL pública HTTPS.
6. Compilar el APK con `API_BASE_URL=https://<backend-remoto>`.
7. Validar la app mediante datos móviles, sin `adb reverse` ni servidor local.
8. Documentar arranque en frío, límites de tráfico y cualquier restricción del plan.

El servicio gratuito solo es aceptable para la validación preliminar. Si suspende
la instancia por inactividad o no sostiene el proxy de audio, se utilizará una
instancia siempre activa para la demostración final.

Salida: aplicación utilizable fuera de la red local con evidencias reproducibles.

### Fase 7 — Validación Android y cierre

1. Instalar el APK remoto actualizado en el dispositivo físico.
2. Completar el recorrido manual de aceptación y guardar resultados en `docs/`.
3. Probar recuperación tras borrar datos/reinstalar e iniciar con la misma cuenta.
4. Actualizar arquitectura, base de datos, roadmap y README si corresponde.
5. Revisar el diff final y confirmar que los criterios de aceptación se cumplen.
6. Hacer commit, integrar en `main`, push y etiqueta `sprint-07-v0.7.0`.
7. Verificar que la rama, etiqueta y GitHub Actions quedan en verde.

Salida: Sprint 07 cerrado formalmente y publicado en GitHub.

## 7. Matriz mínima de pruebas multiusuario

| Caso | Resultado esperado |
|---|---|
| Token ausente, inválido o vencido | `401 UNAUTHENTICATED` |
| Usuario no sincronizado | `404 USER_NOT_SYNCED` |
| Usuario A crea una playlist | Queda asociada a `users.id` de A |
| Usuario B intenta editar, borrar, añadir, retirar o reordenar en A | Operación rechazada sin filtrar datos privados |
| B consulta una playlist privada de A | `404 PLAYLIST_NOT_FOUND` |
| A hace pública su playlist y B la consulta | Lectura permitida; escritura rechazada |
| A vuelve privada la playlist | B deja de poder consultarla |
| Se añade dos veces la misma pista | Existen dos ocurrencias con IDs y posiciones distintos |
| Se retira una ocurrencia intermedia | Las posiciones restantes vuelven a ser contiguas |
| Se envía un orden parcial, duplicado o con un ID ajeno | `400 INVALID_ORDER`; no hay cambios parciales |
| Dos reordenamientos compiten | Uno se confirma o se informa conflicto; nunca queda orden ambiguo |
| A reinstala/inicia en otro dispositivo | Recupera playlists, metadatos y orden desde PostgreSQL |
| A elimina una playlist | Sus `playlist_tracks` se eliminan en cascada |

Además se mantendrán los seis controles de seguridad multiusuario obligatorios del
proyecto; playlists no debe debilitar autenticación, catálogo ni reproducción.

## 8. Criterios de aceptación del Sprint

El Sprint solo puede cerrarse cuando:

- RF-025 a RF-031 tienen prueba automatizada o evidencia manual explícita.
- La migración se aplica desde una base compatible y Prisma la reporta al día.
- Todas las operaciones privadas derivan el propietario del token verificado.
- El orden persiste sin huecos ni duplicados después de añadir, retirar y reordenar.
- La app recupera datos reales tras reinstalar o limpiar datos locales.
- La URL pública usa HTTPS y el APK funciona sin depender de `adb reverse`.
- Login, catálogo, playlists y reproducción se verifican mediante datos móviles.
- Backend: formato, lint, tipos, build y pruebas están en verde.
- Flutter: formato, `flutter analyze`, pruebas y APK Android están en verde.
- La prueba física cubre al menos dos cuentas para propiedad y privacidad.
- La documentación refleja el contrato final y cualquier desviación aprobada.
- El árbol de trabajo está limpio después del commit y el push.
- `main`, la etiqueta `sprint-07-v0.7.0` y GitHub Actions se verifican remotamente.

## 9. Fuera de alcance

- Playlists colaborativas o con múltiples propietarios.
- Compartir mediante enlaces públicos sin autenticación.
- Descarga de canciones u operación offline con escrituras diferidas.
- Imágenes personalizadas de portada.
- Favoritos y calificaciones, que pertenecen al Sprint 08.
- Letras, historial y estadísticas.
- Búsqueda o ranking global de playlists públicas.

## 10. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Reordenamientos simultáneos | Transacción serializable, restricción única y respuesta `409`. |
| Metadatos falsificados desde Flutter | Aceptar solo ID de catálogo y resolverlo en backend. |
| Fuga de datos entre cuentas | Filtrar por propietario en repositorio y cubrirlo con pruebas PostgreSQL. |
| Pista deja de existir en el proveedor | Conservar metadatos normalizados y mostrar indisponibilidad al reproducir. |
| Fallo a mitad de una mutación | Toda actualización de orden se confirma o revierte completa. |
| Regresión de reproducción | Reutilizar IDs normalizados y ejecutar la batería del Sprint 06. |
| Migración incompatible | Revisar SQL, probar despliegue en entorno de prueba y no editar producción manualmente. |

## 11. Secuencia recomendada de entregas

1. `feat(database): add playlist and track models`
2. `feat(playlists): implement playlist application services`
3. `feat(playlists): expose authenticated playlist api`
4. `test(playlists): verify ownership privacy and ordering`
5. `feat(mobile): add playlist management flow`
6. `test(mobile): cover playlist states and mutations`
7. `docs(sprint-07): record verification evidence`
8. `chore(sprint-07): complete sprint`

Cada entrega debe ser pequeña, revisable y mantener las pruebas existentes en verde.

## 12. Avance de ejecución — actualizado el 11 de noviembre de 2026

Completado:

- Modelos Prisma, migraciones y RLS aplicados en Supabase.
- CRUD autenticado, privacidad y ocultación de recursos privados ajenos.
- Incorporación, retiro, repetidos y reordenamiento transaccional.
- Feature Flutter con listado, formulario, detalle y selector desde canciones.
- 144 pruebas backend y 46 pruebas Flutter correctas, sin omisiones.
- Las pruebas backend incluyen 6 casos contra PostgreSQL real.
- Análisis estático, formato, compilación backend y APK Android correctos.
- APK instalado en el dispositivo `23117RA68G` sin errores fatales de inicio.
- Blueprint de Render y guía segura de despliegue preparados.
- Backend desplegado en `https://mysic-api-k03u.onrender.com` y estado `live`.
- Migraciones Prisma verificadas en Render; no existen migraciones pendientes.
- Health check público `200` y rutas privadas sin sesión/token inválido `401`.
- APK remoto compilado con la URL HTTPS de Render.
- El rechazo de streams desde la IP de Render quedó aislado del resto del backend.
- Se implementó un resolvedor Android detrás de `PlaybackSourceResolver`, sin
  descarga completa ni almacenamiento en disco.
- La versión release ARM64 compila en 22,5 MB; la extracción se limita a un trabajo
  simultáneo y una caché LRU de tres pistas en memoria.
- `flutter analyze` y 50 pruebas Flutter están en verde.
- El APK release fue instalado en el dispositivo físico `23117RA68G` conservando
  la sesión. La resolución nativa en frío tomó 2,27–2,50 s.
- `Luma` reprodujo más de 3:39 sin el corte de 1:09 y avanzó automáticamente.
- El proceso pasó de 163,9 MiB PSS al inicio a 188,4 MiB durante reproducción:
  incremento aproximado de 24,5 MiB después de inicializar extractor y audio.
- La sesión multimedia publicó estado `PLAYING` y cola de cuatro pistas. Siguiente
  cambió `Luma` → `Eclipsis`, anterior volvió a `Luma`, pausa/reanudación conservó
  posición y las resoluciones precargadas respondieron en 0 ms.
- La reproducción continuó activa durante más de 30 segundos con Mysic en segundo
  plano y el launcher visible.

Pendiente para cerrar el Sprint:

- Ejecutar la prueba física con datos móviles y una segunda cuenta Google.
- Confirmar pantalla bloqueada y seek manual en el APK final.
- Confirmar recuperación tras limpiar datos o reinstalar la aplicación.
- Publicar `sprint-07-v0.7.0` solo después de la aceptación física final.
