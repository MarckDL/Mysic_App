# Sprint 02 — Autenticación Google

Fecha de revisión: 25 de octubre de 2026. Estado: **validación local y CI completadas; etiqueta pendiente**.
Historia: US-002. Requisitos: RF-001, RF-002, RF-004, RF-005; soporte inicial de
RF-008 y RNF-002/003/004/018/025. RF-003 y la identidad UUID interna quedan en Sprint 03.

## Alcance y decisiones

- Google Sign-In nativo intercambia el ID token Google por una sesión Firebase.
- Solo el Firebase ID token viaja a Express como `Authorization: Bearer ...`.
- Firebase Admin verifica firma, expiración, audiencia, emisor y revocación.
- `GET /api/v1/auth/session` comprueba la sesión; devuelve Firebase UID y proveedor.
  No es `/auth/sync`, no crea registros y no simula un UUID de PostgreSQL.
- Falta token o token inválido: 401. Otro proveedor: 403. Fallo de configuración,
  credenciales o comunicación Firebase: 503. Errores no revelan tokens ni detalles SDK.
- Health sigue público. Las rutas de auth usan Cache-Control: no-store.
- Flutter recupera la sesión desde Firebase, exige confirmación del backend para
  mostrar inicio, permite logout y maneja cancelación/carga/error.
- Ante 401 se fuerza renovación una sola vez para el GET de sesión. Un segundo
  401 o un 403 cierra sesión local. Las respuestas de otra cuenta no validan la actual.
- Logout local no equivale a revocar todos los dispositivos. La API comprueba
  revocación en cada solicitud privada. No existe endpoint público de revocación.
- Sin configuración cliente válida la app muestra que el login no está disponible;
  no crea una cuenta ficticia ni entra a funcionalidades personales.

## Dependencias y comprobaciones iniciales

El entorno conserva Git, Node 24, Corepack/pnpm, Java/Javac, psql, Android Studio,
Android SDK y Flutter/Dart. En el ejecutor, Flutter no figura en PATH de Bash,
pero existe en /home/dino/development/flutter. Firebase CLI y FlutterFire CLI no
están instalados y no son necesarios para la configuración explícita usada aquí.
Acceso a Firebase Console y Supabase aún no confirmado. Supabase es de Sprint 03.

El ejecutor sigue sin resolver DNS del registro npm, sin escritura en la caché
Flutter ni ~/.dartServer, sin sockets de pruebas HTTP y con .git de solo lectura.
La instalación offline de firebase-admin se intentó y falló por ausencia de paquetes.
`package.json` declara Firebase Admin 14.5; falta ejecutar `pnpm install` desde
la terminal normal y actualizar pnpm-lock.yaml. Hasta entonces, frozen-lockfile
fallará y TypeScript no resolverá firebase-admin/app ni firebase-admin/auth.

Las dependencias Flutter ya aparecen resueltas en pubspec.lock y en la caché local
(firebase_core 5.1.0, firebase_auth 7.0.1, google_sign_in 7.2.0, flutter_riverpod
3.4.3 y dio 5.11.1). Se comprobó su presencia; esto no equivale a probar la app.

## Configuración Firebase paso a paso

### 1. Crear proyecto y habilitar Google (requiere la cuenta del usuario)

1. Abrir https://console.firebase.google.com/ y crear un proyecto, por ejemplo Mysic.
2. Anotar el **ID del proyecto**, que puede ser distinto de su nombre visible.
3. Entrar a Authentication, iniciar la configuración y habilitar el proveedor Google.
   Seleccionar el correo de soporte solicitado.
4. Registrar una aplicación Android en Configuración del proyecto con paquete exacto
   `com.mysic.mysic`. Este identificador coincide con el código existente.
5. Agregar las huellas SHA-1 y SHA-256 de la firma debug del equipo.
6. Descargar `google-services.json` después de habilitar Google y registrar las SHA.
   Conservarlo localmente. No pegar cuentas administrativas ni tokens en el chat.

Huellas debug comprobadas en el equipo durante esta revisión:

```text
SHA-1: 69:95:AC:DB:9F:31:65:46:35:BF:A3:A2:3D:D6:05:9D:C2:8C:1E:D9
SHA-256: CF:5B:53:CD:06:AC:5E:53:E3:CA:E6:DB:AF:A1:06:71:30:A4:3F:F7:D1:4F:D1:3F:76:A3:B2:31:7F:62:C1:FB
```

Son huellas públicas del certificado debug, no una clave privada. Deben volver a
obtenerse si se cambia de equipo o keystore. La firma release requiere sus propias SHA.

### 2. Configuración cliente local

Desde mobile/, convertir el archivo cliente descargado (ajustar la ruta):

```bash
python3 tool/configure_firebase.py /home/dino/Descargas/google-services.json
```

Se genera `config/firebase.android.json`, excluido de Git. El conversor verifica
el paquete Android y la existencia de un cliente OAuth **web** (client_type 3),
y rechaza archivos administrativos. No reemplaza una configuración existente.
Si no encuentra el cliente web, revisar Google habilitado y descargar nuevamente
la configuración, conforme a la guía de google_sign_in_android.

Se usa FirebaseOptions y serverClientId explícito, modalidad soportada sin
Google Services Gradle. No se importa firebase_options.dart ni se publica configuración
real en CI. No se requiere crear una interfaz web para obtener un cliente OAuth web.

### 3. Configuración Admin del backend

El backend requiere el mismo FIREBASE_PROJECT_ID y Application Default Credentials
con permisos para consultar el usuario (necesario al comprobar revocación).
En un entorno administrado puede usarse una identidad de servicio sin archivo de clave.

Para desarrollo local, si se utiliza una clave JSON de cuenta de servicio:

1. Obtenerla desde Configuración del proyecto > Cuentas de servicio, según permisos
   de la cuenta y políticas del proyecto.
2. Guardarla **fuera del repositorio**, por ejemplo bajo /home/dino/.config/mysic/.
3. Crear backend/.env a partir de .env.example si aún no existe y editar localmente:

```dotenv
NODE_ENV=development
PORT=3000
FIREBASE_PROJECT_ID=ID_REAL_DEL_PROYECTO
GOOGLE_APPLICATION_CREDENTIALS=/ruta/absoluta/fuera/del/repositorio/cuenta-servicio.json
```

No incluir el JSON en Flutter, Git o el chat. El archivo cliente google-services.json
no sustituye una credencial administrativa. Nunca habilitar FIREBASE_AUTH_EMULATOR_HOST
en esta API: el adaptador rechaza esa modalidad para no aceptar tokens sin firma.

### 4. Instalar y probar

Terminal backend:

```bash
cd /home/dino/programacion/mysic_app/backend
pnpm install
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm format:check
pnpm dev
```

En Fish se puede usar builtin cd. En otra terminal:

```bash
cd /home/dino/programacion/mysic_app/mobile
flutter pub get
dart format lib test
flutter analyze
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
flutter run -d emulator-5554 --dart-define-from-file=config/firebase.android.json
```

El emulador debe estar encendido. La URL local por defecto es http://10.0.2.2:3000.
Solo debug permite HTTP a localhost, 127.0.0.1 y 10.0.2.2; usar HTTPS para remotos.
No hay logs de tokens ni redirecciones HTTP autenticadas. go_router se incorporará
cuando existan rutas de navegación; este incremento usa un gate de sesión.

## Evidencia de pruebas de este incremento

- ESLint y Prettier backend: correctos.
- 24 pruebas nuevas sin sockets: correctas. Cubren cabeceras inválidas, identidad
  verificada, proveedor Google, rechazo de expirados/revocados/deshabilitados,
  distinción 401/403/503, ocultación de errores y bloqueo del emulador Firebase.
  La llamada verifyIdToken con checkRevoked=true se comprueba con un doble del SDK.
- 4 pruebas del conversor cliente: correctas.
- Formato Dart aplicado. El proceso devuelve error al escribir telemetría fuera
  del workspace; no se declara flutter analyze correcto.
- Suite backend completa intentada: 38 casos, 31 correctos y 7 bloqueados por
  EPERM al abrir sockets (4 HTTP de health/errores y 3 de autenticación).
- Nuevas pruebas Flutter preparadas; ejecución pendiente desde la terminal normal.
- Typecheck/build backend bloqueados hasta instalar Firebase Admin. Los unit tests
  no sustituyen la comprobación real de firmas ni la configuración del proyecto.
