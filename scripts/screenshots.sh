#!/usr/bin/env bash
# Boots a small and a large iPhone simulator, installs the Debug build and captures key
# screens in dark and light appearance using sample data (launch arguments, see LaunchOptions.swift).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="$ROOT/build/dd/Build/Products/Debug-iphonesimulator/Blith.app"
OUT="$ROOT/build/screenshots"
BUNDLE="com.blith.health"
mkdir -p "$OUT"
[ -d "$APP" ] || { echo "App not found at $APP"; exit 1; }

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("platform")=="iOS" and r.get("isAvailable")]
print(sorted(rs,key=lambda r:[int(x) for x in r["version"].split(".")])[-1]["identifier"])')
echo "Runtime: $RUNTIME"

# Pick a small and a large iPhone among devices that exist for this runtime.
pick_device() { # $1 = small|large -> "udid|name"
  xcrun simctl list devices available -j | python3 -c "
import json,sys
devs=[d for d in json.load(sys.stdin)['devices'].get('$RUNTIME',[]) if d['name'].startswith('iPhone')]
small=[d for d in devs if 'SE' in d['name'] or d['name'].endswith('e') or 'mini' in d['name']]
large=[d for d in devs if 'Pro Max' in d['name'] or 'Plus' in d['name']]
pick=(small if '$1'=='small' else large) or devs
d=pick[-1] if '$1'=='small' else pick[0]
print(d['udid']+'|'+d['name'])"
}
SMALL=$(pick_device small)
LARGE=$(pick_device large)
echo "Devices: $SMALL / $LARGE"

shoot() { # udid label args...
  local udid="$1" label="$2"; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE" "$@" >/dev/null
  sleep 7
  xcrun simctl io "$udid" screenshot "$OUT/$label.png" >/dev/null 2>&1
  echo "  $label"
}

now() { python3 -c 'import time; print(f"{time.time():.2f}")'; }

# A real screen recording of the app on the large simulator (light appearance, sample data):
# one launch per scene. tour-marks.txt lists when each scene was launched, in seconds from the start.
record_tour() { # udid demo-args...
  local udid="$1"; shift
  local marks="$OUT/tour-marks.txt" pid t0
  : > "$marks"
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$OUT/tour-raw.mp4" >/dev/null 2>&1 &
  pid=$!
  sleep 3
  t0=$(now)
  scene() { # label seconds args...
    local label="$1" wait="$2"; shift 2
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    echo "$(python3 -c "print(f'{$(now) - $t0:.2f}')") $label" >> "$marks"
    xcrun simctl launch "$udid" "$BUNDLE" "$@" >/dev/null
    sleep "$wait"
  }
  scene today 10 "$@" -BlithTab today
  scene today-live 8 "$@" -BlithTab today -BlithScrollTo live -BlithLiveBPM 74
  scene today-monitor 7 "$@" -BlithTab today -BlithScrollTo monitor
  scene activity 8 "$@" -BlithTab walk -BlithPeriod month
  scene sleep 7 "$@" -BlithTab sleep
  scene sleep-stages 7 "$@" -BlithTab sleep -BlithScrollTo stages
  scene body 10 "$@" -BlithTab body -BlithBodyYaw 28
  scene body-focus 8 "$@" -BlithTab body -BlithBodyFocus sample-ankle
  scene body-muscle 8 "$@" -BlithTab body -BlithBodyLayer muscle -BlithBodyYaw -20
  scene ask 14 "$@" -BlithTab ask -BlithAskScript YES
  scene ask-bodynote 10 "$@" -BlithTab ask -BlithAskNote YES
  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "  tour-raw.mp4 ($(cat "$marks" | wc -l | tr -d ' ') scenes)"
}

