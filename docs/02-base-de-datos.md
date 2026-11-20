
# Mysic — Diseño de base de datos

**Motor:** PostgreSQL  
**Servicio propuesto:** Supabase  
**ORM:** Prisma  
**Modelo:** Relacional, multiusuario

## 1. Objetivo

Diseñar una base de datos centralizada que permita almacenar usuarios autenticados mediante Google, playlists, favoritos, calificaciones, comentarios, historial y estadísticas.

La base de datos almacena información propia de Mysic y referencias a canciones externas, no archivos musicales.

## 2. Identidad del usuario

La tabla `users` almacena:

- `id`: UUID interno.
- `firebase_uid`: UID único emitido por Firebase Authentication.
- `google_id`: identificador del proveedor Google, cuando esté disponible y verificado.
- `email`: correo asociado a la cuenta.
- `display_name`: nombre sincronizado desde Google.
- `nickname`: apodo privado y opcional de Mysic, de hasta 24 caracteres.
- `photo_url`: URL de fotografía.
- `created_at`: fecha de creación.
- `updated_at`: última actualización.

### Regla fundamental

Aunque se conserva `google_id`, todas las claves foráneas utilizan `users.id`.

`firebase_uid` permite localizar la cuenta después de verificar el Firebase ID token.

No se permite que Flutter seleccione libremente el propietario de una operación.

## 3. Modelo entidad-relación

```mermaid
erDiagram
    USERS ||--o{ PLAYLISTS : owns
    USERS ||--o{ FAVORITES : saves
    USERS ||--o{ RATINGS : creates
    USERS ||--o{ COMMENTS : writes
    USERS ||--o{ LISTENING_HISTORY : records
    USERS ||--o{ COMMENT_REPORTS : submits

    TRACKS ||--o{ FAVORITES : receives
    TRACKS ||--o{ RATINGS : receives
    TRACKS ||--o{ COMMENTS : receives
    TRACKS ||--o{ LISTENING_HISTORY : appears

    PLAYLISTS ||--o{ PLAYLIST_TRACKS : contains
    TRACKS ||--o{ PLAYLIST_TRACKS : included
    COMMENTS ||--o{ COMMENT_REPORTS : reported
```

## 4. Diccionario de datos

### 4.1 users

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| firebase_uid | VARCHAR(128) | UNIQUE, NOT NULL |
| google_id | VARCHAR(255) | UNIQUE, NULL |
| email | VARCHAR(320) | NULL |
| display_name | VARCHAR(150) | NOT NULL |
| nickname | VARCHAR(24) | NULL |
| photo_url | TEXT | NULL |
| created_at | TIMESTAMPTZ | NOT NULL |
| updated_at | TIMESTAMPTZ | NOT NULL |

`email` no debe utilizarse como identificador estable de la cuenta.

### 4.2 tracks

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| source | VARCHAR(50) | NOT NULL |
| source_id | VARCHAR(255) | NOT NULL |
| title | VARCHAR(500) | NOT NULL |
| artist_name | VARCHAR(255) | NOT NULL |
| duration_seconds | INTEGER | NULL |
| thumbnail_url | TEXT | NULL |
| metadata_updated_at | TIMESTAMPTZ | NOT NULL |

Restricción: `UNIQUE(source, source_id)`.

La tabla representa referencias externas normalizadas.

### 4.3 playlists

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK users |
| name | VARCHAR(150) | NOT NULL |
| description | TEXT | NULL |
| visibility | VARCHAR(20) | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL |
| updated_at | TIMESTAMPTZ | NOT NULL |

Valores de `visibility`: `private`, `public`.

Por defecto, las playlists son privadas.

### 4.4 playlist_tracks

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| playlist_id | UUID | FK playlists |
| track_id | UUID | FK tracks |
| position | INTEGER | NOT NULL |
| added_at | TIMESTAMPTZ | NOT NULL |

Se permiten canciones repetidas si el producto lo requiere.

