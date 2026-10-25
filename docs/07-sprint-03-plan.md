# Sprint 03 — Plan de PostgreSQL y usuarios

Fecha: 25 de octubre de 2026. Estado: validación local y CI completadas; publicación de etiqueta pendiente.
Historia: US-003. Versión prevista: sprint-03-v0.3.0.

## Objetivo y alcance

Persistir un perfil Mysic por identidad Firebase y permitir consultar únicamente
el perfil propio. Base: docs/01-arquitectura.md, docs/02-base-de-datos.md,
docs/03-requisitos.md y Sprint 03 de docs/04-sprints-roadmap.md.

Requisitos: RF-003 y RF-008; consulta de RF-006 y preparación de RF-007.
El roadmap solo incluye preparar la estrategia de eliminación. La eliminación
completa y la edición de perfil siguen pendientes; este sprint no dará esos
requisitos completos por satisfechos. No se crean aún tablas del catálogo,
playlists, favoritos, comentarios ni historial.

## 1. Preparar PostgreSQL

- Crear o seleccionar un proyecto Supabase de desarrollo.
- Obtener conexión de ejecución y conexión para migraciones, con TLS.
- Guardarlas solo en backend/.env; publicar únicamente nombres y ejemplos vacíos.
- Comprobar conectividad desde el equipo y compatibilidad del modo de conexión
  con Prisma antes de elegir conexión directa o pooler.
- Elegir versiones estables de Prisma y adaptadores compatibles con Node/TypeScript
  existentes; verificar documentación oficial al implementar y actualizar lockfile.
- Mantener Flutter conectado exclusivamente a Express. Firebase continúa siendo
  el proveedor de identidad; no se incorpora Supabase Auth.
- Mantener tabla privada fuera del acceso anónimo de la Data API: revisar esquema,
  permisos y RLS cuando corresponda; no asumir que RLS sustituye autorización Express.

Dependencia del usuario: acceso al proyecto Supabase y configuración local de las
conexiones. No pegar contraseñas ni cadenas con credenciales en el chat.

## 2. Prisma y primera migración

- Crear esquema Prisma, configuración, cliente compartido y ciclo de desconexión.
- Crear únicamente users, respetando el diccionario de datos:
  UUID id; firebase_uid único obligatorio; google_id único opcional;
  email opcional; display_name obligatorio; photo_url opcional;
  created_at y updated_at en TIMESTAMPTZ/UTC.
- Mapear nombres de dominio a columnas snake_case.
- Versionar y revisar SQL; aplicar en una base de desarrollo limpia.
- Separar credenciales de ejecución y migraciones cuando sea viable.
- Evitar resets remotos y configuración de shadow database sobre una base con datos.
- Documentar generate, migrate dev y migrate deploy conforme a la versión elegida.

## 3. Sincronización de identidad y API

- Extender AuthIdentity con los campos de perfil obtenidos de claims verificados,
  validando tipos y longitudes; google_id solo desde identities de Google.
- Definir fallback de nombre cuando Firebase no incluya uno, sin usar el email
  como clave de identidad ni fusionar cuentas por coincidencia de email.
- Implementar repositorio users y servicio de aplicación fuera del controlador.
- POST /api/v1/auth/sync: requireAuth; crear o sincronizar por firebase_uid y
  devolver perfil persistido con UUID interno. Propuesta: HTTP 200 en ambos casos.
- Garantizar idempotencia con upsert/restricción única; probar concurrencia real.
- No aceptar id, firebase_uid, google_id ni propietario desde body o query.
- GET /api/v1/users/me: resolver usuario por UID verificado; devolver solo su perfil.
  Si no existe, 404 con código USER_NOT_SYNCED para solicitar sincronización.
- Mantener GET /api/v1/auth/session compatible, sin dependencia de PostgreSQL.
- Usar Cache-Control no-store; errores consistentes y sin detalles SQL/credenciales.
- Fallo de base: 503; token inválido: 401; proveedor no admitido: 403.
- Conflicto de google_id: error controlado, sin vincular automáticamente cuentas.