for DEV in "$SMALL" "$LARGE"; do
  UDID="${DEV%%|*}"
  NAME=$(echo "${DEV#*|}" | tr -cd '[:alnum:]')
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$UDID" "$APP"
  echo "$NAME ($UDID)"
  DEMO=(-BlithDemo balanced -BlithAIConsent NO -BlithClockHour 15.5)
  xcrun simctl ui "$UDID" appearance dark
  shoot "$UDID" "$NAME-01-today" "${DEMO[@]}" -BlithTab today
  shoot "$UDID" "$NAME-02-today-monitor" "${DEMO[@]}" -BlithTab today -BlithScrollTo monitor
  shoot "$UDID" "$NAME-02b-today-live" "${DEMO[@]}" -BlithTab today -BlithScrollTo live -BlithLiveBPM 74
  shoot "$UDID" "$NAME-02c-today-live-hard" "${DEMO[@]}" -BlithTab today -BlithScrollTo live -BlithLiveBPM 152
  shoot "$UDID" "$NAME-03-today-movement" "${DEMO[@]}" -BlithTab today -BlithScrollTo movement
  shoot "$UDID" "$NAME-04-activity" "${DEMO[@]}" -BlithTab walk -BlithPeriod month
  shoot "$UDID" "$NAME-05-sleep" "${DEMO[@]}" -BlithTab sleep
  shoot "$UDID" "$NAME-06-sleep-stages" "${DEMO[@]}" -BlithTab sleep -BlithScrollTo stages
  # Warm up SceneKit's shader cache so the first 3D shot isn't captured mid-compile.
  xcrun simctl launch "$UDID" "$BUNDLE" "${DEMO[@]}" -BlithTab body >/dev/null; sleep 15
  shoot "$UDID" "$NAME-07-body" "${DEMO[@]}" -BlithTab body -BlithBodyYaw 28
  shoot "$UDID" "$NAME-08-body-focus" "${DEMO[@]}" -BlithTab body -BlithBodyFocus sample-ankle
  shoot "$UDID" "$NAME-09-body-muscle" "${DEMO[@]}" -BlithTab body -BlithBodyLayer muscle -BlithBodyYaw -20
  shoot "$UDID" "$NAME-10-body-muscle-back" "${DEMO[@]}" -BlithTab body -BlithBodyLayer muscle -BlithBodyYaw 180
  shoot "$UDID" "$NAME-11-readiness" "${DEMO[@]}" -BlithSheet readiness
  shoot "$UDID" "$NAME-12-ask" "${DEMO[@]}" -BlithTab ask -BlithAskScript YES
  shoot "$UDID" "$NAME-12b-ask-bodynote" "${DEMO[@]}" -BlithTab ask -BlithAskNote YES
  if [ "$UDID" = "${SMALL%%|*}" ]; then
    shoot "$UDID" "$NAME-13-vital" "${DEMO[@]}" -BlithSheet vital
    shoot "$UDID" "$NAME-14-activity-day" "${DEMO[@]}" -BlithTab walk -BlithPeriod month -BlithWalkDaysAgo 40
    shoot "$UDID" "$NAME-15-achievements" "${DEMO[@]}" -BlithSheet achievements
    shoot "$UDID" "$NAME-16-newuser" -BlithDemo newUser -BlithClockHour 15.5 -BlithTab today
    shoot "$UDID" "$NAME-16b-nowatch" -BlithDemo partialPermissions -BlithClockHour 15.5 -BlithTab today
    shoot "$UDID" "$NAME-17-onboarding" -BlithResetOnboarding YES
  fi
  # Light appearance: the same key screens, so both modes are checked every run.
  xcrun simctl ui "$UDID" appearance light
  shoot "$UDID" "$NAME-L01-today" "${DEMO[@]}" -BlithTab today
  shoot "$UDID" "$NAME-L04-activity" "${DEMO[@]}" -BlithTab walk -BlithPeriod month
  shoot "$UDID" "$NAME-L05-sleep" "${DEMO[@]}" -BlithTab sleep
  shoot "$UDID" "$NAME-L12-ask" "${DEMO[@]}" -BlithTab ask -BlithAskScript YES
  shoot "$UDID" "$NAME-L12b-ask-bodynote" "${DEMO[@]}" -BlithTab ask -BlithAskNote YES
  # The tour video costs about 2 build minutes, so it only runs when asked (RECORD_TOUR=1).
  if [ "${RECORD_TOUR:-0}" = "1" ] && [ "$UDID" = "${LARGE%%|*}" ]; then record_tour "$UDID" "${DEMO[@]}"; fi
  xcrun simctl ui "$UDID" appearance dark
  # Keep any crash reports and SceneKit/Metal errors from this device for debugging.
  xcrun simctl spawn "$UDID" log show --last 20m --style compact --predicate 'process == "Blith" AND (messageType == error OR messageType == fault)' \
    > "$OUT/$NAME-log.txt" 2>/dev/null || true
  cp ~/Library/Logs/DiagnosticReports/Blith* "$OUT/" 2>/dev/null || true
  xcrun simctl shutdown "$UDID" || true
done
ls -1 "$OUT"
