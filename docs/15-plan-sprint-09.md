# Sprint 09 — Comentarios y moderación

Sprint 09 implementa US-009 y RF-040 a RF-046. Android 0.9.0 incluye un listado
paginado en el detalle de canción, un editor de comentarios propios y un diálogo
de reporte para comentarios ajenos. El perfil de un moderador ofrece acceso a
la cola, donde puede ocultar un comentario o desestimar sus reportes.

## Contrato HTTP

Todas las rutas requieren Firebase ID token de Google, perfil sincronizado y
usan `Cache-Control: no-store`.

| Método y ruta | Solicitud y resultado |
|---|---|
| `GET /api/v1/tracks/:catalogTrackId/comments` | `{ items, nextCursor }`, comentarios visibles de más reciente a más antiguo |
| `POST /api/v1/tracks/:catalogTrackId/comments` | `{ body }`, comentario creado con `201` |
| `PATCH /api/v1/comments/:commentId` | `{ body }`, comentario propio actualizado con `200` |
| `DELETE /api/v1/comments/:commentId` | Baja lógica propia y cierre de reportes, `204` |
| `POST /api/v1/comments/:commentId/reports` | `{ reason }`, `204` incluso al repetir desde la misma cuenta |
| `GET /api/v1/moderation/comments` | `{ items, nextCursor }`, agrupado por comentario y ordenado por reporte pendiente más antiguo |
| `PATCH /api/v1/moderation/comments/:commentId` | `{ action: "hide" \| "dismiss" }`, resuelve los reportes pendientes con `204` |

El listado admite `limit` de 1 a 50 (20 por omisión) y `cursor` opaco. Los
comentarios contienen `id`, `body`, `authorName`, `createdAt`, `updatedAt` e
`isMine`. La cola devuelve `firstReportAt` y motivos distintos en `reasons`, sin
identificadores de denunciantes. El texto se recorta y admite de 1 a 500
caracteres. Los motivos admitidos son `spam`, `harassment` y `other`. Si la entrada
de moderación ya fue resuelta, el servidor devuelve `409` y Android refresca la
cola. Los comentarios ocultos o eliminados quedan fuera del listado.

## Operación de Firebase

Desde un entorno administrativo autorizado y configurado para el proyecto
Firebase correcto, seleccionar la cuenta Google por su UID verificado. Con
Firebase Admin SDK, agregar el claim `moderator: true` preservando los claims
existentes. En Android, cerrar sesión y volver a entrar para renovar el token.
El campo `canModerateComments` se devuelve en `GET /api/v1/users/me` y en la
sincronización inicial del perfil.

Para retirar el permiso, quitar solo `moderator` y después revocar los refresh
tokens existentes. Express verifica revocación al validar el ID token. Confirmar
que la sesión anterior recibe `401` y que la sesión renovada recibe `403` al
intentar moderar.

```ts
// Operaciones separadas. auth es la instancia de Firebase Admin del proyecto.
const user = await auth.getUser(uid);
const claims = { ...user.customClaims };

// Alta
await auth.setCustomUserClaims(uid, { ...claims, moderator: true });

// Baja. Volver a leer los claims antes de aplicar este bloque.
delete claims.moderator;
await auth.setCustomUserClaims(uid, claims);
await auth.revokeRefreshTokens(uid);
```

## Verificación de cierre

- Backend con PostgreSQL real. Comprobar propiedad, paginación estable, reportes
  duplicados, resolución concurrente, baja con reportes pendientes y RLS.
- Android físico ARM64 contra HTTPS. Dos cuentas comunes prueban publicación,
  edición, reporte, eliminación y persistencia al reabrir la app. Una de las
  cuentas recibe temporalmente el permiso y comprueba ocultar y desestimar. Tras revocar el permiso, verificar
  que una sesión renovada pierde el acceso. Presupuesto del APK de 24 MB.
- Confirmar CI, despliegue en Render y migración de Supabase antes de publicar
  `sprint-09-v0.9.0`.

## Evidencia local — 14 de noviembre de 2026

- Las cinco migraciones se aplicaron desde cero en PostgreSQL 18.6. Los roles
  locales `anon` y `authenticated` quedaron sin acceso directo a ambas tablas.
- Backend: 169 pruebas correctas con PostgreSQL real, además de validación
  y generación Prisma, lint, tipos, formato y build.
- Mobile: 62 pruebas Flutter y 5 de herramientas, con formato y análisis
  estático correctos.
- APK release ARM64 0.9.0 (`versionCode 2009`) compilado contra el backend
  HTTPS. Tamaño de 22.517.338 bytes, dentro del presupuesto de 24 MB.

## Evidencia remota — 14 de noviembre de 2026

- GitHub Actions terminó correctamente en el commit `536c719`, incluido
  PostgreSQL 17 y el build Android.
- Render desplegó el mismo commit y alcanzó el estado `live`. Supabase reportó
  cinco migraciones aplicadas y el esquema al día.
- La ruta HTTPS `/api/v1/health` devolvió `200`. Las rutas de comentarios por
  canción y la cola de moderación devolvieron `401 UNAUTHENTICATED` sin token.

## Aceptación física — 14 de noviembre de 2026

- Se instaló el APK ARM64 release 0.9.0 en el Android conectado, contra el backend
  HTTPS y sin redirecciones de puertos.
- La cuenta A publicó dos comentarios sobre «One More Time (Radio Edit)», editó
  uno y comprobó su persistencia al forzar el cierre y abrir nuevamente la app.
- La cuenta B consultó los comentarios de A y mostró únicamente la acción
  Reportar sobre ellos. Registró un reporte por spam y otro por acoso.
- Por disponibilidad de cuentas propias, se utilizaron dos cuentas Google y se
  concedió temporalmente el rol de moderador a B. La cuenta adicional pertenece
  a un amigo del usuario. Las pruebas PostgreSQL cubren moderadores separados de
  los autores y denunciantes.
- B renovó su sesión y abrió la cola desde el perfil. Desestimó el reporte de
  spam y ocultó el comentario reportado por acoso, previa confirmación. Supabase
  conservó ambos reportes con moderador y fecha de resolución.
- Se retiró el claim temporal y se revocaron las sesiones de B. El intento de
  volver a abrir la cola recibió HTTP 401 y cerró la sesión. Después de entrar
  nuevamente, el perfil perdió la opción de moderación.
- B consultó la canción y encontró solo el comentario visible. Al volver a A,
  se eliminó ese comentario desde Android y el listado quedó vacío. Los registros
  de prueba conservan su estado lógico y los reportes resueltos como evidencia.

Sprint verificado y cerrado como `sprint-09-v0.9.0`.
