# Sprint 04 — Plan de catálogo experimental

Fecha: 25 de octubre de 2026.
Estado: validación local, manual y CI completadas; etiqueta pendiente.
Historia: US-004. Versión prevista: sprint-04-v0.4.0.

## Objetivo

Buscar canciones por texto o artista, mostrar resultados normalizados en Flutter
y consultar su detalle a través de Express. Mantener autenticación Google y
separación entre dominio, aplicación, presentación e infraestructura.

Fuentes: Sprint 04 de docs/04-sprints-roadmap.md, catálogo de docs/03-requisitos.md,
contrato MusicProvider y caché de docs/01-arquitectura.md, modelo de tracks de
docs/02-base-de-datos.md.

Requisitos: RF-009, RF-010, RF-011, RF-013, RF-014, RF-015 y RF-016.
RF-012 (exploración de artistas) solo se habilita mostrando el nombre disponible;
no se considera implementado un perfil de artista completo en este sprint.

## Alcance y decisiones propuestas

- youtubei.js exclusivamente en backend; Flutter recibe DTO propios de Mysic.
- Ambas rutas del catálogo requieren requireAuth. Es la política propuesta para
  resolver la decisión abierta de búsqueda pública/privada de arquitectura.
- Primer incremento limitado a una página de hasta 20 resultados; no se promete
  catálogo exhaustivo, total de coincidencias ni paginación sin implementarlos.
- Se conservan source y sourceId separados. Propuesta de id público: youtube:<sourceId>,
  validado y codificado en URL desde Flutter. No es un UUID PostgreSQL ni un ID de usuario.
- El detalle resuelve este identificador sin depender de haber buscado antes.
- No crear tabla tracks en este sprint: búsqueda y detalle funcionan con proveedor
  y caché temporal. Cuando biblioteca/playlists necesiten referencias persistentes,
  se añadirá tracks con UUID y UNIQUE(source, source_id) mediante migración.
  La API mantendrá explícita la diferencia entre identidad externa y UUID persistido.
- El contrato conceptual MusicProvider ya incluye resolvePlayback: se conserva,
  devolviendo unavailable sin resolver audio. No se expone endpoint de reproducción
  ni se añaden controles reproducibles antes del Sprint 05.
- Registrar estas decisiones en arquitectura/modelo al implementar; este documento
  propone el alcance, no afirma cambios de contrato ya desplegados.

## 1. Validar proveedor y dependencias

1. Consultar documentación oficial y API de una versión estable de youtubei.js;
   verificar compatibilidad con Node, ESM y TypeScript actuales.
2. Instalar solo en backend y registrar lockfile. Elegir caché LRU compatible.
3. Probar metadatos de búsqueda y detalle desde el equipo, sin cookies de usuario
   ni credenciales Google/Firebase entregadas al proveedor musical.
4. Verificar timeout, inicialización de sesión y comportamiento ante restricciones.
5. Si el proveedor exige autenticación o bloquea el entorno, detener esa integración
   y documentar el bloqueo. Los dobles de pruebas no cuentan como viabilidad real.

Punto de control: búsqueda y detalle de metadatos deben funcionar antes de ampliar UI.

## 2. Contratos y adaptador de dominio

- Definir Track normalizado con id público, source, sourceId, title, artistName,
  durationSeconds nullable y thumbnailUrl nullable.
- Crear MusicProvider y YoutubeProvider; ningún tipo de youtubei.js sale del adaptador.
- Normalizar únicamente elementos musicales/pistas compatibles con el contrato.
  No presentar canales, playlists, anuncios o álbumes como canciones.
- Definir cómo se identifican resultados musicales según API real elegida. Si se
  usa búsqueda de videos, no asumir que todo video es una canción: documentar su
  carácter experimental y evitar afirmar una clasificación no respaldada.
- Manejar títulos incompletos, artistas ausentes, duraciones desconocidas/directos
  y miniaturas faltantes. No convertir ausencia de duración en cero ficticio.
- Eliminar duplicados por (source, sourceId), conservar orden de relevancia.
- Miniaturas HTTPS y campos de texto acotados; no devolver URLs de audio, datos
  internos, cookies, tokens o trazas del SDK.