Debe garantizarse una posición consistente dentro de cada playlist, utilizando transacciones al reordenar.

### 4.5 favorites

| Campo | Tipo | Restricción |
|---|---|---|
| user_id | UUID | FK users |
| track_id | UUID | FK tracks |
| created_at | TIMESTAMPTZ | NOT NULL |

Clave primaria compuesta: `(user_id, track_id)`.

Implementación Sprint 08: índice `(user_id, created_at)` para la biblioteca reciente,
índice por `track_id`, cascada al eliminar el usuario, RLS habilitado y permisos
públicos revocados.

### 4.6 ratings

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK users |
| track_id | UUID | FK tracks |
| score | SMALLINT | CHECK 1–5 |
| created_at | TIMESTAMPTZ | NOT NULL |
| updated_at | TIMESTAMPTZ | NOT NULL |

Restricción: `UNIQUE(user_id, track_id)`.

Un usuario mantiene una calificación activa por canción.

Implementación Sprint 08: `score` utiliza `SMALLINT` y `CHECK (score BETWEEN 1 AND
5)`. Existe un índice por `track_id` para promedio/cantidad, cascada al eliminar el
usuario, RLS habilitado y permisos públicos revocados.

### 4.7 comments

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK users |
| track_id | UUID | FK tracks |
| body | TEXT | NOT NULL |
| status | comment_status | NOT NULL, por defecto `visible` |
| created_at | TIMESTAMPTZ(3) | NOT NULL |
| updated_at | TIMESTAMPTZ(3) | NOT NULL |

Estados `visible`, `hidden` y `deleted`. El texto admite de 1 a 500 caracteres.
El listado usa el índice `(track_id, status, created_at, id)`. La eliminación
lógica retira el comentario del listado y cierra sus reportes pendientes.

### 4.7.1 comment_reports

| Campo | Tipo | Restricción |
|---|---|---|
| comment_id | UUID | PK compuesta, FK comments |
| reporter_id | UUID | PK compuesta, FK users |
| reason | comment_report_reason | `spam`, `harassment`, `other` |
| status | comment_report_status | `pending`, `dismissed`, `hidden`, `deleted` |
| created_at | TIMESTAMPTZ(3) | NOT NULL |
| moderator_id | UUID | FK users, opcional |
| resolved_at | TIMESTAMPTZ(3) | Requerido al cerrar |

La clave compuesta garantiza un reporte por cuenta y comentario, incluso tras
resolverlo. El índice `(status, comment_id, created_at)` respalda la cola.
Ambas tablas tienen RLS y permisos públicos revocados. Las operaciones sobre
un comentario existente lo bloquean durante la transacción para serializar
edición, baja, reportes y moderación.

### 4.8 listening_history

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK users |
| track_id | UUID | FK tracks |
| playback_session_id | UUID | UNIQUE |
| started_at | TIMESTAMPTZ | NOT NULL |
| listened_ms | BIGINT | NOT NULL |
| completed | BOOLEAN | NOT NULL |

`playback_session_id` permite evitar registros duplicados por reintentos.

### 4.9 comment_reports

| Campo | Tipo | Restricción |
|---|---|---|
| id | UUID | PK |
| reporter_id | UUID | FK users |
| comment_id | UUID | FK comments |
| reason | VARCHAR(100) | NOT NULL |
| status | VARCHAR(20) | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL |

Estados: `pending`, `reviewed`, `dismissed`.

## 5. Estadísticas

Las estadísticas deben calcularse a partir de `listening_history`.

Indicadores:

- Canciones más escuchadas.
- Artistas más escuchados.
- Tiempo total de escucha.
- Cantidad de reproducciones.
- Actividad diaria y mensual.

Inicialmente no se requiere una tabla materializada `user_statistics`.

Si el rendimiento lo exige, se podrá incorporar una tabla agregada o vista materializada.

No contar automáticamente cada inicio de audio como una reproducción válida. El umbral deberá definirse en las reglas de negocio.

## 6. Índices recomendados

