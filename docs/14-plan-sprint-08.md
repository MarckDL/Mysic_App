# Sprint 08 — Favoritos y calificaciones

## 1. Propósito

Implementar RF-032 a RF-039 sobre la identidad multiusuario, el catálogo normalizado
y PostgreSQL. Cada usuario puede mantener su biblioteca de favoritos y una única
calificación activa de 1 a 5 por canción. Los promedios agregados se comparten solo
entre usuarios autenticados.

Versión objetivo: `sprint-08-v0.8.0`.

## 2. Alcance y decisiones

- Favoritos privados, persistentes y sin duplicados por `(user_id, track_id)`.
- Una calificación activa por usuario/canción; se puede modificar, no eliminar.
- Promedio global con cantidad de votos; sin votos se devuelve promedio nulo y cero.
- Biblioteca ordenada desde el favorito más reciente.
- Controles de corazón y estrellas en el detalle de canción.
- Pantalla `Mis favoritos`; no se agregan controles a resultados de búsqueda.
- Flutter solo envía el ID normalizado. El backend obtiene metadatos mediante
  `CatalogService` y no persiste URLs efímeras de reproducción.

Comentarios, historial, estadísticas y optimizaciones de reproducción permanecen
fuera del Sprint.

## 3. Datos y seguridad

La migración `20261112180000_create_favorites_ratings` crea:

- `favorites`, con PK compuesta, fecha, índices de listado y búsqueda, y FK con
  cascada desde usuario.
- `ratings`, con UUID, unicidad por usuario/canción, `SMALLINT`, `CHECK 1–5`, fechas
  e índice para agregados por canción.
- RLS habilitado y permisos públicos revocados en ambas tablas. Flutter no accede
  a PostgreSQL ni a la Data API.

Todas las operaciones resuelven `users.id` desde el Firebase UID verificado. No se
aceptan selectores de propietario desde el cliente. Las consultas privadas siempre
incluyen el UUID interno autenticado.

## 4. Contrato HTTP final

Todos los endpoints requieren Google/Firebase válido y usan `Cache-Control: no-store`.

| Método y ruta | Resultado |
|---|---|
| `GET /api/v1/favorites` | `{ items }` recientes del usuario |
| `PUT /api/v1/favorites/:catalogTrackId` | Alta idempotente y `{ isFavorite: true }` |
| `DELETE /api/v1/favorites/:catalogTrackId` | Baja propia idempotente y `{ isFavorite: false }` |
| `PUT /api/v1/ratings/:catalogTrackId` | Upsert de `{ score: 1..5 }` y agregado actualizado |
| `GET /api/v1/tracks/:catalogTrackId/interactions` | Favorito propio, rating propio, promedio y votos |

La lectura combinada responde:

```json
{
  "isFavorite": true,
  "myRating": 4,
  "ratingAverage": 4.5,
  "ratingCount": 2
}
```

Los errores públicos son `INVALID_REQUEST`, `USER_NOT_SYNCED`, `TRACK_NOT_FOUND`,
`CATALOG_TIMEOUT`, `CATALOG_UNAVAILABLE` y `DATABASE_UNAVAILABLE`.

## 5. Aplicación Flutter

- `features/favorites` contiene modelo, repositorio, cliente, estado Riverpod y
  pantalla de biblioteca.
- `features/ratings` contiene el agregado de interacciones, repositorio, estado y
  panel de corazón/estrellas.
- Las mutaciones invalidan la biblioteca y el detalle afectados.
- Los providers son `autoDispose`; el navegador autenticado se desmonta al cerrar
  o cambiar de cuenta.
- La versión de la aplicación es `0.8.0+8`.

## 6. Matriz mínima de aceptación

| Caso | Resultado esperado |
|---|---|
| Sin token, token inválido o proveedor no Google | `401` o `403` |
| Usuario no sincronizado | `404 USER_NOT_SYNCED` |
| ID o score inválido, campo desconocido | `400 INVALID_REQUEST` |
| A agrega dos veces la misma pista | Una fila en favoritos |
| B consulta o retira la pista favorita de A | No ve ni modifica la preferencia de A |
| A califica dos veces | Una fila con el score más reciente |
| A=4 y B=5 | Promedio `4.5`, cantidad `2`; cada rating personal aislado |
| C consulta una canción sin votos | Promedio nulo y cantidad cero |
| Reinstalación/cambio de dispositivo | Preferencias recuperadas desde PostgreSQL |
| Cambio de cuenta | No queda estado Riverpod de la cuenta anterior |

## 7. Evidencia local — 12 de noviembre de 2026

Completado:

- Prisma valida y genera el cliente con los dos modelos nuevos.
- Backend: lint, tipos y build correctos; 151 pruebas correctas.
- Flutter: formato, análisis estático y 57 pruebas correctas.
- APK release ARM64 construido contra el backend HTTPS: 22.517.278 bytes
  (22,5 MB), dentro del límite de 24 MB.
- Los tests cubren contrato HTTP, idempotencia, aislamiento simulado, modificación
  de rating, promedio/cantidad, clientes autenticados y widgets.
- Se añadieron tres casos PostgreSQL reales para concurrencia, aislamiento,
  restricciones, cascadas y RLS.

Pendiente antes del cierre:

- Las 9 pruebas PostgreSQL (incluidas 3 nuevas) requieren `TEST_DATABASE_URL` hacia
  una base desechable. Docker está instalado pero su servicio local no está activo;
  no se usó Supabase productivo para pruebas destructivas.
- Aplicar la migración revisada a Supabase mediante el despliegue autorizado.
- Validar HTTPS y APK físico con dos cuentas, sin `adb reverse`.
- Confirmar GitHub Actions, publicar `main` y crear `sprint-08-v0.8.0` después de
  recibir autorización explícita.

El Sprint no se considera cerrado mientras estas verificaciones sigan pendientes.