## 4. Integración Flutter

- Tras autenticar o recuperar sesión, sincronizar el perfil antes de mostrar inicio.
- Incorporar modelo de usuario Mysic: UUID interno distinto del UID Firebase.
- Mostrar nombre y correo del perfil persistido; foto opcional con fallback.
- Limpiar perfil/estado al salir o cambiar de cuenta, descartando respuestas tardías.
- Si falla PostgreSQL, mostrar error y reintento sin borrar una sesión Firebase válida.
- Reintento explícito de sync seguro por idempotencia; no extender automáticamente
  el reintento de GET a cualquier operación de escritura.
- Mantener permisos y resolución de propietario exclusivamente en el backend.

## 5. Pruebas y CI

- Unitarias: sincronización, claims incompletos, conflictos y fallos de repositorio.
- HTTP: sync/me autenticados; token ausente/inválido/revocado; identidad falsificada
  en body/query; /me sin sincronización; respuestas privadas sin caché.
- Integración PostgreSQL real de prueba: migración desde cero, UUID, unicidad,
  dos cuentas distintas, sync repetido/concurrente y persistencia entre sesiones.
- Aislamiento: A no puede seleccionar B mediante body/query; ninguna ruta genérica
  de perfiles privados permite enumerar o recuperar datos de B.
- Flutter: carga/error/reintento, perfil persistido, logout, cambio de cuenta y
  respuesta tardía de la anterior.
- CI con servicio PostgreSQL temporal para migraciones y pruebas de integración;
  sin credenciales Supabase reales. Conservar análisis/pruebas/build existentes.

## 6. Datos personales y operación

- Documentar eliminación futura coordinada entre PostgreSQL y Firebase: identidad
  reciente, relaciones, errores parciales y reintentos. No implementar DELETE todavía.
- Definir qué campos vienen de Google y cómo evitar que una futura sync sobrescriba
  personalizaciones cuando se implemente la edición de perfil.
- Documentar respaldo/restauración y probar migraciones en base desechable.
- Actualizar arquitectura, modelo, requisitos y seguimiento según decisiones finales.

## Criterios de aceptación

1. A y B tienen filas distintas y UUID internos distintos.
2. Sync repetida o concurrente no duplica usuarios ni cambia su UUID.
3. El perfil y UUID persisten tras logout, reinicio y nuevo login.
4. /users/me siempre devuelve el perfil de la identidad verificada.
5. Flutter no puede elegir el propietario; la base no expone perfiles anónimamente.
6. No se almacenan tokens ni contraseñas Google en PostgreSQL.
7. Migración reproducible, pruebas de integración y suites existentes correctas.
8. Prueba manual con las dos cuentas reales, revisión de secretos y CI verde.
9. Commit y etiqueta sprint-03-v0.3.0 publicados y verificados al cerrar el sprint.

## Orden de ejecución

1. Supabase y conectividad.
2. Prisma, tabla y migración.
3. Sync y perfil propio con pruebas backend.
4. Integración Flutter y pruebas multiusuario.
5. CI PostgreSQL, documentación y revisión final.
6. Publicación y verificación de etiqueta sobre el commit probado.

## Avance inicial — 25 de octubre de 2026

- El usuario confirmó SELECT 1 mediante psql, Session pooler y TLS require.
- Preparados schema.prisma y prisma.config.ts para Prisma 7, con cliente ESM
  generado bajo src/generated/prisma y URL de migraciones en DIRECT_URL.
- users se ubicará en un esquema dedicado mysic para separar los datos privados
  de los esquemas administrados por Supabase. No agregar mysic a los esquemas
  expuestos por la Data API. Revisar permisos al aplicar la primera migración.