```sql
CREATE INDEX idx_playlists_user
ON playlists(user_id);

CREATE INDEX idx_comments_track_created
ON comments(track_id, created_at DESC);

CREATE INDEX idx_history_user_started
ON listening_history(user_id, started_at DESC);

CREATE INDEX idx_history_user_track
ON listening_history(user_id, track_id);
```

Estos índices son conceptuales; las migraciones definitivas se generarán mediante Prisma.

## 7. Reglas de autorización

### Datos privados

Solo el propietario puede:

- Modificar sus playlists.
- Administrar sus favoritos.
- Modificar sus calificaciones.
- Consultar su historial.
- Consultar sus estadísticas personales.
- Editar su perfil.

### Datos públicos

Los usuarios autenticados pueden:

- Consultar comentarios visibles.
- Consultar calificaciones agregadas.
- Consultar playlists declaradas públicas.

Solo el autor o un moderador autorizado puede modificar un comentario.

### Regla de implementación

Cada consulta privada debe incluir el identificador interno del usuario autenticado.

Ejemplo:

```typescript
const playlists = await prisma.playlist.findMany({
  where: {
    userId: authenticatedUser.id
  }
});
```

El backend nunca debe confiar en un `userId` proporcionado por Flutter.

## 8. Firebase y PostgreSQL

Flujo de asociación:

1. Flutter obtiene Firebase ID token.
2. Express verifica el token.
3. Express obtiene `firebase_uid`.
4. Express busca `users.firebase_uid`.
5. Si no existe, crea el usuario.
6. Las operaciones utilizan `users.id`.

El `google_id` debe obtenerse de información verificada del proveedor; nunca de un valor arbitrario enviado por el cliente.

## 9. Integridad y transacciones

- Claves foráneas obligatorias.
- Restricciones únicas para favoritos y ratings.
- Transacciones para reordenar playlists.
- Paginación en comentarios e historial.
- Eliminación controlada de datos personales.
- Fechas almacenadas en UTC.
- Validación de tamaños y tipos de datos.
- Migraciones versionadas con Prisma.

## 10. Eliminación de cuenta

La eliminación de cuenta debe coordinar:

1. Verificación de identidad.
2. Eliminación o anonimización de datos personales según la política.
3. Tratamiento de comentarios públicos.
4. Eliminación de datos relacionados en PostgreSQL.
5. Eliminación de la identidad de Firebase.

Se deben contemplar errores parciales y reintentos seguros.

## 11. PostgreSQL frente a NoSQL

Se selecciona PostgreSQL porque:

- Existen relaciones claras entre usuarios, canciones y playlists.
- Se requieren claves foráneas.
- Son importantes las restricciones únicas.
- Las estadísticas utilizan agregaciones SQL.
- Se necesita consistencia transaccional.

MongoDB no es necesario en la primera versión.

La caché de metadatos puede usar memoria o SQLite sin convertir la base principal a NoSQL.

## 12. Datos sensibles y seguridad

- No almacenar contraseñas de Google.
- No almacenar Firebase ID tokens en PostgreSQL.
- No guardar credenciales administrativas en tablas.
- No incluir cadenas de conexión en Git.
- Usar TLS en las conexiones remotas.
- Limitar los permisos del usuario de base de datos.
- Documentar backups y restauración.
- Probar aislamiento entre dos cuentas diferentes.

## 13. Migraciones

Prisma será la fuente principal del esquema relacional.

Comandos previstos:

```bash
npx prisma generate
npx prisma migrate dev --name init
npx prisma migrate deploy
```

`migrate dev` se utiliza en desarrollo.

`migrate deploy` se utiliza para aplicar migraciones existentes en entornos desplegados.

No ejecutar migraciones destructivas sin respaldo y revisión.

## 14. Implementación inicial Sprint 03

La tabla users se preparó en el esquema PostgreSQL dedicado `mysic` mediante
Prisma multi-schema. Este esquema no debe exponerse en la Data API de Supabase;
Flutter consulta únicamente Express. El cliente se genera en el backend y no se
versiona.

