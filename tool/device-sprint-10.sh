#!/usr/bin/env bash
# Interactive USB acceptance on the host, using disposable PostgreSQL.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
device_serial="${1:-kfz5cugawodihaj7}"
adb_bin="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/home/dino/Android/Sdk}}/platform-tools/adb"
api_port=33010
for dependency in docker pnpm flutter node curl; do
  command -v "$dependency" >/dev/null || { echo "Falta: $dependency" >&2; exit 1; }
done
[[ -x "$adb_bin" ]] || { echo "No se encontró ADB: $adb_bin" >&2; exit 1; }
[[ "$($adb_bin -s "$device_serial" get-state)" == device ]]
docker info >/dev/null
[[ -f "$project_dir/mobile/config/firebase.android.json" ]]
if "$adb_bin" -s "$device_serial" reverse --list | awk '{print $2}' | grep -qx "tcp:$api_port"; then
  echo "Ya existe un reverse en tcp:$api_port; no se reemplazó." >&2
  exit 1
fi
report_dir="$(mktemp -d "${TMPDIR:-/tmp}/mysic-sprint10-device.XXXXXX")"
container_id=''
backend_pid=''
reverse_added=false
cleanup() {
  if [[ -n "$backend_pid" ]]; then
    kill "$backend_pid" 2>/dev/null || true
    wait "$backend_pid" 2>/dev/null || true
  fi
  if [[ "$reverse_added" == true ]]; then
    "$adb_bin" -s "$device_serial" reverse --remove "tcp:$api_port" >/dev/null 2>&1 || true
  fi
  if [[ -n "$container_id" ]]; then
    docker exec "$container_id" psql -U mysic_test -d mysic_test -c \
      'SELECT count(*) AS sesiones, count(DISTINCT user_id) AS cuentas, min(listened_ms) AS minimo_ms, max(listened_ms) AS maximo_ms FROM mysic.listening_history;' \
      >"$report_dir/history-summary.txt" 2>&1 || true
    docker rm -f "$container_id" >/dev/null || true
  fi
  echo "Registros de prueba: $report_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
container_id="$(docker run -d --rm -e POSTGRES_USER=mysic_test \
  -e POSTGRES_PASSWORD=mysic_test -e POSTGRES_DB=mysic_test \
  -p 127.0.0.1::5432 postgres:17)"
ready=false
for ((attempt = 0; attempt < 60; attempt++)); do
  if docker exec "$container_id" pg_isready -U mysic_test -d mysic_test >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || { echo 'PostgreSQL no inició.' >&2; exit 1; }
binding="$(docker port "$container_id" 5432/tcp)"
export DATABASE_URL="postgresql://mysic_test:mysic_test@127.0.0.1:${binding##*:}/mysic_test"
export DIRECT_URL="$DATABASE_URL"
export DATABASE_SSL_CA_BASE64=''
export DATABASE_SSL_CA_FILE=''
export PORT="$api_port"
(
  cd "$project_dir/backend"
  pnpm db:generate --no-hints
  pnpm db:deploy
  pnpm build
) 2>&1 | tee "$report_dir/setup.log"
(
  cd "$project_dir/backend"
  exec node --env-file-if-exists=.env dist/server.js
) >"$report_dir/backend.log" 2>&1 &
backend_pid=$!
ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
  kill -0 "$backend_pid" 2>/dev/null || { cat "$report_dir/backend.log"; exit 1; }
  if grep -q '"event":"server_started"' "$report_dir/backend.log" &&
    curl -fsS --max-time 2 "http://127.0.0.1:$api_port/api/v1/health" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || { echo 'El backend no respondió.' >&2; exit 1; }
"$adb_bin" -s "$device_serial" reverse "tcp:$api_port" "tcp:$api_port"
reverse_added=true
(
  cd "$project_dir/mobile"
  flutter build apk --debug --no-pub --build-number=2010 \
    --dart-define-from-file=config/firebase.android.json \
    --dart-define=API_BASE_URL="http://127.0.0.1:$api_port"
) 2>&1 | tee "$report_dir/apk.log"
"$adb_bin" -s "$device_serial" install -r "$project_dir/mobile/build/app/outputs/flutter-apk/app-debug.apk"
"$adb_bin" -s "$device_serial" shell am start -n com.mysic.mysic/.MainActivity
cat <<'MESSAGE'

PRUEBA USB LISTA. Mantén el cable conectado y esta terminal abierta.
La app usa la base temporal; el historial de Supabase no aparecerá aquí.
1. Inicia sesión con Google. Busca una canción de más de un minuto.
2. Escucha 10 segundos y selecciona otra: la primera no debe aparecer en Mi historial.
3. Escucha la segunda 40 segundos y pausa. Debe aparecer una sola sesión.
4. Reanuda 15 segundos y pausa: debe continuar siendo una sola sesión.
5. Prueba segundo plano y seek: saltar al final no debe sumar ese tiempo.
6. Cierra sesión, entra con otra cuenta y comprueba que no ve el historial anterior.
7. Vuelve a la primera cuenta y comprueba que recupera su historial.
8. Cierra y reabre Mysic, sin terminar este script, y comprueba persistencia.
Comunica cada resultado. Estas comprobaciones son manuales; el script no las declara aprobadas.
No desconectes USB para simular una caída: también perderías el transporte del backend.
Para finalizar pulsa Enter: se detendrán el backend y la base temporal.
MESSAGE
read -r
