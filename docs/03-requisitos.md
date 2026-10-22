
# Mysic — Especificación de requisitos

**Versión:** 1.0.0  
**Estado:** Línea base del proyecto  
**Metodología:** Scrum adaptado a proyecto académico

## 1. Propósito

Definir los requisitos funcionales y no funcionales de Mysic, una aplicación móvil multiusuario de exploración musical, reproducción, biblioteca personal y funcionalidades sociales.

## 2. Alcance

### Incluido

- Autenticación obligatoria con Google.
- Gestión de usuarios.
- Búsqueda y exploración musical.
- Integración experimental de catálogo mediante youtubei.js.
- Reproductor de audio con fuente compatible.
- Playlists y favoritos centralizados.
- Calificaciones y comentarios.
- Historial y estadísticas personales.
- Aislamiento multiusuario.
- Persistencia en PostgreSQL.
- APK privado para demostración.

### Excluido inicialmente

- Suscripciones y pagos.
- Publicación en tiendas.
- Descarga no autorizada de música.
- Almacenamiento masivo de MP3.
- Playlists colaborativas.
- Recomendaciones mediante IA.
- Letras sincronizadas.
- Monetización y publicidad.

## 3. Actores

| Actor | Descripción |
|---|---|
| Visitante | Persona sin sesión iniciada |
| Usuario autenticado | Persona identificada mediante Google |
| Moderador | Usuario con permisos administrativos |
| Firebase Auth | Proveedor de autenticación |
| Proveedor musical | Fuente externa de metadatos y reproducción permitida |

## 4. Requisitos funcionales

### Módulo de autenticación y usuarios

| ID | Requisito | Prioridad |
|---|---|---|
| RF-001 | Iniciar sesión con Google mediante Firebase Auth | Obligatoria |
| RF-002 | Verificar Firebase ID token en Express | Obligatoria |
| RF-003 | Crear perfil automáticamente en PostgreSQL | Obligatoria |
| RF-004 | Recuperar la sesión autenticada | Obligatoria |
| RF-005 | Cerrar sesión | Obligatoria |
| RF-006 | Consultar y actualizar datos editables del perfil | Obligatoria |
| RF-007 | Eliminar cuenta y datos asociados | Obligatoria |
| RF-008 | Impedir acceso a recursos privados de otros usuarios | Obligatoria |

### Módulo de catálogo

| ID | Requisito | Prioridad |
|---|---|---|
| RF-009 | Buscar canciones por texto | Obligatoria |
| RF-010 | Mostrar resultados con título, artista y miniatura | Obligatoria |
| RF-011 | Consultar detalle de una canción | Obligatoria |
| RF-012 | Explorar información disponible de artistas | Obligatoria |
| RF-013 | Integrar youtubei.js exclusivamente en backend | Obligatoria |
| RF-014 | Normalizar respuestas del proveedor | Obligatoria |
| RF-015 | Gestionar errores y falta de resultados | Obligatoria |
| RF-016 | Aplicar caché temporal de metadatos | Obligatoria |

### Módulo de reproducción

| ID | Requisito | Prioridad |
|---|---|---|
| RF-017 | Reproducir audio desde una fuente compatible y autorizada | Obligatoria |
| RF-018 | Pausar y reanudar reproducción | Obligatoria |
| RF-019 | Avanzar o retroceder dentro de una pista cuando sea compatible | Obligatoria |
| RF-020 | Mostrar información de pista actual | Obligatoria |
| RF-021 | Gestionar cola de reproducción | Obligatoria |
| RF-022 | Soportar controles multimedia en segundo plano | Obligatoria |
| RF-023 | Manejar interrupciones y errores de audio | Obligatoria |
| RF-024 | Mostrar indisponibilidad cuando no exista fuente reproducible | Obligatoria |

### Módulo de playlists