## 15. Implementación Sprint 07

Las migraciones versionadas crean `tracks`, `playlists` y `playlist_tracks` en el
esquema `mysic`. Se aplicaron en Supabase el 6 de noviembre de 2026. Las tablas
mantienen RLS habilitado y no exponen políticas a roles de Data API; Flutter accede
exclusivamente mediante Express.

La restricción `(playlist_id, position)` evita órdenes ambiguos. Añadir, retirar y
reordenar ocurrencias usa transacciones serializables, y el borrado de una playlist
elimina sus ocurrencias en cascada sin borrar el catálogo normalizado.

## Implementación de historial — Sprint 10

ListeningHistory implementa el modelo previsto con UUID de sesión único,
CHECK de listened_ms entre 0 y 86400000, RLS y permisos públicos revocados.
Las actualizaciones atómicas conservan máximo tiempo acumulado y completitud.
La migración versionada requiere validación PostgreSQL antes del despliegue.

## Importación de YouTube Music — Sprint 14

La migración `20261118000000_youtube_music_imports` crea `mysic.music_imports`.
Cada borrador tiene UUID de solicitud, FK a `users.id`, hash del contenido,
nombre, lista JSON de identificadores y resoluciones, y caducidad de 24 horas.
Las consultas y preparaciones purgan globalmente los borradores caducados.
Las operaciones rechazan un borrador vencido incluso antes de su purga física.

La confirmación bloquea la fila, crea una playlist PRIVATE y sus posiciones
en una única transacción. Se reutiliza el catálogo canónico por
`(source, source_id)`. Las repeticiones de canciones conservan sus posiciones.
Se elimina el JSON temporal y se conserva un comprobante con fecha, conteos y
FK opcional a la playlist. Este comprobante mantiene la idempotencia tras un
reinicio. Al eliminar la playlist, la FK queda NULL y el mismo UUID de
importación continúa confirmado. Al eliminar el usuario, sus borradores y
comprobantes se eliminan en cascada.

RLS está habilitado y se revocan permisos a PUBLIC, anon y authenticated cuando
existen. Express comprueba la propiedad mediante Firebase y el UUID interno.
La migración se validó en PostgreSQL temporal y se aplicó en Supabase el
18 de noviembre de 2026 durante el despliegue de importaciones. Prisma confirmó
las ocho migraciones al día después del despliegue.

## Vinculación oficial de YouTube

La migración `20261118010000_youtube_oauth` añade tres tablas privadas con RLS. El intento y el vínculo se asocian a `users.id`. La tarea de revocación conserva su propio identificador de propietario y sobre cifrado, sin FK que pueda borrarla durante un reintento. El alcance de estas tablas es exclusivamente YouTube. La biblioteca sigue consultándose al proveedor.

El contrato, ciclo de vida de las credenciales y requisitos de mantenimiento se describen en [Vinculación OAuth de YouTube](youtube-oauth.md).

## Actividad musical del canal en Mysic

La migración `20261120010000_channel_music_listens` guarda las escuchas de Mysic en `mysic.channel_music_listens`. La clave combina el UUID interno del usuario, la generación del vínculo y el UUID del evento para que un reintento conserve una única escucha. La base guarda el ID de la grabación, el tiempo escuchado y la fecha del servidor. La API limita el historial a las últimas 600 escuchas por vínculo. El borrado se propaga al desvincular la cuenta. El reemplazo de canal elimina los eventos de la generación anterior. Al renovar el consentimiento del mismo titular y canal, la transacción mueve las escuchas a la nueva generación y conserva el identificador estable de su biblioteca en el dispositivo.

La conexión guarda la preferencia de pausa y una versión de la actividad. Un cambio de preferencia o un borrado invalida las escrituras pendientes de versiones anteriores y los cursores de actividad. Express verifica la identidad de Firebase y la generación del canal antes de exponer datos. RLS y la revocación de privilegios de los roles públicos protegen la tabla.