- Esta decisión conserva PostgreSQL/Prisma y el acceso exclusivamente por Express.
- Preparados scripts db:generate, db:validate, db:deploy y db:status.
- Instalación, generación, validación y creación de la migración aún pendientes.
  No ejecutar migrate dev ni reset contra Supabase sin preparar una shadow database
  aislada; la primera migración se generará desde esquema vacío y se revisará antes
  de migrate deploy. Ningún cambio de tabla se ha aplicado desde el agente.

## Primera migración preparada

Prisma CLI, Client y adapter-pg 7.10.1 instalados por el usuario; esquema validado
 y cliente generado. Se conserva Prisma 7 estable; no se migra a Prisma 8 RC.

Migración: backend/prisma/migrations/20261025113000_create_users/migration.sql.
Generada con migrate diff --from-empty --to-schema prisma/schema.prisma --script,
sin conexión a Supabase ni shadow database. Revisión: crea solo mysic.users y sus
índices únicos; no contiene DROP, resets ni cambios a tablas de auth/storage.
Incluye transacción, RLS sin políticas y revocación de privilegios de PUBLIC.
El propietario PostgreSQL usado inicialmente por el backend puede acceder; roles
anon/authenticated no deben recibir políticas ni acceso al esquema mysic. Antes
de desplegar con otro rol, definir permisos mínimos y su relación con RLS.

Actualización: migración aplicada por el usuario y estado actualizado. Los
endpoints sync/me ya se implementaron; ver evidencia al final del documento.

## Incremento de perfiles implementado

El usuario aplicó create_users en Supabase y confirmó migrate status actualizado.

- POST /api/v1/auth/sync crea/actualiza por Firebase UID y responde 200 con perfil.
- GET /api/v1/users/me consulta solo el UID verificado; sin fila responde 404
  USER_NOT_SYNCED. Body/query con valores adicionales reciben 400.
- Firma/revocación y Google siguen siendo obligatorios. Solo claims verificados
  suministran nombre, correo, foto HTTPS e identidad Google; nunca el body.
- Los campos presentes de Google se sincronizan; los ausentes conservan los valores
  anteriores. Un nuevo perfil sin nombre usa Usuario Mysic. La edición personalizada
  deberá separar estos campos antes de incorporarse para evitar sobrescrituras.
- Conflictos únicos: 409 sin revelar datos ajenos; errores de base: 503 sin SQL.
- Cliente Prisma compartido, creación diferida y desconexión al cerrar servidor.
  Remotos usan TLS con validación del certificado; no se desactiva verificación.
- Flutter valida sesión y sincroniza antes de mostrar inicio, usando el nombre y
  correo persistidos. Descarta perfiles tardíos de otra cuenta y permite reintento
  sin borrar Firebase si PostgreSQL falla. No reintenta automáticamente el POST.
- CI preparada con PostgreSQL 17 desechable, migraciones y generación del cliente.
  TEST_DATABASE_URL activa pruebas PostgreSQL; nunca se usa automáticamente la
  conexión Supabase para esas pruebas. La CI aún no se ha ejecutado para Sprint 03.
- Flutter: formato aplicado; análisis/tests pendientes en terminal normal por caché
  y telemetría de solo lectura. No se declara validado el nuevo flujo real todavía.

### Estrategia de eliminación futura (sin endpoint en este sprint)

La eliminación requerirá autenticación reciente, un estado persistente de solicitud,
reintentos idempotentes y tratamiento de errores parciales. Se revocarán sesiones,
se eliminarán o anonimizarán relaciones según política y finalmente la identidad
Firebase. No se coordinarán ambas plataformas como si fueran una sola transacción.
Debe decidirse la retención de comentarios públicos y conservar evidencia mínima
sin tokens ni datos personales innecesarios. RF-007 continúa pendiente de implementación.

### Siguientes verificaciones

1. Ejecutar pnpm db:check desde el equipo para comprobar también el adaptador Prisma.
2. Analizar/probar Flutter y reiniciar backend/aplicación.
3. Login con A y B: confirmar mensaje de perfil guardado y dos filas diferentes
   en mysic.users. Reingresar con A y confirmar UUID estable y ausencia de duplicados.