- Separar no encontrado de proveedor indisponible; restringido no implica inexistente.

## 3. Servicios y API

| Ruta | Propósito | Respuesta propuesta |
|---|---|---|
| GET /api/v1/search?q=texto | Búsqueda validada y acotada | 200 con { items: Track[] } |
| GET /api/v1/tracks/:id | Detalle por id externo compuesto | 200 con Track |

- Validar entrada en el límite HTTP con Zod o una alternativa coherente: q es una
  cadena, trim, entre 2 y 120 caracteres; rechazar arrays/objetos y parámetros ajenos.
- Identificador de detalle: solo fuente youtube soportada y formato sourceId
  validado contra el proveedor. No aceptar URL arbitraria para fetch remoto.
- Servicio de aplicación coordina caché/proveedor, sin lógica de negocio en rutas.
- Mantener el JSON de error actual de Mysic y respuestas privadas no-store.
- 400: entrada inválida. 401/403: autenticación. 404: pista realmente inexistente.
  429: límite propio. 503: proveedor indisponible/restringido. 504: timeout.
- Evitar convertir un error externo en una lista vacía de éxito.
- Timeout total propuesto: 10 segundos. Cancelar trabajo externo cuando el SDK
  lo soporte; no asumir que Promise.race cancela una solicitud subyacente.
- No aplicar reintentos ilimitados ni mantener sesiones Firebase en el proveedor.

## 4. Caché y límites de consumo

- LRU acotada en memoria: propuesta inicial 100 búsquedas y 500 detalles.
- TTL de arquitectura: búsqueda 10 minutos; detalle de pista 1 hora.
- Clave: fuente + consulta normalizada + opciones que alteren resultados.
  No incluir UID/token en claves de metadatos públicos compartidos.
- Aplicar autenticación antes de servir incluso un cache hit.
- Coalescer solicitudes concurrentes de la misma clave; limpiar promesas fallidas.
- Cachear resultados vacíos válidos; no cachear 401/403 ni fallos operativos como
  éxitos. Si se usa la ventana de errores de 30 segundos de arquitectura, emplearla
  como enfriamiento explícito del proveedor, distinguiendo errores de datos válidos.
- Rate limit por UID verificado: propuesta 30 solicitudes/minuto por cuenta para
  el catálogo completo, incluidos cache hits. Responder 429 y Retry-After.
- Cache y limitador de un solo proceso: suficiente inicialmente; documentar que
  los límites no son globales si en el futuro se despliegan múltiples instancias.
- No almacenar consultas como historial personal ni añadir persistencia implícita.

## 5. Flutter

- Añadir feature search con presentación, estado Riverpod, modelos y repositorio Dio.
- Extraer/reutilizar cliente HTTP autenticado sin duplicar gestión de tokens.
  Los GET pueden renovar una vez ante 401; 503/504 no deben cerrar sesión.
- Incorporar go_router cuando se introduzcan búsqueda/detalle; conservar el gate
  que exige autenticación y perfil sincronizado antes de acceder a esas vistas.
- Pantalla con buscador y estados inicial, carga, resultados, vacío, error/reintento.
- Debounce propuesto de 400 ms y longitud mínima coherente con backend.
- Cancelar solicitud anterior y descartar respuestas tardías mediante identificador
  de solicitud/consulta. Limpiar estado al cambiar o cerrar cuenta.
- Cada resultado muestra título, artista, miniatura con fallback y duración si existe.
- Abrir detalle con la misma identidad de pista; manejar inexistencia/restricción.
- No mostrar botones de reproducción operativos en este sprint.
- Nombre de artista informativo; navegación a perfil completo queda pendiente.

## 6. Pruebas

### Backend determinista

- Normalización con fixtures mínimos representativos: pista completa, campos
  ausentes, elemento no compatible, duplicados y respuesta externa malformada.
- Rutas: validación, 401/403, resultados vacíos, detalle válido/404, restricción,
  503/504 y ocultación de datos internos.
- LRU: TTL con reloj simulado, expulsión por capacidad, claves consistentes,
  concurrencia y recuperación tras fallo. Un usuario no evita auth mediante caché.