| ID | Requisito | Prioridad |
|---|---|---|
| RF-025 | Crear playlists asociadas al usuario | Obligatoria |
| RF-026 | Editar nombre y descripción | Obligatoria |
| RF-027 | Eliminar playlists propias | Obligatoria |
| RF-028 | Añadir y retirar canciones | Obligatoria |
| RF-029 | Reordenar canciones | Obligatoria |
| RF-030 | Consultar playlists desde distintos dispositivos | Obligatoria |
| RF-031 | Configurar privacidad de playlists | Obligatoria |

### Módulo de favoritos

| ID | Requisito | Prioridad |
|---|---|---|
| RF-032 | Agregar canciones a favoritos | Obligatoria |
| RF-033 | Quitar canciones de favoritos | Obligatoria |
| RF-034 | Consultar favoritos almacenados en PostgreSQL | Obligatoria |
| RF-035 | Evitar favoritos duplicados | Obligatoria |

### Módulo de calificaciones

| ID | Requisito | Prioridad |
|---|---|---|
| RF-036 | Calificar canciones de 1 a 5 estrellas | Obligatoria |
| RF-037 | Modificar la calificación propia | Obligatoria |
| RF-038 | Consultar promedio de calificaciones | Obligatoria |
| RF-039 | Mantener una calificación activa por usuario y canción | Obligatoria |

### Módulo de comentarios

| ID | Requisito | Prioridad |
|---|---|---|
| RF-040 | Publicar comentarios vinculados al usuario | Obligatoria |
| RF-041 | Consultar comentarios visibles | Obligatoria |
| RF-042 | Editar comentarios propios | Obligatoria |
| RF-043 | Eliminar comentarios propios | Obligatoria |
| RF-044 | Reportar comentarios | Obligatoria |
| RF-045 | Moderar comentarios reportados | Obligatoria |
| RF-046 | Paginar resultados y limitar contenido | Obligatoria |

### Módulo de historial

| ID | Requisito | Prioridad |
|---|---|---|
| RF-047 | Registrar sesiones de escucha válidas | Obligatoria |
| RF-048 | Guardar historial en PostgreSQL | Obligatoria |
| RF-049 | Consultar historial cronológico personal | Obligatoria |
| RF-050 | Evitar eventos duplicados | Obligatoria |

### Módulo de estadísticas

| ID | Requisito | Prioridad |
|---|---|---|
| RF-051 | Calcular tiempo de escucha | Obligatoria |
| RF-052 | Mostrar canciones más escuchadas | Obligatoria |
| RF-053 | Mostrar artistas más escuchados | Obligatoria |
| RF-054 | Filtrar estadísticas por período | Obligatoria |
| RF-055 | Aislar estadísticas por usuario | Obligatoria |

## 5. Requisitos no funcionales

Los valores siguientes son objetivos iniciales de ingeniería, no mediciones ya verificadas.

| ID | Requisito | Criterio |
|---|---|---|
| RNF-001 | Seguridad de transporte | HTTPS para servicios remotos |
| RNF-002 | Autenticación | Validación de Firebase ID tokens |
| RNF-003 | Autorización | Comprobación de propiedad en operaciones privadas |
| RNF-004 | Protección de secretos | Credenciales fuera del repositorio |
| RNF-005 | Rendimiento de API | p95 objetivo menor a 500 ms para operaciones internas, excluyendo proveedores externos |
| RNF-006 | Rendimiento de búsqueda | p95 objetivo menor a 3 s con backend activo, sujeto al proveedor |
| RNF-007 | Disponibilidad | Best effort en hosting gratuito |
| RNF-008 | Persistencia | Datos confirmados sobreviven al reinicio |
| RNF-009 | Consistencia | Restricciones y transacciones PostgreSQL |
| RNF-010 | Usabilidad | Estados de carga, vacío y error claros |
| RNF-011 | Accesibilidad | Etiquetas semánticas y contraste adecuado |
| RNF-012 | Compatibilidad | Android como plataforma inicial |
| RNF-013 | Mantenibilidad | Arquitectura modular y TypeScript |
| RNF-014 | Testabilidad | Pruebas unitarias e integración |
| RNF-015 | Observabilidad | Logs estructurados sin secretos |
| RNF-016 | Resiliencia | Manejo de fallos del proveedor |
| RNF-017 | Caché | TTL y límite de capacidad |
| RNF-018 | Privacidad | Historial y biblioteca privados por defecto |
| RNF-019 | Recuperación | Reintentos controlados e idempotencia |
| RNF-020 | Coste | Objetivo de infraestructura gratuita |
| RNF-021 | Control de versiones | Git y GitHub |
| RNF-022 | Documentación | README, arquitectura, BD y roadmap |
| RNF-023 | Calidad | CI y análisis estático |
| RNF-024 | Integración externa | MusicProvider desacoplado |
| RNF-025 | Gestión de sesiones | Renovación y revocación de tokens |

