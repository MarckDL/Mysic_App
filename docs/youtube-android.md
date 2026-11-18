# Biblioteca de YouTube en Android

En el piloto, Biblioteca abre la autorización en el navegador. Al volver, Mysic comprueba el intento con la sesión Firebase que lo inició, confirma el canal y carga sus playlists. Cuenta permite cambiar el canal y desvincularlo. Cuando Android mantiene el navegador abierto, se puede volver a Mysic, tocar **Comprobar vinculación** y confirmar el canal mostrado. Un cambio de canal requiere confirmación expresa. La importación Takeout conserva su entrada propia.

## Preparar el entorno de prueba

1. Configurar un backend HTTPS con las variables de [OAuth](youtube-oauth.md), las migraciones y los endpoints de [biblioteca](youtube-library.md). En Google Cloud registrar la URI exacta de `YOUTUBE_OAUTH_CALLBACK`.
2. Elegir el host de retorno bajo control del piloto. Configurar `YOUTUBE_APP_RETURN=https://HOST/library/youtube/return`. Si el backend sirve ese host, `YOUTUBE_ANDROID_SHA256` admite las huellas de los certificados autorizados separadas por coma, con octetos hexadecimales separados por dos puntos. El backend sirve `/.well-known/assetlinks.json` y la página de regreso manual. Si el host de retorno es otro, servir ambos recursos en ese host. Comprobar que el JSON responda con HTTP 200 directo, sin autenticación ni redirección. [Android App Links](https://developer.android.com/training/app-links/configure-assetlinks)
3. Preparar un archivo local para el build a partir de `mobile/config/firebase.android.example.json`, con los valores del Firebase de ensayo y el `API_BASE_URL` HTTPS de ese backend. Incluir `"YOUTUBE_LIBRARY_ENABLED": "true"` y `"YOUTUBE_APP_LINK_HOST": "HOST"`. Usar exclusivamente el nombre de dominio en ese último campo. El piloto está desactivado por defecto.
4. Desde `mobile/`, compilar el APK de prueba para un emulador o un teléfono aparte con `flutter build apk --debug --dart-define-from-file=RUTA_AL_JSON`. La firma de ese APK también debe estar autorizada para el login Firebase y para el dominio de prueba. Los secretos de OAuth web y las claves de cifrado pertenecen al backend.

## Comprobar el Mysic 0.11.1 instalado

En Windows, conectar el teléfono por USB, autorizar la depuración para ese equipo y ejecutar en PowerShell con Platform Tools y las Android Build Tools disponibles. El bloque solo consulta el paquete y copia su APK base al equipo.

```powershell
$pkg = 'com.mysic.mysic'
adb devices
adb shell dumpsys package $pkg | Select-String 'versionName=|versionCode='
$base = adb shell pm path $pkg | Where-Object { $_.Trim().EndsWith('/base.apk') } | Select-Object -First 1
if (-not $base) { throw 'El teléfono no devolvió la ruta del APK base.' }
adb pull ($base.Trim() -replace '^package:', '') .\mysic-0.11.1-base.apk
apksigner verify --print-certs .\mysic-0.11.1-base.apk
```

Si `apksigner` está fuera del PATH, ejecutar `apksigner.bat` desde la carpeta de versión instalada en `Android\Sdk\build-tools`. Para validar una actualización sobre esa instalación, cotejar paquete, certificado SHA-256 y un `versionCode` efectivo mayor en el APK candidato. El certificado histórico del repositorio y el de un APK de CI son únicamente referencias. La clave de firma se conserva en el equipo que produce el APK. [apksigner](https://developer.android.com/tools/apksigner)

## Aceptación en el dispositivo

- En Android 12 o posterior usar `adb shell pm verify-app-links --re-verify com.mysic.mysic` y luego `adb shell pm get-app-links com.mysic.mysic`. Esperar el estado `verified` en el dominio del piloto. [Verificar enlaces de la app](https://developer.android.com/training/app-links/verify-applinks)
- Medir desde **Vincular YouTube** hasta la primera página visible, primero con Mysic en memoria y luego recreando el proceso mientras el navegador sigue abierto. Probar también el regreso manual y un retorno duplicado.
- Abrir una playlist privada de cada canal autorizado, avanzar hasta la última página de la lista de 68 elementos y comprobar el cambio de canal, la cancelación, el reintento al recuperar conexión y la desvinculación conservando la sesión Firebase.
- Registrar canal de ensayo, conteos y tiempos. Las capturas y los registros de aceptación deben excluir cabeceras de autorización, códigos y referencias del retorno.
