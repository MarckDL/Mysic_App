# Biblioteca de YouTube · Fase 2

La biblioteca muestra las playlists propias que YouTube devuelve para el canal vinculado, incluidas las privadas. Se consulta por demanda con la sesión Firebase de Mysic y el permiso de lectura del canal. El teléfono recibe metadatos y enlaces oficiales. El backend conserva las credenciales. Las pruebas con dos cuentas personales se hicieron en OAuth Playground. La aceptación del callback de Mysic con Google real y la prueba del cliente móvil siguen pendientes.

## Contrato HTTP

Ambas consultas requieren un perfil sincronizado, vínculo activo y `YOUTUBE_LINK_ENABLED=true`. El servidor responde con `Cache-Control: no-store`.

| Método y ruta | Contenido |
| --- | --- |
| `GET /api/v1/integrations/youtube/playlists` | Devuelve `items`, `nextCursor` y `fetchedAt` en UTC. Cada lista incluye ID, título, visibilidad, número de elementos y miniatura cuando estén disponibles. |
| `GET /api/v1/integrations/youtube/playlists/{id}/items` | Comprueba el propietario con YouTube en cada página. Devuelve las entradas en el orden recibido, con su posición original, y añade `unavailableCount` para esa página. |

Enviar `limit` entre 1 y 50 para elegir el tamaño inicial. El valor predeterminado es 50. Para continuar, enviar el `cursor` recibido y omitir `limit` o conservar el mismo valor. `nextCursor: null` indica el final. Una página vacía con cursor permite continuar. Para actualizar la vista, volver a solicitar la primera página.

El identificador de cada fila es `playlistItemId`. Si dos filas representan el mismo video mantienen su posición y su identidad. Cada fila puede incluir `videoId`, `title`, `channelTitle`, `durationSeconds` y `thumbnailUrl`. El canal identifica a quien publicó el video. Si Google omite sus metadatos, la entrada conserva la posición y el título que suministre la playlist.

| Disponibilidad | Presentación |
| --- | --- |
| `available` | Google devolvió el video procesado con estado de privacidad y sin condición geográfica pendiente. `openUrl` abre su página en YouTube. YouTube decide la reproducción para el espectador. |
| `unavailable` | Falta el video en la respuesta, falta un ID válido o Google indica un estado incompatible. La fila se conserva con `openUrl: null`. |
| `unknown` | Metadatos insuficientes, procesamiento en curso o una restricción geográfica cuyo resultado depende del espectador. La fila se conserva con `openUrl: null`. |

## Paginación y errores

El cursor se autentica y cifra con la clave versionada del backend. Queda ligado al usuario, canal, generación del vínculo y operación, incluida la playlist. El piloto de una instancia conserva en memoria hasta 1024 referencias de páginas para eliminar repeticiones de filas entre páginas y permitir reintentos sobre el mismo cursor. Cada recorrido vence a los 15 minutos. Un reinicio o la expulsión de una referencia requiere empezar de nuevo. El servidor vuelve a comprobar la generación antes de entregar cada respuesta. Las playlists remotas se consultan directamente en YouTube.

| Respuesta | Acción del cliente |
| --- | --- |
| 401 de Mysic | Renovar la sesión Firebase. |
| 403 `MISSING_SCOPE` / `YOUTUBE_FORBIDDEN` | Solicitar consentimiento para el alcance requerido, o informar la restricción de ese recurso, según el código. |
| 404 `PLAYLIST_NOT_FOUND` | Volver al listado. Se usa también para una lista ajena. |
| 409 `INVALID_CURSOR` / `CURSOR_EXPIRED` | Descartar las páginas de la vista y volver a empezar. |
| 409 `REAUTHORIZE_YOUTUBE` / `YOUTUBE_LINK_CHANGED` | Consultar el estado y ofrecer reconexión o recargar para el canal actual. |
| 429 `YOUTUBE_QUOTA` / `TOO_MANY_REQUESTS` | Conservar lo ya mostrado y respetar `Retry-After` cuando esté presente. |
| 503 | El proveedor puede estar temporalmente indisponible. El código `LINK_DISABLED` indica que el piloto está apagado. |

Una página de listas implica una consulta a Google. Una página de elementos usa dos consultas para comprobar propiedad y leer filas, y hasta una más para enriquecer un lote de hasta 50 identificadores únicos. La renovación OAuth se gestiona por separado. Cada lectura permite una renovación ante un 401 del proveedor y hasta dos reintentos temporales compartidos entre sus operaciones. El presupuesto de lectura es de 15 segundos, con cancelación del transporte al desconectarse el cliente. No se reintentan automáticamente los errores de cuota. El límite HTTP del piloto es de 30 solicitudes de biblioteca por minuto por usuario e instancia.

Métodos del proveedor: [playlists.list](https://developers.google.com/youtube/v3/docs/playlists/list), [playlistItems.list](https://developers.google.com/youtube/v3/docs/playlistItems/list) y [videos.list](https://developers.google.com/youtube/v3/docs/videos/list). El contrato de vinculación se documenta en [OAuth](youtube-oauth.md).