- Rate limit: 429/Retry-After y separación entre UID.
- No red externa en suites obligatorias de CI. Dobles/fixtures prueban el contrato;
  una prueba manual separada demuestra disponibilidad real del proveedor.
- Conservar pruebas de autenticación, usuarios y PostgreSQL del Sprint 03.

### Flutter

- Estados de búsqueda/detalle, fallback de imágenes, vacíos y reintento.
- Debounce y respuesta fuera de orden; logout/cambio de cuenta durante búsqueda.
- GET con renovación de token acotada; fallo de proveedor mantiene sesión válida.
- Navegación y protección de rutas.

### Prueba real con el usuario

- Buscar por título y por artista; abrir detalle y comprobar consistencia.
- Verificar búsquedas repetidas y registros de cache hit sin tokens ni consultas
  personales completas en logs.
- Probar sin conexión o con fallo externo controlado; no simular éxito.
- Repetir con las dos cuentas sin mezclar perfil/estado.
- Compilar APK y probar en el emulador.

## 7. Documentación y cierre

- Actualizar arquitectura con política de auth, identidad de pista, DTO y errores.
- Registrar versión y limitaciones del proveedor, TTL, capacidad y límites de uso.
- Documentar ausencia de persistencia tracks y reproducción fuera de alcance.
- Revisar dependencias, lockfiles y archivos publicables; excluir secretos.
- Ejecutar lint, tipos, formato, pruebas y build backend; formato/análisis/pruebas
  Flutter, pruebas PostgreSQL existentes y compilación APK en GitHub Actions.
- Publicar commit, verificar CI y luego etiqueta anotada sprint-04-v0.4.0 sobre el
  commit probado. No etiquetar como completo si falla la prueba real del proveedor.

## Criterios de aceptación

1. Usuario autenticado busca por texto y ve resultados normalizados en Flutter.
2. Cada pista permite abrir un detalle coherente con su source/sourceId.
3. Vacíos, errores, restricciones y timeout tienen estados claros y controlados.
4. Caché limitada con TTL y rate limit probados; auth no se omite en cache hits.
5. Ningún módulo Flutter depende de youtubei.js ni recibe credenciales del proveedor.
6. No hay extracción/retransmisión de audio ni cambios a la autenticación existente.
7. Suites previas y nuevas correctas; prueba real y CI documentadas.
8. Publicación y etiqueta verificadas antes del cierre.

## Orden de ejecución y apoyo del usuario

1. Prueba técnica de metadatos del proveedor en backend.
2. Contrato normalizado, adaptador y pruebas.
3. API, LRU, límites y pruebas HTTP.
4. Flutter: búsqueda y detalle con navegación protegida.
5. Prueba real, revisión y CI.
6. Cierre versionado.

No se requiere otro proyecto Firebase ni otra base Supabase. Puede necesitarse la
terminal del usuario para descargar dependencias, comprobar acceso real al proveedor,
ejecutar Flutter y publicar Git si el entorno del agente mantiene restricciones.

## Avance inicial — 25 de octubre de 2026

- Revisada la documentación oficial y el paquete estable youtubei.js 18.3.0.
- El intento pnpm add en backend falló por almacén global de solo lectura. No se
  modificaron package.json ni lockfile para declarar dependencias no instaladas.
- Se instaló una copia aislada de youtubei.js 18.3.0 en scratch para inspección y
  prueba técnica; no sustituye la instalación pendiente en el proyecto backend.
- Prueba real: búsqueda Music con filtro song devolvió 20 canciones. Un segundo
  intento obtuvo detalle con el mismo sourceId. Tiempo total aproximado 12,5 s
  para sesión + búsqueda + detalle; un límite global inicial de 10 s se agotó.
  Cada petición debe tener cancelación y el servicio una política total explícita.
- El detalle indicó UNPLAYABLE. Esto no valida reproducción ni implica por sí solo
  ausencia de metadatos; no se descargó audio ni se intentó eludir restricciones.
- Creado MusicProvider y DTO Track con id externo compuesto; PlaybackResult
  mantiene el contrato conceptual sin implementar resolución de audio.
- Añadido normalizador con whitelist de miniaturas HTTPS del proveedor, filtro
  exclusivo song, deduplicación, máximo 20 y valores ausentes explícitos.