## 6. Reglas de negocio

- RN-001: Google Sign-In es obligatorio para acceder a funcionalidades personales.
- RN-002: Cada cuenta Firebase se vincula a un único usuario Mysic.
- RN-003: Los datos privados pertenecen a un usuario interno identificado por UUID.
- RN-004: Una canción solo puede figurar una vez en favoritos por usuario.
- RN-005: Cada usuario tiene como máximo una calificación activa por canción.
- RN-006: Las calificaciones válidas son enteros entre 1 y 5.
- RN-007: Solo el propietario modifica sus playlists.
- RN-008: Solo el autor o moderador modifica el estado de un comentario.
- RN-009: Los comentarios eliminados no se muestran públicamente.
- RN-010: Los eventos de escucha usan identificadores idempotentes.
- RN-011: Los metadatos externos no garantizan disponibilidad de audio.
- RN-012: No se almacenan archivos musicales externos sin autorización.
- RN-013: La reproducción requiere un mecanismo compatible y permitido.
- RN-014: El usuario puede solicitar eliminación de su cuenta y datos.

## 7. Casos de uso prioritarios

### CU-001: Iniciar sesión con Google

Actor: visitante.

Precondición: Firebase correctamente configurado.

Flujo:

1. El visitante abre Mysic.
2. Selecciona Continuar con Google.
3. Completa la autenticación.
4. Flutter obtiene Firebase ID token.
5. Express valida el token.
6. El backend crea o recupera el perfil.
7. Se muestra la pantalla principal.

Resultado: sesión válida y perfil asociado a PostgreSQL.

### CU-002: Crear playlist

Actor: usuario autenticado.

1. Selecciona Nueva playlist.
2. Ingresa nombre y descripción.
3. Flutter envía solicitud autenticada.
4. Express determina el propietario.
5. PostgreSQL registra la playlist.
6. La aplicación confirma la creación.

Resultado: playlist vinculada a `users.id`.

### CU-003: Calificar canción

Actor: usuario autenticado.

1. Abre una canción.
2. Selecciona de 1 a 5 estrellas.
3. El backend valida identidad y puntuación.
4. Inserta o actualiza la calificación.
5. Devuelve la calificación personal y el promedio.

Resultado: una calificación activa por usuario y canción.

### CU-004: Registrar escucha

Actor: usuario autenticado.

1. Inicia reproducción compatible.
2. El reproductor mide el tiempo escuchado.
3. Al alcanzar el criterio definido, registra un evento.
4. El backend valida e inserta la sesión.
5. Las estadísticas utilizan el evento confirmado.

Resultado: historial actualizado sin duplicados.

## 8. Criterios de aceptación globales

La entrega académica deberá demostrar:

- Inicio de sesión con dos cuentas Google distintas.
- Datos privados aislados.
- Playlists persistentes en PostgreSQL.
- Favoritos y calificaciones persistentes.
- Comentarios con autor identificado.
- Historial y estadísticas personales.
- Búsqueda mediante backend y youtubei.js.
- Reproducción demostrable con fuente autorizada.
- Manejo de fallos externos.
- Pruebas de autenticación y autorización.
- APK instalable y documentación actualizada.

## 9. Trazabilidad

Cada historia de usuario debe referenciar al menos un RF.

Cada pull request o conjunto de cambios debe indicar:

- Sprint correspondiente.
- Requisitos afectados.
- Pruebas realizadas.
- Resultado de validación.
- Riesgos o limitaciones pendientes.
