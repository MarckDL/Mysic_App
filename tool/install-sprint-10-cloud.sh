#!/usr/bin/env bash
# Run only after the history backend deployment is live.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
device_serial="${1:-kfz5cugawodihaj7}"
adb_bin="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/home/dino/Android/Sdk}}/platform-tools/adb"
api_base='https://mysic-api-k03u.onrender.com'
report_dir="$(mktemp -d "${TMPDIR:-/tmp}/mysic-sprint10-cloud-apk.XXXXXX")"
[[ -x "$adb_bin" ]] || { echo "No se encontró ADB: $adb_bin" >&2; exit 1; }
if [[ "$device_serial" == emulator ]]; then
  mapfile -t emulators < <("$adb_bin" devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1}')
  if ((${#emulators[@]} != 1)); then
    echo 'Abre un solo emulador en Android Studio y espera a que termine de iniciar.' >&2
    echo 'También puedes pasar su serial exacto como argumento de este script.' >&2
    exit 1
  fi
  device_serial="${emulators[0]}"
fi
[[ "$($adb_bin -s "$device_serial" get-state)" == device ]]
[[ "$($adb_bin -s "$device_serial" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]] || {
  echo 'Espera a que Android termine de iniciar y vuelve a ejecutar el script.' >&2
  exit 1
}
abi="$("$adb_bin" -s "$device_serial" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$abi" in
  arm64-v8a) target_platform=android-arm64; apk_abi=arm64-v8a ;;
  x86_64) target_platform=android-x64; apk_abi=x86_64 ;;
  *) echo "Arquitectura no contemplada por este instalador: $abi" >&2; exit 1 ;;
esac
echo "Destino: $device_serial ($abi). Backend: $api_base"
# The route check verifies availability and authentication, not DB migration state.
status="$(curl --silent --show-error --max-time 90 \
  --output "$report_dir/history-unauthenticated.json" --write-out '%{http_code}' \
  "$api_base/api/v1/history")"
if [[ "$status" != 401 ]]; then
  echo "La ruta de historial no está lista: HTTP $status. No se instaló el APK." >&2
  echo "Registros: $report_dir"
  exit 1
fi
cd "$project_dir/mobile"
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze 2>&1 | tee "$report_dir/analyze.log"
flutter test --no-enable-impeller 2>&1 | tee "$report_dir/tests.log"
flutter build apk --release --split-per-abi --target-platform "$target_platform" \
  --dart-define-from-file=config/firebase.android.json \
  --dart-define=API_BASE_URL="$api_base" 2>&1 | tee "$report_dir/build.log"
apk="build/app/outputs/flutter-apk/app-$apk_abi-release.apk"
stat --format='APK: %s bytes' "$apk"
sha256sum "$apk" | tee "$report_dir/apk.sha256"
"$adb_bin" -s "$device_serial" install -r "$apk"
"$adb_bin" -s "$device_serial" shell am force-stop com.mysic.mysic
"$adb_bin" -s "$device_serial" shell am start -n com.mysic.mysic/.MainActivity
echo "Instalación completada. Registros: $report_dir"
echo 'Mysic usa Render HTTPS; no necesita adb reverse ni backend local.'
