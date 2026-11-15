#!/usr/bin/env bash
# Publish the reviewed Sprint 10 implementation, without closing/tagging it.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
[[ "$(git branch --show-current)" == main ]] || {
  echo 'Se esperaba la rama main. No se cambió de rama.' >&2
  exit 1
}
case "$(git remote get-url origin)" in
  git@github.com:MarckDL/Mysic_App.git|https://github.com/MarckDL/Mysic_App.git) ;;
  *) echo 'El remoto no coincide con MarckDL/Mysic_App.' >&2; exit 1 ;;
esac
git diff --cached --quiet || {
  echo 'Ya hay cambios preparados en el índice. Revísalos antes de publicar.' >&2
  exit 1
}
files=(
  backend/prisma/schema.prisma
  backend/prisma/migrations/20261115020000_create_history/migration.sql
  backend/src/app.ts
  backend/src/infrastructure/database/prisma-history-repository.ts
  backend/src/modules/history/application/history-service.ts
  backend/src/modules/history/domain/history.ts
  backend/src/modules/history/presentation/history.routes.ts
  backend/tests/history.postgres.test.ts
  backend/tests/history.routes.test.ts
  backend/tests/history.test.ts
  docs/01-arquitectura.md
  docs/02-base-de-datos.md
  docs/03-requisitos.md
  docs/04-sprints-roadmap.md
  docs/16-plan-sprint-10.md
  mobile/pubspec.yaml
  mobile/android/app/src/main/kotlin/com/mysic/mysic/MainActivity.kt
  mobile/lib/app/router/catalog_navigator.dart
  mobile/lib/features/home/presentation/home_screen.dart
  mobile/lib/features/playback/application/playback_providers.dart
  mobile/lib/features/playback/application/track_playback_controller.dart
  mobile/lib/features/history/application/listening_tracker.dart
  mobile/lib/features/history/presentation/history_screen.dart
  mobile/test/listening_tracker_test.dart
  mobile/test/queue_playback_test.dart
  mobile/test/support/fake_track_audio_engine.dart
  tool/device-sprint-10.sh
  tool/verify-sprint-10.sh
  tool/publish-sprint-10.sh
  tool/install-sprint-10-cloud.sh
)
git diff --check
git add -- "${files[@]}"
git diff --cached --stat
if ! git diff --cached --quiet; then
  git commit -m "${1:-feat(history): add private listening history and Android tracking}"
fi
git push origin main
git log -1 --format='Commit publicado: %H'
echo 'Push completado. Falta comprobar CI y el despliegue de Render antes de probar HTTPS.'
