#!/usr/bin/env bash
# Formal publication after automatic and assisted device acceptance.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
verified_sha=56718a56c9ffe175d4ad1d10216c023d2b3d38ec
sprint_tag=sprint-10-v0.10.1
[[ "$(git branch --show-current)" == main ]] || {
  echo 'Se esperaba main; no se cambió de rama.' >&2
  exit 1
}
case "$(git remote get-url origin)" in
  git@github.com:MarckDL/Mysic_App.git|https://github.com/MarckDL/Mysic_App.git) ;;
  *) echo 'El remoto no coincide con MarckDL/Mysic_App.' >&2; exit 1 ;;
esac
git diff --cached --quiet || {
  echo 'Hay cambios ya preparados en el índice: revísalos antes del cierre.' >&2
  exit 1
}
git diff --quiet "$verified_sha" -- backend mobile .github render.yaml || {
  echo 'El código cambió desde la versión validada. Repetir validación antes de cerrar.' >&2
  exit 1
}
git diff --check
bash -n tool/install-sprint-10-cloud.sh tool/close-sprint-10.sh
git add -- README.md docs/04-sprints-roadmap.md docs/16-plan-sprint-10.md \
  tool/install-sprint-10-cloud.sh tool/close-sprint-10.sh
git diff --cached --stat
if ! git diff --cached --quiet; then
  git commit -m "chore(sprint-10): complete listening history"
fi
git push origin main
closing_sha="$(git rev-parse HEAD)"
remote_head="$(git ls-remote origin refs/heads/main | cut -f1)"
[[ "$remote_head" == "$closing_sha" ]] || { echo 'HEAD remoto no verificado.' >&2; exit 1; }
if git show-ref --verify --quiet "refs/tags/$sprint_tag"; then
  [[ "$(git rev-parse "$sprint_tag^{commit}")" == "$closing_sha" ]] || {
    echo 'La etiqueta local ya existe en otro commit; no se reescribió.' >&2
    exit 1
  }
else
  git tag -a "$sprint_tag" -m 'Sprint 10 verified: listening history 0.10.1'
fi
git push origin "refs/tags/$sprint_tag"
remote_tag="$(git ls-remote origin "refs/tags/$sprint_tag^{}" | cut -f1)"
[[ "$remote_tag" == "$closing_sha" ]] || { echo 'Etiqueta remota no verificada.' >&2; exit 1; }
printf 'Cierre publicado y verificado: %s\nEtiqueta: %s\n' "$closing_sha" "$sprint_tag"
printf 'https://github.com/MarckDL/Mysic_App/releases/tag/%s\n' "$sprint_tag"