- Añadido catalog:check: prueba reproducible sin Firebase ni PostgreSQL, que usa
  búsqueda fija y verifica detalle normalizado. No registra respuestas completas,
  tokens, cookies ni URLs de audio. Inicialización sin caché de sesión ni player JS.
- Lint, tipos, formato y build correctos; 60 pruebas backend correctas, incluidas
  10 nuevas de normalización. Tres casos PostgreSQL omitidos localmente porque
  requieren TEST_DATABASE_URL desechable; no son fallos ni nueva validación remota.

Siguiente paso: instalar youtubei.js 18.3.0 en backend desde la terminal normal,
actualizando pnpm-lock.yaml, y ejecutar pnpm catalog:check. Después implementar
YoutubeProvider, API protegida, caché/rate limit y Flutter. No hay rutas de catálogo
ni cambios de UI publicados en este incremento. Sprint 04 no está cerrado.

Fuentes consultadas:
- https://ytjs.dev/guide/getting-started
- https://ytjs.dev/api/youtubei.js/namespaces/Clients/classes/Music
- https://ytjs.dev/api/youtubei.js/namespaces/YTMusic/classes/Search
- https://ytjs.dev/api/youtubei.js/namespaces/YTNodes/classes/MusicResponsiveListItem

## Incremento de API y Flutter

La instalación en el equipo quedó confirmada: youtubei.js 18.3.0 en backend y
lockfile actualizado. El usuario ejecutó catalog:check con búsqueda y detalle
normalizados correctos. La comprobación ahora reutiliza YoutubeProvider y
CatalogService, los mismos componentes de la API; también pasó desde el agente.

### Decisiones aplicadas

- GET /api/v1/search?q y GET /api/v1/tracks/:id requieren Firebase Google verificado,
  incluso al servir caché. No dependen de PostgreSQL ni aceptan IDs de propietario.
- q: cadena de 2–120 caracteres después de trim/colapsar espacios; máximo bruto
  1024, sin controles, arrays ni parámetros ajenos. ID youtube:<videoId de 11 chars>.
- Resultado de búsqueda: { items: Track[] }, máximo 20. Detalle devuelve Track.
- Respuestas no-store. Códigos 400/401/403/404/429/503/504 controlados.
  El adaptador no convierte restricciones o metadata incompleta en 404: cuando no
  puede confirmar inexistencia devuelve indisponibilidad. No confunde metadata
  válida con disponibilidad de audio ni expone streaming_data.
- LRU propia pequeña y probada, sin otra dependencia: 100 búsquedas/10 min,
  500 detalles/1 hora. No hay caché de fallos; no se implementa enfriamiento de 30 s.
- Coalescing por clave, copias de resultados cacheados, máximo 8 operaciones
  externas distintas simultáneas y timeout total de 10 s por operación.
- Timeout aborta fetch y una respuesta tardía no entra en caché. SDK se inicializa
  por operación con retrieve_player:false, sin cookies ni caché de sesión.
  La opción de versión instalada es fail_fast; se corrigió la discrepancia de docs.
- Limitador de proceso por UID: 30 solicitudes/minuto para catálogo, incluidos
  cache hits, máximo 10.000 ventanas retenidas; 429 con Retry-After.
- No hay migración ni tabla tracks en este incremento, solo metadatos temporales.

### Aplicación móvil

- Botón Buscar música desde el inicio verificado; búsqueda y detalle con go_router
  18.1.1. El navegador vive dentro de AuthGate y se elimina al cerrar/cambiar cuenta.
- go_router requiere Dart 3.12: se elevó el mínimo del proyecto a 3.12, compatible
  con el toolchain actual Flutter 3.47.8/Dart 3.13.7. Lockfile actualizado.
- El cambio de versión de lenguaje requiere nuevo formato Dart en archivos previos;
  se aplicó y verificó. No modifica el comportamiento de autenticación.
- Cliente Dio GET autenticado compartido para catálogo; configuración de seguridad
  común con el cliente de sesión. No sigue redirects ni acepta HTTP remoto.
