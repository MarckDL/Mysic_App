# Mysic mobile

Base Flutter del Sprint 01 con plataforma Android generada y pantalla inicial.
No implementa autenticación ni acceso a datos privados. Riverpod, go_router, Dio
y las integraciones se añadirán con sus funcionalidades.

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

Se demostró el arranque en emulator-5554, Android API 37, mostrando Mysic y
el mensaje de bienvenida. CI compila un APK debug adicionalmente a los tests.

`com.mysic.mysic` es el identificador provisional y debe confirmarse antes de
registrar Android en Firebase (Sprint 02). La firma release sigue usando la clave
debug de la plantilla: no es una configuración de distribución.

`ApiConfig` lee `API_BASE_URL` mediante `--dart-define`; no existe cliente HTTP
ni comunicación de red en esta pantalla. La configuración HTTP de desarrollo
se añadirá con esa integración. No hay credenciales en la aplicación inicial.
