# Biblioteca de YouTube en Android

En el piloto, Biblioteca abre la autorización en el navegador. Al volver, Mysic comprueba el intento con la sesión Firebase que lo inició, confirma el canal y carga sus playlists. Cuenta permite cambiar el canal y desvincularlo. Cuando Android mantiene el navegador abierto, se puede volver a Mysic, tocar **Comprobar vinculación** y confirmar el canal mostrado. Un cambio de canal requiere confirmación expresa. La importación Takeout conserva su entrada propia.

## Preparar el entorno de prueba

1. Configurar un backend HTTPS con las variables de [OAuth](youtube-oauth.md), las migraciones y los endpoints de [biblioteca](youtube-library.md). En Google Cloud registrar la URI exacta de `YOUTUBE_OAUTH_CALLBACK`.
2. Elegir el host de retorno bajo control del piloto. Configurar `YOUTUBE_APP_RETURN=https://HOST/library/youtube/return`. Si el backend sirve ese host, `YOUTUBE_ANDROID_SHA256` admite las huellas de los certificados autorizados separadas por coma, con octetos hexadecimales separados por dos puntos. El backend sirve `/.well-known/assetlinks.json` y la página de regreso manual. Si el host de retorno es otro, servir ambos recursos en ese host. Comprobar que el JSON responda con HTTP 200 directo, sin autenticación ni redirección. [Android App Links](https://developer.android.com/training/app-links/configure-assetlinks)
3. Preparar un archivo local para el build a partir de `mobile/config/firebase.android.example.json`, con los valores del Firebase de ensayo y el `API_BASE_URL` HTTPS de ese backend. Incluir `"YOUTUBE_LIBRARY_ENABLED": "true"` y `"YOUTUBE_APP_LINK_HOST": "HOST"`. Usar exclusivamente el nombre de dominio en ese último campo. El piloto está desactivado por defecto.
4. Desde `mobile/`, compilar el APK de prueba para un emulador o un teléfono aparte con `flutter build apk --debug --dart-define-from-file=RUTA_AL_JSON`. La firma de ese APK también debe estar autorizada para el login Firebase y para el dominio de prueba. Los secretos de OAuth web y las claves de cifrado pertenecen al backend.

## Comprobar la actualización de 4019 a 4020

En Windows, conectar el teléfono por USB, autorizar la depuración para ese equipo y ejecutar en PowerShell con Platform Tools y las Android Build Tools disponibles. Primero comprobar la versión y comparar los certificados.

```powershell
$pkg = 'com.mysic.mysic'
adb devices
adb shell dumpsys package $pkg | Select-String 'versionName=|versionCode='
$base = adb shell pm path $pkg | Where-Object { $_.Trim().EndsWith('/base.apk') } | Select-Object -First 1
if (-not $base) { throw 'El teléfono no devolvió la ruta del APK base.' }
adb pull ($base.Trim() -replace '^package:', '') .\Mysic-4019-base.apk
apksigner verify --print-certs .\Mysic-4019-base.apk
apksigner verify --print-certs .\Mysic-0.11.2-rc3.apk
```

Si el paquete es `com.mysic.mysic`, las huellas SHA-256 coinciden y el candidato tiene `versionCode 4020`, instalar como actualización.

```powershell
adb install -r .\Mysic-0.11.2-rc3.apk
adb shell dumpsys package $pkg | Select-String 'versionName=|versionCode='
```

Al terminar se espera `versionName 0.11.2-rc.3` y la sesión de Mysic abierta. Si `apksigner` está fuera del PATH, ejecutar `apksigner.bat` desde la carpeta de versión instalada en `Android\Sdk\build-tools`. [apksigner](https://developer.android.com/tools/apksigner)

## Validación del candidato 4020

- Flutter completó 106 pruebas, incluidas 13 de biblioteca conectada. Pasaron el análisis estático, el formato y las 5 pruebas de configuración.
- El backend completó 246 pruebas con las 9 migraciones aplicadas en PostgreSQL local. La cobertura incluye denegación de Google, retoma manual, intentos duplicados, reemplazo autorizado y descarte de lecturas privadas en vuelo al desvincular.
- El APK se compiló en modo release para ARM64, ARMv7 y x86-64. `apksigner` confirmó que comparte el certificado del APK 4019. El manifiesto declaró el App Link con verificación automática y el dominio publicó la asociación para ese certificado.
- El emulador por software de Android 11 respondió por ADB, pero su gestor de paquetes quedó indisponible durante el arranque. La instalación de 4020 sobre 4019 y el recorrido con cuentas reales quedan para el teléfono.
- SHA-256 del archivo `Mysic-0.11.2-rc3.apk` · `7893bcc94b3c9cf7d9ccc0dd6d3dbaa23bc99af902bfe5e0bc2998e4ce1abf0c`.

## Aceptación en el dispositivo

- En Android 12 o posterior usar `adb shell pm verify-app-links --re-verify com.mysic.mysic` y luego `adb shell pm get-app-links com.mysic.mysic`. Esperar el estado `verified` en el dominio del piloto. [Verificar enlaces de la app](https://developer.android.com/training/app-links/verify-applinks)

La versión 4019 mostró las cinco playlists de **rawr**, incluidas las privadas, en el teléfono del propietario. Desde **Biblioteca → Biblioteca de YouTube → Opciones del vínculo** se puede iniciar otro intento con **Cambiar cuenta de YouTube** o retirar el acceso con **Desvincular YouTube**.

| Caso | Acción | Resultado esperado |
| --- | --- | --- |
| Actualización | Instalar 4020 sobre 4019 y abrir Mysic. | La sesión sigue abierta y la biblioteca vuelve a mostrar las cinco playlists de rawr. |
| Cancelación | Iniciar el cambio de cuenta y cancelar en Google. Si se sale con Atrás y el intento sigue activo, tocar **Cancelar vinculación** en Mysic. | Se cierra el intento y rawr conserva su vínculo y sus playlists. |
| Cierre del proceso | Iniciar otro intento. Con Google abierto, retirar Mysic de Recientes o, por USB, ejecutar `adb shell am kill com.mysic.mysic` cuando esté en segundo plano. Completar Google y tocar **Volver a Mysic** si aparece. | Mysic recupera el intento de la sesión que lo inició y muestra el canal para confirmar cuando corresponde. |
| Regreso manual y duplicado | Terminar en Google, volver desde Recientes sin tocar el enlace y usar **Comprobar vinculación**. Tras confirmar, abrir de nuevo **Volver a Mysic** si la página sigue abierta. | Se confirma una sola vez. El segundo retorno conserva el canal y la pantalla sin abrir una autorización nueva. |
| Red interrumpida | Apagar Wi-Fi y datos antes de iniciar el intento o confirmar el canal. Restaurarlos y usar **Volver a abrir Google**, **Comprobar vinculación** o **Confirmar este canal**, según la pantalla. | Aparece un aviso de conexión y el flujo se puede retomar. Al confirmar un reemplazo, las listas del canal anterior quedan ocultas hasta verificar el canal vigente. |
| Cambio de canal | Autorizar otro canal de prueba y tocar **Reemplazar por este canal**. Abrir una de sus playlists privadas. | Biblioteca muestra solo las playlists del nuevo canal. Desaparecen las privadas de rawr. |
| Desvinculación | Desvincular el canal y volver a **Cuenta** y a **Biblioteca**. Si se interrumpe el envío, restaurar la red y tocar **Reintentar desvinculación**. | Desaparecen las playlists de YouTube. Cuenta conserva el perfil y Biblioteca conserva las listas guardadas en Mysic. |
| Regresión de reproducción | Poner una canción en cola, abrir letras y volver a Inicio, Buscar y Biblioteca. | Funcionan el reproductor, el minirreproductor, las letras, la cola y la barra inferior. |

Registrar canal, conteo y tiempo hasta la primera página. Si está disponible la playlist de 68 elementos, cargar la segunda página y comprobar que se muestran las 50 primeras filas y las 18 restantes. Las capturas y los registros deben excluir cabeceras de autorización, códigos y referencias del retorno.

## Modo YouTube Music

Consulta [el diseño, la configuración de ensayo y los criterios de validación del modo YouTube Music](youtube-music-mode.md). La ficha anterior cubre la biblioteca del canal autorizada en 4020.
