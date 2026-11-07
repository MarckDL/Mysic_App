# Despliegue preliminar del backend

Este procedimiento forma parte del Sprint 07. Su objetivo es verificar Mysic desde
una red externa; el endurecimiento final sigue perteneciendo a los Sprints 12 a 14.

## Arquitectura

- API Express persistente en Render mediante `render.yaml`.
- PostgreSQL administrado por Supabase.
- Firebase Authentication y Firebase Admin para verificar cada ID token.
- APK privado compilado con la URL HTTPS entregada por Render.
- Flutter nunca accede directamente a PostgreSQL ni recibe secretos administrativos.

## Preparación segura en Render

1. Conectar el repositorio `MarckDL/Mysic_App` como Blueprint.
2. Revisar el servicio `mysic-api`, región Virginia y rama `main`.
3. Completar las variables solicitadas por el Blueprint:
   - `FIREBASE_PROJECT_ID`.
   - `DATABASE_URL`, conexión de runtime Supabase.
   - `DIRECT_URL`, conexión apta para migraciones Prisma.
4. Añadir en **Environment → Secret Files**:
   - `firebase-admin.json`, credencial del mismo proyecto Firebase.
   - `supabase-ca.crt`, certificado CA usado para PostgreSQL.
5. No copiar esos valores al Blueprint, GitHub, APK, logs ni documentación.

Render monta los archivos secretos bajo `/etc/secrets/`. El Blueprint configura las
rutas esperadas mediante `GOOGLE_APPLICATION_CREDENTIALS` y
`DATABASE_SSL_CA_FILE`.

## Construcción y migración

El alojamiento ejecuta:

```text
pnpm install --frozen-lockfile && pnpm db:generate && pnpm db:deploy && pnpm build
pnpm start
```

`db:deploy` solo aplica migraciones versionadas. En el plan gratuito se ejecuta
durante la construcción porque Render reserva el paso `preDeployCommand` para
servicios pagados. No utiliza `migrate dev`, no borra datos ni modifica manualmente
producción.

## Verificación

### Evidencia del 7 de noviembre de 2026

- Blueprint: `Mysic Sprint 7`.
- Servicio: `mysic-api-k03u`, plan gratuito, región Virginia.
- URL pública: `https://mysic-api-k03u.onrender.com`.
- Commit desplegado: `8b88fb0e26f75d89e890b8fee3e0cb7d8912031e`.
- Migraciones Prisma: 3 encontradas, ninguna pendiente.
- `GET /api/v1/health`: `200 {"status":"ok"}`.
- `GET /api/v1/playlists` sin token: `401 UNAUTHENTICATED`.
- Token inválido en `/api/v1/auth/session`: `401 UNAUTHENTICATED`.
- APK debug compilado con la URL pública. La prueba autenticada y de reproducción
  permanece pendiente de instalarlo en el dispositivo físico.

Los primeros intentos detectaron dos problemas de configuración ya corregidos:
`corepack enable` no podía modificar `/usr/bin` en Render y las variables de
conexión del servicio estaban vacías. El despliegue vigente terminó en estado
`live` después de usar el `pnpm` provisto por Render y sincronizar las variables.

1. Confirmar `200 {"status":"ok"}` en `https://<servicio>/api/v1/health`.
2. Confirmar que una ruta privada sin token devuelve `401`.
3. Desde `mobile/`, compilar el APK:

```text
flutter build apk --debug \
  --dart-define-from-file=config/firebase.android.json \
  --dart-define=API_BASE_URL=https://<servicio>
```

4. Desactivar `adb reverse` y el backend local.
5. Probar con datos móviles: login, búsqueda, reproducción superior a dos minutos,
   creación de playlist, incorporación, reordenamiento y recuperación tras reinicio.

## Limitaciones del plan gratuito

- La instancia puede suspenderse después de un periodo sin tráfico.
- El primer acceso puede tardar cerca de un minuto; el cliente remoto admite hasta
  75 segundos para esa conexión preliminar.
- El proxy de audio consume tráfico de entrada y salida del backend y puede superar
  las cuotas gratuitas.
- Para la demostración estable se debe usar una instancia siempre activa si las
  mediciones del Sprint 12 confirman cortes, arranques fríos o falta de capacidad.

El despliegue no se considera verificado hasta registrar URL, fecha, health check,
prueba autenticada y reproducción real desde una red externa, sin publicar secretos.
