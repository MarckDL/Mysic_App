# Sprint 14 — Importación desde YouTube Music

**Archivo histórico.** El APK 4028 retiró esta función y sus rutas de escritura. Las playlists creadas anteriormente conservan su propietario y contenido.


## Estado

Implementación adelantada el 18 de noviembre de 2026 por solicitud del propietario.
Se mantiene el orden del roadmap con Estadísticas y Optimización antes de este
sprint. Calidad pasa al Sprint 15 y Entrega al Sprint 16.

Pendientes de aceptación final una exportación real de Google Takeout, la prueba
Android con dos cuentas Google. El backend y la migración están desplegados y
0.11.1 está instalada en el teléfono de pruebas. La etiqueta de cierre prevista es `sprint-14-v0.14.0` después de esas comprobaciones.

## Uso

1. Abrir Biblioteca o Cuenta y elegir Importar de YouTube Music.
2. Abrir Google Takeout, desmarcar los otros productos y elegir playlists y
   biblioteca de YouTube y YouTube Music. Elegir CSV y ZIP para la exportación.
   Seleccionar el ZIP descargado o uno de sus CSV.
3. Seleccionar las listas y pulsar Revisar canciones seleccionadas. Las listas de
   más de 500 pistas se presentan como partes numeradas. Las canciones de
   biblioteca se agrupan en Guardadas de YouTube Music.
4. Consultar las canciones reconocidas, no disponibles, con fallo temporal y
   pendientes. Reintentar los fallos temporales cuando se recupere la red.
5. Pulsar Guardar copia privada para confirmar las listas seleccionadas que ya
   fueron revisadas y contienen pistas reconocidas. Las pistas ausentes o con
   fallo temporal se omiten al confirmar. Cada resultado permite abrir la playlist.

Los borradores preparados se recuperan al volver a esta pantalla durante 24 horas.
Se permiten 20 borradores activos por cuenta. En una exportación mayor se pueden
guardar las listas revisadas o descartar los borradores que se quieran omitir,
y continuar con las siguientes. Cada nueva selección
de archivo crea nuevas copias. Se conserva el orden y las repeticiones de canciones.

## Interfaces y persistencia

Todas las rutas parten de `/api/v1/imports/youtube-music`, exigen un Firebase ID
token de Google y responden con `Cache-Control: no-store`.

| Método y ruta | Entrada | Resultado |
| --- | --- | --- |
| POST / | UUID id, name y sourceIds de 1 a 500 | Preparar o recuperar el mismo borrador |
| GET / | Sin cuerpo ni parámetros | Hasta 20 borradores activos propios |
| GET /:id | UUID | Estado privado del borrador o comprobante |
| POST /:id/resolve | indices, de 1 a 2 posiciones distintas | Resolver pendientes o reintentar fallos |
| POST /:id/confirm | Objeto vacío | Guardar una playlist privada una sola vez |
| DELETE /:id | Sin cuerpo | Descartar un borrador propio pendiente |

El estado contiene id, name, expiresAt, confirmed, playlistId, savedCount,
skippedCount e items. Cada item tiene sourceId, status y track cuando está
reconocido. Los estados son pending, ready, unavailable y retry. La respuesta
omite el UUID del propietario y el hash interno.

Se devuelve 400 para entradas inválidas, 401 para tokens inválidos, 403 para
identidades ajenas a Google, 404 para propiedad ajena o caducidad, 409 para
contenido distinto con el mismo UUID, listas pendientes o listas sin pistas
reconocidas, 429 para límites y 503 para fallos de persistencia. Un error temporal
del catálogo se registra como retry y conserva las pistas ya reconocidas.

La tabla music_imports mantiene UUID de solicitud, propietario, hash del contenido,
borrador y comprobante de confirmación. El mismo UUID y contenido recuperan el
resultado existente. El mismo UUID con contenido diferente devuelve conflicto.
La fila se bloquea para fusionar lotes y confirmar. La transacción crea la
playlist, reutiliza o inserta tracks y guarda sus posiciones con operaciones en
lote. La inserción de catálogo reutiliza los metadatos canónicos existentes.
Un fallo revierte la creación completa. La confirmación elimina el JSON temporal.

Las consultas y preparaciones purgan los borradores vencidos. La ausencia de
tráfico puede retrasar la purga física, aunque el acceso vence a las 24 horas.
Los comprobantes persisten para impedir que una respuesta perdida o la eliminación
posterior de la playlist permita recrearla con el mismo UUID.

## Formatos y límites

- CSV UTF-8 con BOM opcional, comillas y saltos de línea. Se reconocen Video ID,
  Video Id y Song URL, y metadatos de playlist anteriores a la tabla de pistas.
  Los nombres de columnas opcionales de biblioteca permiten reconocer esa colección.