4. Verificar GET /users/me y aislamiento en integración PostgreSQL/CI.
5. Completar documentación, revisión de secretos y publicación solo tras CI verde.

### Resultado de verificación del incremento

Lint, typecheck, formato y build backend correctos. Suite: 47 pruebas correctas y
3 PostgreSQL omitidas por ausencia de TEST_DATABASE_URL; ninguna prueba se ejecutó
contra Supabase desde este agente. git diff --check correcto. Las pruebas HTTP
usan repositorios controlados; no sustituyen las pruebas de unicidad/concurrencia
reales pendientes. Flutter incorpora tres nuevos casos de sync/error/cambio de
cuenta; ejecución pendiente. No se ha realizado commit ni cierre de Sprint 03.

### Diagnóstico de conexión pendiente

El usuario ejecutó Flutter: 13 pruebas correctas y un aviso de llaves en if.
El aviso se corrigió. db:check falló con el mensaje genérico; todavía no se conoce
la causa. Se añadió clasificación local segura de TLS/DNS/autenticación/red/permisos,
sin imprimir errores originales. La validación de certificados permanece activa.
Se requiere repetir db:check para identificar el siguiente paso.

### Certificado de PostgreSQL

El diagnóstico del usuario confirmó fallo de validación TLS en Prisma; no depende
del emulador ni de Flutter. Se añadió DATABASE_SSL_CA_FILE para cargar el certificado
CA descargado desde Database Settings > SSL Configuration de Supabase.
El archivo se conserva fuera del repositorio. La verificación de certificado y
hostname continúa activa; no se utiliza rejectUnauthorized:false.
La prueba anterior psql con sslmode=require cifraba sin verificar el servidor.
Resuelto: el usuario configuró la CA y db:check confirmó conexión Prisma correcta.

## Validación real de persistencia — 25 de octubre de 2026

El usuario confirmó el mensaje de perfil guardado con ambas cuentas, dos filas en
mysic.users con UUID diferentes y conservación de los perfiles al volver a iniciar
sesión, sin duplicados observados. Prisma conecta con TLS y CA configurada.

Verificaciones backend más recientes: lint, tipos, formato y build correctos;
50 pruebas correctas. Tres pruebas PostgreSQL siguen pendientes de ejecución en
base desechable/CI. Flutter: 13 pruebas correctas; el aviso de estilo identificado
fue corregido. El usuario confirmó después el flujo manual con ambas cuentas.

La prueba manual de persistencia no demuestra por sí sola aislamiento completo ni
concurrencia: se mantienen pendientes la ejecución de integración y la CI.
No se declara cerrado el Sprint ni publicada su etiqueta.

### Última comprobación Flutter

El usuario confirmó formato de 16 archivos sin cambios y flutter analyze sin
problemas después de corregir el aviso de llaves. Las 13 pruebas ya habían pasado.
Pendiente publicar el incremento y ejecutar Quality con PostgreSQL desechable.

## Validación remota final

Commit probado: `26f69aca2a41349e55e96dc47ef933ebd1cac2bc`.
GitHub Actions Quality: https://github.com/MarckDL/Mysic_App/actions/runs/40191284274

Backend y mobile completados con success. Se verificó el log backend: 53 pruebas
correctas, incluidos los tres casos de PostgreSQL real, sin omisiones. Migración
desde cero, validación/generación Prisma, lint, tipos, formato y build correctos.
Flutter pasó formato, análisis, pruebas, conversor Python y compilación APK debug.

Esta sección actualiza los pendientes históricos de integración y CI descritos
anteriormente. Permanece pendiente publicar el registro y la etiqueta anotada
`sprint-03-v0.3.0` sobre el commit probado. La referencia remota debe verificarse
antes de declarar cerrado el Sprint.