- Renueva token una sola vez ante 401. 503/504/429 no cierran la sesión.
- Debounce 400 ms, cancelación y descarte de respuestas de consultas anteriores.
  Respuestas tardías de otra cuenta no se muestran.
- Estados inicial/carga/vacío/error, reintento, imágenes con fallback y duración
  opcional. Detalle muestra metadatos y reproducción aún no disponible, sin play.

### Verificación del incremento

- Backend: 85 pruebas correctas (incluyen 25 nuevas de servicio/rutas/adaptador),
  3 PostgreSQL omitidas localmente por falta de TEST_DATABASE_URL desechable.
- Lint, typecheck, build y formato backend correctos. git diff --check correcto.
- Prueba real con nuevo adaptador/servicio: 20 canciones y detalle confirmado.
- Dart analyze ejecutado directamente con SDK: sin problemas. Formato aplicado.
- Pruebas Flutter preparadas para cliente autenticado, errores, debounce,
  cancelación, navegación y eliminación de rutas al salir. Ejecución bloqueada
  en el agente por lockfile de caché del SDK en filesystem de solo lectura.
- Pendiente flutter test desde terminal normal, prueba UI real, APK y CI.
- No se ha hecho commit, push ni etiqueta del Sprint 04.

### Corrección de prueba de navegación

El usuario ejecutó pub get/análisis sin problemas: 20 tests correctos y uno falló.
El doble SearchFake mantenía detail() sin implementar y lanzaba UnimplementedError;
por ello el detalle mostraba estado de error. Se implementó el dato de prueba y se
agregó comprobación del ID solicitado y artista. Se conserva la expectativa de
metadatos y cierre de rutas tras logout. Dart analyze vuelve a pasar. Pendiente
repetir flutter test; no se declara validada aún toda la suite móvil.
La comprobación real catalog:check volvió a pasar en el equipo del usuario.

## Validación final local y aceptación manual

El usuario repitió flutter test tras la corrección: 21 pruebas correctas.
Después confirmó que las pruebas propuestas en el emulador funcionan: búsqueda
por título/artista, detalle, cambio rápido de consulta y uso con las dos cuentas.
Esta es evidencia manual comunicada por el usuario; no una observación directa
del agente ni una prueba de reproducción de audio.

Revisión final: lint, tipos, formato, 85 pruebas y build backend correctos;
los 3 casos PostgreSQL se ejecutarán en CI con la base desechable. Formato Dart
verificado: 28 archivos sin cambios; análisis Dart sin problemas. Revisión de diff
sin errores. Escaneo de archivos candidatos a Git sin patrones de claves privadas
o API keys Google. .env, Firebase cliente real y cliente Prisma generado ignorados.
El escaneo por patrones complementa la revisión y no garantiza detectar todo secreto.

Revisados autenticación antes de caché, límite por UID, cancelación/timeout,
invalidación al cambiar cuenta y contratos de proveedor: sin hallazgos bloqueantes.
CI existente cubre lockfiles, migraciones, pruebas de PostgreSQL y compilación APK.
Las pruebas deterministas no dependen de acceso a YouTube; catalog:check y la
aceptación manual aportan la comprobación externa separada.

Pendiente publicar el commit y verificar Quality, incluido APK debug, antes de
crear la etiqueta sprint-04-v0.4.0. No se ha publicado ni cerrado este Sprint aún.

## Validación remota final

Commit probado: `5e4f8667000cfdd7c43fcedd76b92b2dcb5e0990`.
Quality: https://github.com/MarckDL/Mysic_App/actions/runs/40196450276

Workflow completado con success. Backend: 88 pruebas correctas, incluidos los tres
casos PostgreSQL sin omisiones, migraciones, generación Prisma, lint, tipos, formato
y build. Mobile: formato, análisis, pruebas, conversor Firebase y APK debug correctos.
La disponibilidad externa del catálogo fue comprobada por separado mediante
catalog:check y pruebas manuales del usuario; CI usa dobles de proveedor.

Este resultado actualiza los pendientes históricos de CI de este documento.
Falta publicar este registro y la etiqueta anotada sprint-04-v0.4.0 sobre el commit
probado, y verificar la referencia remota antes de declarar cerrado el Sprint.
