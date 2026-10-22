
# AGENTS.md — Mysic

## 1. Identidad del proyecto

Nombre: Mysic

Repositorio:
git@github.com:MarckDL/Mysic_App.git

Mysic es una aplicación móvil académica de exploración musical, reproducción, playlists, favoritos, calificaciones, comentarios, historial y estadísticas.

El proyecto es multiusuario y utiliza autenticación obligatoria con Google.

No está destinado inicialmente a monetización ni publicación en tiendas.

## 2. Fuentes de verdad

Antes de implementar cambios, leer:

1. `README.md`
2. `docs/01-arquitectura.md`
3. `docs/02-base-de-datos.md`
4. `docs/03-requisitos.md`
5. `docs/04-sprints-roadmap.md`

Si una tarea contradice estos documentos, informar la contradicción y proponer una actualización coherente.

No modificar decisiones arquitectónicas importantes silenciosamente.

## 3. Stack oficial

### Mobile

- Flutter
- Dart
- Riverpod
- go_router
- Dio
- Firebase Auth
- Google Sign-In
- just_audio
- audio_service
- audio_session

### Backend

- Node.js 22 LTS o versión LTS compatible
- Express
- TypeScript
- Firebase Admin SDK
- Prisma
- Zod
- youtubei.js
- Caché LRU

### Base de datos

- PostgreSQL
- Supabase como servicio administrado

### DevOps

- Git
- GitHub
- GitHub Actions
- Docker opcional
- pnpm

MongoDB, NestJS y microservicios no forman parte del stack inicial.

## 4. Prerrequisitos del sistema

Antes de comenzar cualquier Sprint, verificar la disponibilidad de:

### Obligatorios

- Git.
- GitHub con acceso SSH configurado.
- Node.js LTS compatible.
- Corepack y pnpm.
- Flutter SDK.
- Dart SDK, incluido con Flutter.
- Android SDK.
- Android Studio o herramientas Android CLI.
- Java JDK compatible con el toolchain Android.
- Editor de código.
- PostgreSQL Client (`psql`) o cliente SQL equivalente.
- Acceso a Firebase Console.
- Acceso a Supabase.
- Conexión a internet para dependencias.

### Recomendados

- Docker y Docker Compose.
- Android Emulator.
- Dispositivo Android físico.
- Prisma CLI.
- Firebase CLI.
- curl.
- jq.
- Postman o Bruno.

### Comandos de diagnóstico

```bash
git --version
node --version
corepack --version
pnpm --version
flutter --version
dart --version
flutter doctor -v
java -version
psql --version
docker --version
docker compose version
```

Verificar además:

```bash
git remote -v
ssh -T git@github.com
```

El diagnóstico SSH puede solicitar confirmación de la huella del host.

### Herramientas faltantes

Si falta alguna herramienta:

1. Informar cuál falta.
2. Explicar para qué se necesita.
3. Proponer instalación compatible con el sistema operativo.
4. Solicitar confirmación antes de cambios de sistema que requieran privilegios.
5. Instalar solo cuando esté autorizado y existan herramientas disponibles.
6. Verificar nuevamente después de instalar.
7. No afirmar que está instalada sin comprobarlo.

En CachyOS/Arch Linux, preferir instrucciones compatibles con pacman o el gestor configurado.

No instalar paquetes de forma indiscriminada.

## 5. Reglas obligatorias de desarrollo

### R-001 — Autenticación

Google Sign-In mediante Firebase Auth es obligatorio.

No sustituir por un perfil local único.

### R-002 — Validación de identidad

Todas las operaciones privadas deben verificar Firebase ID token en Express.

No confiar en `user_id` enviado desde Flutter.

### R-003 — Persistencia

Playlists, favoritos, ratings, comentarios e historial se almacenan en PostgreSQL.

SQLite puede utilizarse únicamente como caché local o soporte offline.

### R-004 — Identificadores

Utilizar:

- `users.id` como UUID interno.
- `users.firebase_uid` para vinculación con Firebase.
- `users.google_id` como dato del proveedor Google cuando esté disponible.

Las claves foráneas utilizan `users.id`.

### R-005 — youtubei.js

`youtubei.js` debe existir exclusivamente dentro de `backend/`.

Nunca instalarlo o importarlo desde Flutter.

### R-006 — Proveedores externos

Toda integración musical debe implementar la interfaz `MusicProvider`.

No acoplar los módulos de dominio a las respuestas internas de youtubei.js.

### R-007 — Reproducción

La extracción o retransmisión de audio no debe asumir derechos de uso.

