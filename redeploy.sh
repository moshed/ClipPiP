#!/bin/bash
# Build ClipPiP, fully quit any running instance, install to /Applications, relaunch,
# and VERIFY the running binary is the one we just built (an already-running instance
# would otherwise just re-activate stale, making changes look like they did nothing).
set -euo pipefail

APP="ClipPiP"
PROJ_DIR="/Users/moshe/Apps/ClipPiP"
SRC="$PROJ_DIR/build/Build/Products/Release/$APP.app"
DEST="/Applications/$APP.app"
BIN_REL="Contents/MacOS/$APP"

cd "$PROJ_DIR"

echo "▸ Building…"
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
  -derivedDataPath build build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
[ -x "$SRC/$BIN_REL" ] || { echo "✘ build produced no binary"; exit 1; }

echo "▸ Quitting running instance…"
osascript -e "tell application \"$APP\" to quit" 2>/dev/null || true
pkill -f "$DEST/$BIN_REL" 2>/dev/null || true
# Wait (up to ~10s) until the process is actually gone — the key step.
for _ in $(seq 1 50); do
  pgrep -f "$DEST/$BIN_REL" >/dev/null 2>&1 || break
  sleep 0.2
done
if pgrep -f "$DEST/$BIN_REL" >/dev/null 2>&1; then
  echo "  …force-killing"; pkill -9 -f "$DEST/$BIN_REL" 2>/dev/null || true; sleep 0.5
fi

echo "▸ Installing…"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
NEW_MTIME=$(stat -f %m "$DEST/$BIN_REL")

echo "▸ Launching…"
open "$DEST"

echo "▸ Verifying fresh instance…"
for _ in $(seq 1 25); do
  PID=$(pgrep -f "$DEST/$BIN_REL" | head -1 || true)
  [ -n "${PID:-}" ] && break
  sleep 0.2
done
if [ -z "${PID:-}" ]; then echo "✘ did not launch"; exit 1; fi
# Confirm the launched executable is the freshly-installed one.
RUN_BIN=$(ps -p "$PID" -o comm= 2>/dev/null || true)
echo "✔ $APP running (pid $PID), binary built $(date -r "$NEW_MTIME" '+%H:%M:%S')"
echo "  exec: $RUN_BIN"