- CI no ejecutada para estos cambios. El Sprint 02 no está publicado ni etiquetado.

## Actualización de validación local

El usuario instaló Firebase Admin 14.5.0 y actualizó pnpm-lock.yaml desde su terminal.
Confirmó lint, typecheck, build y format:check correctos; las 38 pruebas backend
pasaron. También confirmó flutter pub get, flutter analyze sin problemas y las
10 pruebas Flutter correctas. Las limitaciones anteriores describen el ejecutor
del agente, no el resultado local actual. El proyecto Firebase fue creado;
Android y Google ya están configurados. Las pruebas reales se completaron según
las confirmaciones del usuario registradas a continuación.

## Validación real confirmada por el usuario — 25 de octubre de 2026

- Login Google: bienvenida y mensaje de sesión verificada por Express.
- Hot restart: recuperación de sesión sin seleccionar de nuevo la cuenta.
- Logout, nuevo ingreso y cancelación del selector: correctos.
- Cambio entre dos cuentas Google: correcto, con UID distintos.
- GET /api/v1/auth/session sin token y con token inválido: HTTP 401,
  error UNAUTHENTICATED, Cache-Control no-store y WWW-Authenticate apropiado.
- Cuenta deshabilitada en Firebase: cierra sesión y rechaza nuevos ingresos;
  al habilitarla permite autenticación de nuevo.
- Revocación explícita mediante Firebase Admin revokeRefreshTokens para la cuenta
  de prueba: el usuario confirmó cierre de sesión tras hot restart y nuevo login
  correcto. No se copiaron tokens ni credenciales al registro de pruebas.

La prueba manual de revocación confirma el comportamiento observado de la app;
la suite del adaptador verifica por separado verifyIdToken(token, true) y el
rechazo de auth/id-token-revoked. No se capturó el HTTP de un token real revocado.

## Revisión final del agente — 25 de octubre de 2026

- Backend: lint, typecheck, format:check, 38 pruebas y build correctos.
- Conversor cliente: 4 pruebas correctas.
- git diff --check: correcto.
- Escaneo de archivos candidatos a Git: sin coincidencias de claves privadas,
  claves API Google o conexiones PostgreSQL con contraseña. Este escaneo por
  patrones complementa la revisión; no garantiza detectar todo secreto posible.
- .env, configuración cliente real y su copia .bak: excluidos de Git.
  La plantilla firebase.android.example.json contiene valores vacíos.
- Revisados middleware, adaptador Firebase, gate Flutter, cambio de cuenta,
  renovación única ante 401 y restricciones HTTP locales: sin hallazgos bloqueantes.
- Ambos lockfiles incluyen las dependencias de autenticación.
- Flutter analyze/test intentados de nuevo: bloqueados antes de ejecutar porque
  la caché del SDK está montada como solo lectura. Se conserva la validación previa
  del usuario: análisis sin problemas y 10 pruebas correctas.
- El usuario compiló e instaló el APK debug con Firebase y confirmó el flujo real.
  Advertencias Gradle/Kotlin observadas: no bloquearon el build; requieren seguimiento
  de compatibilidad en futuras actualizaciones del toolchain.

## Validación remota y cierre pendiente

Commit publicado: `be8b81968b8370ea43e6b17ef9ef424144baf14e`.
GitHub Actions Quality #4: backend y mobile completados con success, incluidos
formato, análisis, pruebas, conversor Python y compilación APK debug.

Evidencia: https://github.com/MarckDL/Mysic_App/actions/runs/40176723434

El usuario completó la última verificación Flutter: 15 archivos sin cambios de
formato, análisis sin problemas y 10 pruebas correctas.

Falta publicar este registro documental y la etiqueta anotada `sprint-02-v0.2.0`
sobre el commit verificado. No se declara publicada hasta verificar su referencia.

## Fuentes oficiales

- https://firebase.google.com/docs/auth/flutter/federated-auth
- https://pub.dev/packages/google_sign_in_android
- https://firebase.google.com/docs/admin/setup
- https://firebase.google.com/docs/auth/admin/verify-id-tokens
- https://firebase.google.com/docs/auth/admin/manage-sessions
