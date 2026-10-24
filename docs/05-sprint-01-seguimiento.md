# Sprint 01 — Fundamentos

Fecha de revisión: 24 de octubre de 2026.
Estado: **implementación local verificada; cierre formal pendiente**.
Historia: US-001. Requisitos habilitados: RNF-004, RNF-013, RNF-014,
RNF-021, RNF-022 y RNF-023. Firebase y PostgreSQL se implementan en sprints 2/3.

## Entrega

- Backend Express y TypeScript estricto, app separada del servidor.
- Endpoint público de liveness `GET /api/v1/health`: `{"status":"ok"}`.
- Errores JSON consistentes, límite del cuerpo, configuración de puerto validada
  y cierre por señales. No existen rutas privadas sin autenticación.
- ESLint 10.13.0, @eslint/js 10.0.1, Prettier, Vitest y Supertest con 11 pruebas.
- Flutter Android, pantalla inicial de Mysic y prueba de widget.
- Ambos lockfiles generados y destinados a Git.
- CI con instalación reproducible, comprobaciones backend, análisis/prueba Flutter
  y compilación APK debug. Flutter fijado a la versión comprobada 3.47.8.
- `.env.example` sin credenciales. Identificador Android provisional com.mysic.mysic.

## Verificación

| Comprobación | Evidencia y resultado |
|---|---|
| Backend lint, tipos, formato y build | Correctos; el usuario los repitió tras actualizar ESLint 10 |
| Backend tests | Terminal del usuario: 11/11 correctos, también tras actualizar ESLint 10 |
| Health real | Usuario confirmó respuesta ok desde el navegador |
| Flutter dependencias y lockfile | Instalación completada por el usuario; archivos presentes |
| Flutter formato, analyze y test | Usuario aportó salida: sin cambios, sin problemas, 1 prueba correcta |
| Android | APK debug presente; usuario confirmó pantalla de Mysic en emulator-5554 |
| Revisión de secretos y exclusiones | Revisados archivos publicables y reglas Git; sin credenciales detectadas |
| CI remota | Configurada; pendiente de publicación y ejecución |
| Publicación y etiqueta | Pendientes; no se declara cerrado el Sprint |

Las pruebas HTTP del agente están bloqueadas por EPERM al abrir sockets; los
siete casos de configuración pasan. Flutter no puede escribir en su caché ni el
analizador en ~/.dartServer desde el ejecutor restringido. No son errores del
proyecto: los comandos se completaron en la terminal del usuario.

## Entorno

Git 2.56.0, Node 24.22.1, Corepack 0.36.0, pnpm 10.34.7,
Flutter 3.47.8, Dart 3.13.7, Java/Javac 17.0.20.1, psql 18.6,
Docker 29.9.2 y Compose 5.6.1. Android Studio incluye además un JDK que Flutter
utilizó para la compilación local. CI usa Java 21 para Gradle.
El acceso a consolas Firebase y Supabase queda sin verificar.

## Pendientes de cierre

La actualización de ESLint y @eslint/js está completada con lockfile actualizado.
El usuario confirmó lint, typecheck, las 11 pruebas, build y format:check correctos.
El aviso de script esbuild omitido no bloqueó tests, desarrollo ni compilación;
no se autorizaron scripts de paquetes indiscriminadamente.

1. Crear commit, publicar y comprobar GitHub Actions. `git add` fue intentado y
   falló al crear `.git/index.lock` porque `.git` está montado como solo lectura.
   No se creó commit, no se ejecutó push ni se generó etiqueta desde el agente.
   La autorización de publicación fue otorgada por el usuario en esta sesión.
2. Solo con CI correcta, publicar etiqueta anotada sprint-01-v0.1.0 sobre el commit
   integrado en main y registrar el resultado.

El remoto es git@github.com:MarckDL/Mysic_App.git y la rama local es main.
SSH falla desde el ejecutor por permisos de la configuración global. El conector
GitHub consultado devuelve pull=true y push=false para este repositorio: no se
utiliza para publicar sin permisos. No se modifica configuración del sistema.

## Emulador

Pixel_7 y Medium_Phone tienen igual configuración: 4 núcleos, 1080x2400,
2048 MiB declarados e imagen API 37 Google Play x86_64. API 37 eleva la RAM de
la máquina virtual a un mínimo de 4 GB. No es necesario cambiar de perfil si el
rendimiento es adecuado; utilizar un solo emulador.
Fuente: https://developer.android.com/studio/releases/emulator
