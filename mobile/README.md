# Mysic mobile

Base Flutter Android del Sprint 01 e incremento de autenticación del Sprint 02.
Google Sign-In, Firebase Auth, Riverpod y Dio separan presentación, aplicación y datos.
El inicio solo se muestra después de verificar la sesión en Express.

Configurar el proyecto Firebase y las credenciales conforme a
[la guía del Sprint 2](../docs/06-sprint-02-autenticacion.md). No hay perfil local ficticio.

## Ejecutar

Flutter estable 3.47.8 (Dart 3.13.7) es la versión comprobada localmente y fijada
en CI. Instalar Android Studio y el SDK Android; comprobar con `flutter doctor -v`.
Desde `mobile/`:

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter devices
flutter run
```

En Fish, si `cd` está reemplazado por zoxide, usar `builtin cd`.
El SDK Flutter se instala fuera del repositorio. Los archivos `local.properties`,
credenciales, cachés y builds no se versionan. `pubspec.lock` sí se versiona.
Flutter gestiona los archivos Gradle wrapper que su plantilla excluye de Git.

## Estado y configuración

La ejecución de la pantalla inicial fue demostrada en Sprint 01. Este incremento
requiere repetir análisis, tests y arranque con Firebase configurado.

```bash
python3 tool/configure_firebase.py /ruta/google-services.json
flutter run --dart-define-from-file=config/firebase.android.json
```

Los identificadores cliente se cargan explícitamente con FirebaseOptions y el
client ID OAuth web con GoogleSignIn.initialize. No se requiere Google Services
Gradle para esta modalidad. CI compila sin configuración real y prueba estados
con dobles; no demuestra login real.

El paquete Android sigue siendo com.mysic.mysic. La firma release de la plantilla
usa claves debug y no está lista para distribución. Configuración real y credenciales
administrativas no se versionan. Nunca colocar Firebase Admin credentials en mobile/.

ApiConfig lee API_BASE_URL. HTTP está limitado a hosts locales de desarrollo y solo
se permite en debug; usar HTTPS para un backend remoto.
