#!/usr/bin/env bash
# Build the Plinth APK. Run all steps, or name the ones you want:
#   scripts/build.sh                 # atumvr visor addon mods pojlib unity
#   scripts/build.sh pojlib unity
#   scripts/build.sh install         # adb install the last APK
#   scripts/build.sh visor addon server   # Fabric dedicated server zip
#   scripts/build.sh --no-addon      # plain QuestCraft + Visor, no add-on (or NO_ADDON=1)
set -euo pipefail

NO_ADDON="${NO_ADDON:-0}"
if [ "${1:-}" = --no-addon ]; then NO_ADDON=1; shift; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MC=1.20.1
UNITY="${UNITY:-/Applications/Unity/Hub/Editor/6000.4.10f1/Unity.app/Contents/MacOS/Unity}"
OUT="${OUT:-$ROOT/outputs}"
if [ "$NO_ADDON" = 1 ]; then
  APK="$OUT/QuestCraft-Visor-$MC.apk"
else
  APK="$OUT/Plinth-$MC.apk"
fi
SERVER_ZIP="$OUT/Plinth-Server-$MC.zip"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags 2>/dev/null || echo "dev-$(git -C "$ROOT" rev-parse --short HEAD)")}"

# Server versions. Loader matches what Visor builds against, fabric-api what
# both Visor and the add-on depend on.
FABRIC_LOADER="${FABRIC_LOADER:-0.16.14}"
FABRIC_INSTALLER="${FABRIC_INSTALLER:-1.1.2}"
FABRIC_API="${FABRIC_API:-0.92.3+$MC}"

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
  (cd "$ROOT/AtumVR" && sh ./gradlew publishToMavenLocal)
}

visor() {
  log "Visor $MC"
  (cd "$ROOT/Visor" && sh ./gradlew --configure-on-demand ":visor-fabric:$MC:build")
}

addon() {
  log "Plinth add-on"
  (cd "$ROOT/HoloCraft-MR" && sh ./gradlew build -PvisorPath="$ROOT/Visor")
}

mods() {
  log "Copying mods into Pojlib"
  local dest="$ROOT/Pojlib/src/main/assets/mods"
  local visor_jar addon_jar
  visor_jar=$(ls "$ROOT"/Visor/visor-fabric/versions/$MC/build/libs/Visor-*+mc$MC-fabric.jar | head -n1)
  cp "$visor_jar" "$dest/Visor.jar"
  echo "$(basename "$visor_jar") -> Visor.jar"
  if [ "$NO_ADDON" = 1 ]; then
    rm -f "$dest/Plinth.jar" "$dest/HoloCraftMR.jar"
    echo "No add-on"
    return
  fi
  addon_jar=$(ls "$ROOT"/HoloCraft-MR/build/libs/*.jar | grep -v -- '-sources' | head -n1)
  cp "$addon_jar" "$dest/Plinth.jar"
  echo "$(basename "$addon_jar") -> Plinth.jar"
}

pojlib() {
  log "Pojlib release AAR"
  (cd "$ROOT/Pojlib" && sh ./gradlew assembleRelease)
  cp "$ROOT/Pojlib/build/outputs/aar/Pojlib-release.aar" \
     "$ROOT/QCXR-XR-Wrapper/Assets/Plugins/Android/Pojlib-release.aar"
}

unity() {
  log "Unity Android build"
  [ -x "$UNITY" ] || { echo "Unity not found at $UNITY (set UNITY=...)" >&2; exit 1; }
  mkdir -p "$ROOT/logs" "$OUT"
  # The editor build method writes to <wrapper>/../../outputs, so move it after.
  local unity_out
  unity_out="$(cd "$ROOT/.." && pwd)/outputs/Plinth-$MC.apk"
  "$UNITY" -batchmode -quit \
    -projectPath "$ROOT/QCXR-XR-Wrapper" \
    -buildTarget Android \
    -executeMethod QuestCraftVisorBuild.BuildAndroid \
    -holocraftVersion "${VERSION#v}" \
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

server() {
  log "Fabric $MC dedicated server"
  local visor_jar addon_jar dir
  visor_jar=$(ls "$ROOT"/Visor/visor-fabric/versions/$MC/build/libs/Visor-*+mc$MC-fabric.jar | head -n1)
  addon_jar=
  [ "$NO_ADDON" = 1 ] || addon_jar=$(ls "$ROOT"/HoloCraft-MR/build/libs/*.jar | grep -v -- '-sources' | head -n1)
  dir=$(mktemp -d)
  mkdir -p "$dir/mods" "$OUT"

  curl -fsSL -o "$dir/fabric-server-launch.jar" \
    "https://meta.fabricmc.net/v2/versions/loader/$MC/$FABRIC_LOADER/$FABRIC_INSTALLER/server/jar"
  curl -fsSL -o "$dir/mods/fabric-api-$FABRIC_API.jar" \
    "https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/$FABRIC_API/fabric-api-$FABRIC_API.jar"
  cp "$visor_jar" $addon_jar "$dir/mods/"

  cat > "$dir/start.sh" <<'EOF'
#!/bin/sh
cd "$(dirname "$0")"
exec java -Xmx"${MEMORY:-4G}" -jar fabric-server-launch.jar nogui "$@"
EOF
  chmod +x "$dir/start.sh"
  printf '@echo off\r\ncd /d "%%~dp0"\r\njava -Xmx4G -jar fabric-server-launch.jar nogui %%*\r\npause\r\n' > "$dir/start.bat"

  rm -f "$SERVER_ZIP"
  (cd "$dir" && zip -qr "$SERVER_ZIP" .)
  rm -rf "$dir"
  unzip -l "$SERVER_ZIP"
  echo "Server: $SERVER_ZIP"
}

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(atumvr visor addon mods pojlib unity)
if [ "$NO_ADDON" = 1 ]; then
  kept=()
  for step in "${steps[@]}"; do [ "$step" = addon ] || kept+=("$step"); done
  steps=("${kept[@]}")
fi

for step in "${steps[@]}"; do
  case "$step" in
    atumvr|visor|addon|mods|pojlib|unity|install|server) ;;
    *) echo "Unknown step: $step" >&2; exit 1 ;;
  esac
done

for step in "${steps[@]}"; do
  [ "$step" = install ] || [ "$step" = mods ] || check_disk
  "$step"
done