- Dentro del ZIP se leen CSV bajo playlists y archivos music-library-songs.
  El nombre de un CSV de playlist se utiliza cuando falta el título interno.
- Hasta 25 MiB por archivo seleccionado, 8 MiB por CSV, 32 MiB de CSV seleccionados
  dentro del ZIP, 2 000 entradas del ZIP y 50 000 pistas válidas por selección.
  Se rechazan enlaces simbólicos y archivos dañados. El ZIP se inspecciona antes
  de descomprimir sus CSV y se procesa en memoria.
- Dos pistas por lote, dos lotes simultáneos por proceso y 180 solicitudes por
  minuto y cuenta en las rutas de importación. El catálogo conserva sus límites,
  caché y caducidades existentes.

La versión actual de YoutubeProvider puede clasificar como error temporal una
pista eliminada o privada cuando el proveedor rechaza su consulta. La interfaz
permite reintentar o confirmar omitiéndola. La disponibilidad de metadatos y la
reproducción se verifican por separado.

## Verificación y aceptación

La batería específica cubre CSV antiguos y actuales, ZIP, biblioteca por URL,
BOM, orden y repetidos, división de 501 pistas, archivos inválidos y límites.
Las pruebas del controlador simulan respuestas perdidas y salida durante una
revisión. Las pruebas de pantalla cubren el flujo hasta abrir la playlist en
ambos temas y texto al 200 %.

Las pruebas con PostgreSQL cubren propiedad ajena en las rutas, caducidad, RLS,
reinicio del cliente, límite y descarte de borradores, fusiones simultáneas,
confirmación concurrente e idempotente,
eliminación posterior de la playlist, rollback y 500 posiciones. Confirman que
favoritos e historial se mantienen sin eventos creados por la importación.

Resultados automatizados de esta implementación:

- 203 pruebas backend correctas, incluyendo PostgreSQL temporal y las ocho migraciones.
- 114 pruebas Flutter y cinco pruebas Python correctas.
- Análisis estático, tipos, formato y compilación backend correctos.
- APK de depuración Android compilado. Las pruebas de pantalla cubren ambos temas
  y texto al 200 %. La integración del selector nativo con una exportación real
  forma parte de la aceptación Android pendiente.
- Una consulta puntual de tres IDs públicos reconoció las tres pistas en 760 ms
  totales desde este equipo. Esta muestra acredita conectividad del catálogo
  y requiere ampliar la medición a una biblioteca real.

Las muestras de prueba son sintéticas según los formatos documentados.
La cobertura y duración de resolución de una biblioteca real quedan pendientes
de medición. Para aceptar en campo:

1. Importar una exportación real y contrastar nombres, orden, repeticiones y conteos.
2. Pausar o interrumpir la red, reabrir y recuperar el borrador con la misma cuenta.
3. Confirmar, reiniciar la app y abrir las playlists persistidas.
4. Cambiar a una segunda cuenta y comprobar su biblioteca y borradores privados.
5. Reproducir una pista compatible y comprobar que la escucha se registra mediante
   el mecanismo normal del reproductor.

El backend público ya incluye la migración versionada en Supabase. Registrar los resultados de campo,
revisar cambios y secretos y realizar el cierre con commit, push y etiqueta
después de verificar todos los criterios.

## Publicación de prueba — 18 de noviembre de 2026

El commit `3d285eb` se publicó en main. GitHub Actions completó correctamente los
jobs backend y mobile. La copia aislada de los cambios publicados pasó 203
pruebas backend con PostgreSQL y 92 Flutter. La versión de trabajo completa
también pasó las 114 pruebas Flutter registradas anteriormente.

Render desplegó automáticamente el commit en mysic-api-k03u, con estado live
en `dep-dbukkeijnfac73bmdf2g`. Los logs confirman la aplicación de la migración
de importaciones y Prisma confirmó las ocho migraciones al día. El endpoint de
salud respondió 200 y las rutas de importación respondieron 401 tanto sin token
como con un token inválido.

Se compiló el APK ARM64 release con la configuración Firebase existente y
`https://mysic-api-k03u.onrender.com`. Android confirmó una actualización sobre
la instalación existente, versión 0.11.1 y versionCode 4015. La sesión Google
existente abrió Inicio. El APK de pruebas incluye las mejoras locales del
reproductor y letras que están en curso en el directorio de trabajo.
La comprobación visual terminó cuando el teléfono pasó a estar en uso.

El número base de compilación es 2015. El APK dividido ARM64 añade 2000 y genera
versionCode 4015, superior al 4014 que estaba instalado.

[CI del código publicado](https://github.com/MarckDL/Mysic_App/actions/runs/44253332218)