No implementar evasión de DRM, autenticación, bloqueos o restricciones de proveedor.

Usar fuentes autorizadas para pruebas y demostraciones.

### R-008 — Arquitectura

Mantener separación entre:

- Presentación.
- Dominio.
- Aplicación.
- Infraestructura.

Evitar lógica de negocio dentro de widgets Flutter o controladores HTTP.

### R-009 — Seguridad

Nunca incluir en commits:

- `.env`
- Service account JSON
- Firebase Admin credentials
- Contraseñas
- Tokens
- Claves privadas
- URLs de conexión con credenciales

### R-010 — Calidad

Antes de completar una tarea:

- Ejecutar análisis estático.
- Ejecutar pruebas pertinentes.
- Revisar errores.
- Actualizar documentación si corresponde.

### R-011 — Base de datos

Usar migraciones Prisma versionadas.

No modificar manualmente producción sin una migración revisada.

### R-012 — APIs

Utilizar rutas versionadas:

`/api/v1/...`

Usar códigos HTTP adecuados y respuestas de error consistentes.

### R-013 — Dependencias

Preferir versiones estables y compatibles.

No instalar paquetes innecesarios.

Registrar cambios relevantes en lockfiles.

### R-014 — Git

No ejecutar `git push --force` sobre ramas compartidas.

No reescribir etiquetas publicadas.

No eliminar trabajo no confirmado sin autorización.

## 6. Flujo de trabajo del agente

Antes de implementar:

1. Leer documentación.
2. Inspeccionar estructura actual.
3. Revisar `git status`.
4. Identificar Sprint y requisitos.
5. Verificar dependencias.
6. Proponer cambios necesarios.

Durante la implementación:

1. Mantener cambios pequeños.
2. Respetar módulos existentes.
3. Agregar pruebas.
4. Evitar introducir secretos.
5. Documentar decisiones nuevas.

Después:

1. Ejecutar pruebas.
2. Revisar diff.
3. Informar archivos modificados.
4. Informar resultados y limitaciones.
5. Confirmar criterios de aceptación.

## 7. Regla obligatoria de cierre de Sprint

**Al finalizar y verificar cada Sprint, se DEBE realizar un `git commit` y `git push` formal etiquetando la versión/sprint.**

Esta regla forma parte de la Definition of Done del Sprint.

Procedimiento:

```bash
git status
git add .
git commit -m "chore(sprint-XX): complete sprint"
git push origin main
git tag -a sprint-XX-vX.Y.Z -m "Sprint XX verified"
git push origin sprint-XX-vX.Y.Z
```

Los comandos son plantillas; sustituir los valores correspondientes.

Antes de ejecutar:

- Verificar rama y remoto.
- Verificar que no se incluyan secretos.
- Confirmar pruebas.
- Confirmar autorización para publicar cambios.
- Si existe flujo de pull requests, integrar primero en main.

No realizar commits vacíos para simular avances.

No etiquetar Sprints incompletos.

No afirmar que el push fue exitoso sin verificar el resultado.

## 8. Convenciones

### Código

- TypeScript estricto.
- Dart con análisis estático.
- Nombres descriptivos.
- Funciones pequeñas.
- Validación en límites de entrada.
- Manejo explícito de errores.

### Git

Conventional Commits.

Ejemplos:

```text
feat(auth): add Google Sign-In
feat(catalog): implement music provider
fix(playlists): enforce ownership
test(auth): reject invalid tokens
```

### Documentación

Actualizar `docs/` cuando cambien:

- Arquitectura.
- Modelo de datos.
- Requisitos.
- Roadmap.
- Decisiones técnicas.

## 9. Criterios de seguridad multiusuario

Probar como mínimo:

1. Usuario A crea playlist.
2. Usuario B no puede editarla.
3. Usuario B no puede consultar historial privado de A.
4. Usuario A solo modifica sus comentarios.
5. Tokens inválidos reciben HTTP 401.
6. Acceso autenticado sin permisos recibe HTTP 403 o respuesta equivalente definida por la API.

## 10. Prioridad de implementación

Seguir el orden:

1. Infraestructura.
2. Autenticación.
3. Usuarios y PostgreSQL.
4. Catálogo.
5. Viabilidad de reproducción.
6. Reproductor.
7. Playlists.
8. Favoritos y ratings.
9. Comentarios.
10. Historial.
11. Estadísticas.
12. Optimización.
13. Pruebas.
14. Entrega.

No adelantar funcionalidades complejas si las dependencias críticas siguen sin validar.
