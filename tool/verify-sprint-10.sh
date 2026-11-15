#!/usr/bin/env bash
# Run on the development host: bash tool/verify-sprint-10.sh
# Uses only a disposable PostgreSQL container; never reads backend/.env.
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for dependency in docker pnpm flutter dart python3 java; do
  command -v "$dependency" >/dev/null || {
    echo "Falta la herramienta requerida: $dependency" >&2
    exit 1
  }
done
docker info >/dev/null
report_dir="$(mktemp -d "${TMPDIR:-/tmp}/mysic-sprint10-validation.XXXXXX")"
container_id=''
cleanup() {
  if [[ -n "$container_id" ]]; then
    docker rm -f "$container_id" >/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

container_id="$(docker run -d --rm \
  -e POSTGRES_USER=mysic_test \
  -e POSTGRES_PASSWORD=mysic_test \
  -e POSTGRES_DB=mysic_test \
  -p 127.0.0.1::5432 postgres:17)"
ready=false
for ((attempt = 0; attempt < 60; attempt++)); do
  if docker exec "$container_id" pg_isready -U mysic_test -d mysic_test >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  docker logs "$container_id" >&2
  echo 'PostgreSQL no está disponible.' >&2
  exit 1
fi
binding="$(docker port "$container_id" 5432/tcp)"
test_port="${binding##*:}"
export TEST_DATABASE_URL="postgresql://mysic_test:mysic_test@127.0.0.1:${test_port}/mysic_test"
export DATABASE_URL="$TEST_DATABASE_URL"
export DIRECT_URL="$TEST_DATABASE_URL"

backend_checks() (
  set -e
  cd "$project_dir/backend"
  pnpm install --frozen-lockfile
  pnpm db:validate
  pnpm db:generate --no-hints
  pnpm db:deploy
  pnpm lint
  pnpm typecheck
  pnpm format:check
  pnpm test
  pnpm build
)
mobile_checks() (
  set -e
  cd "$project_dir/mobile"
  flutter pub get --enforce-lockfile
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze
  flutter test --no-enable-impeller
  python3 -m unittest discover -s tool -p 'test_*.py'
  flutter build apk --debug
  stat --format='APK debug: %s bytes' build/app/outputs/flutter-apk/app-debug.apk
  sha256sum build/app/outputs/flutter-apk/app-debug.apk
)

# Do not invoke functions in an if/|| condition: that disables Bash errexit
# inside them and could report a successful build after a failed test suite.
set +e
backend_checks 2>&1 | tee "$report_dir/backend.log"
backend_status=${PIPESTATUS[0]}
mobile_checks 2>&1 | tee "$report_dir/mobile.log"
mobile_status=${PIPESTATUS[0]}
set -e
printf 'Backend: %s\nFlutter/APK: %s\nLogs: %s\n' \
  "$backend_status" "$mobile_status" "$report_dir"
echo 'La aceptación física con dos cuentas/dispositivos se verifica por separado.'
if ((backend_status != 0 || mobile_status != 0)); then
  exit 1
fi
