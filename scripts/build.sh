#!/usr/bin/env bash
# Build the HoloCraft APK. Run all steps, or name the ones you want:
#   scripts/build.sh                 # atumvr visor addon mods pojlib unity
#   scripts/build.sh pojlib unity
#   scripts/build.sh install         # adb install the last APK
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MC=1.20.1
UNITY="${UNITY:-/Applications/Unity/Hub/Editor/6000.4.10f1/Unity.app/Contents/MacOS/Unity}"
OUT="${OUT:-$ROOT/outputs}"
APK="$OUT/HoloCraft-$MC.apk"
MIN_FREE_GB="${MIN_FREE_GB:-5}"

log() { printf '\n== %s\n' "$*"; }

check_disk() {
  local free_gb
  free_gb=$(df -Pk "$ROOT" | awk 'NR==2 { print int($4 / 1048576) }')
  if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
    echo "Only ${free_gb} GB free, need ${MIN_FREE_GB}. Stopping." >&2
    exit 1
  fi
}

atumvr() {
  log "AtumVR -> mavenLocal"
  (cd "$ROOT/AtumVR" && ./gradlew publishToMavenLocal)
}

visor() {
  log "Visor $MC"
  (cd "$ROOT/Visor" && ./gradlew ":visor-fabric:$MC:build")
}

addon() {
  log "HoloCraft MR add-on"
  (cd "$ROOT/HoloCraft-MR" && ./gradlew build -PvisorPath="$ROOT/Visor")
}

mods() {
  log "Copying mods into Pojlib"
  local dest="$ROOT/Pojlib/src/main/assets/mods"
  local visor_jar addon_jar
  visor_jar=$(ls "$ROOT"/Visor/visor-fabric/versions/$MC/build/libs/Visor-*+mc$MC-fabric.jar | head -n1)
  addon_jar=$(ls "$ROOT"/HoloCraft-MR/build/libs/HoloCraftMR-*.jar | grep -v -- '-sources' | head -n1)
  cp "$visor_jar" "$dest/Visor.jar"
  cp "$addon_jar" "$dest/HoloCraftMR.jar"
  echo "$(basename "$visor_jar") -> Visor.jar"
  echo "$(basename "$addon_jar") -> HoloCraftMR.jar"
}

pojlib() {
  log "Pojlib release AAR"
  (cd "$ROOT/Pojlib" && ./gradlew assembleRelease)
  cp "$ROOT/Pojlib/build/outputs/aar/Pojlib-release.aar" \
     "$ROOT/QCXR-XR-Wrapper/Assets/Plugins/Android/Pojlib-release.aar"
}

unity() {
  log "Unity Android build"
  [ -x "$UNITY" ] || { echo "Unity not found at $UNITY (set UNITY=...)" >&2; exit 1; }
  mkdir -p "$ROOT/logs" "$OUT"
  # The editor build method writes to <wrapper>/../../outputs, so move it after.
  local unity_out
  unity_out="$(cd "$ROOT/.." && pwd)/outputs/HoloCraft-$MC.apk"
  "$UNITY" -batchmode -quit \
    -projectPath "$ROOT/QCXR-XR-Wrapper" \
    -buildTarget Android \
    -executeMethod QuestCraftVisorBuild.BuildAndroid \
    -logFile "$ROOT/logs/unity.log"
  if [ "$unity_out" != "$APK" ]; then
    mv -f "$unity_out" "$APK"
  fi
  echo "APK: $APK"
}

install() {
  log "Installing on headset"
  adb install -r "$APK"
}

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(atumvr visor addon mods pojlib unity)

for step in "${steps[@]}"; do
  case "$step" in
    atumvr|visor|addon|mods|pojlib|unity|install) ;;
    *) echo "Unknown step: $step" >&2; exit 1 ;;
  esac
done

for step in "${steps[@]}"; do
  [ "$step" = install ] || [ "$step" = mods ] || check_disk
  "$step"
done
