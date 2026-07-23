#!/usr/bin/env bash
# Creates ~/Desktop/Hello World (C++).app that launches hello_world_cpp (no Terminal).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_EXE="$REPO_ROOT/hello_world_cpp"
ICON_ICNS="$REPO_ROOT/hello_world.icns"
ICON_ICO="$REPO_ROOT/hello_world.ico"
DESKTOP="${HOME}/Desktop"
APP_DIR="$DESKTOP/Hello World (C++).app"
EXEC_NAME="Hello World (C++)"
BUNDLE_ID="com.codingagent.HelloWorldCpp"

if [[ ! -f "$APP_EXE" ]]; then
  echo "error: app binary not found: $APP_EXE" >&2
  echo "Build it first: ./build_cpp_macos.sh" >&2
  exit 1
fi
if [[ ! -x "$APP_EXE" ]]; then
  chmod +x "$APP_EXE" || true
fi

# Ensure .icns exists for the bundle icon (generate from .ico if needed).
ensure_icns() {
  if [[ -f "$ICON_ICNS" ]]; then
    return 0
  fi
  if [[ ! -f "$ICON_ICO" ]]; then
    echo "warning: no hello_world.icns or hello_world.ico; app will use the default icon" >&2
    return 0
  fi
  if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "warning: sips/iconutil missing; cannot derive .icns from .ico" >&2
    return 0
  fi
  local tmp png
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/hw_icon.XXXXXX")"
  png="$tmp/icon.png"
  if ! sips -s format png "$ICON_ICO" --out "$png" >/dev/null 2>&1; then
    echo "warning: failed to convert $ICON_ICO to PNG" >&2
    rm -rf "$tmp"
    return 0
  fi
  local iconset="$tmp/hello_world.iconset"
  mkdir -p "$iconset"
  local pair size name
  for pair in \
    "16 icon_16x16" \
    "32 icon_16x16@2x" \
    "32 icon_32x32" \
    "64 icon_32x32@2x" \
    "128 icon_128x128" \
    "256 icon_128x128@2x" \
    "256 icon_256x256" \
    "512 icon_256x256@2x" \
    "512 icon_512x512" \
    "1024 icon_512x512@2x"; do
    size="${pair%% *}"
    name="${pair#* }"
    sips -z "$size" "$size" "$png" --out "$iconset/${name}.png" >/dev/null
  done
  if iconutil -c icns "$iconset" -o "$ICON_ICNS" >/dev/null 2>&1; then
    echo "Generated: $ICON_ICNS"
  else
    echo "warning: iconutil failed; app will use the default icon" >&2
  fi
  rm -rf "$tmp"
}

ensure_icns

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Launcher: WorkingDirectory = repo root so hello_world.icns resolves next to the binary.
cat > "$APP_DIR/Contents/MacOS/$EXEC_NAME" <<EOF
#!/bin/bash
BIN="$APP_EXE"
cd "$REPO_ROOT"
exec "\$BIN" "\$@"
EOF
chmod +x "$APP_DIR/Contents/MacOS/$EXEC_NAME"

if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/hello_world.icns"
  ICON_KEY="hello_world"
else
  ICON_KEY=""
fi

{
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>Hello World (C++)</string>
    <key>CFBundleDisplayName</key>      <string>Hello World (C++)</string>
    <key>CFBundleIdentifier</key>       <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>          <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleExecutable</key>       <string>${EXEC_NAME}</string>
PLIST
  if [[ -n "$ICON_KEY" ]]; then
    echo "    <key>CFBundleIconFile</key>         <string>${ICON_KEY}</string>"
  fi
  cat <<'PLIST'
    <key>NSHighResolutionCapable</key>  <true/>
    <key>LSMinimumSystemVersion</key>   <string>10.13</string>
    <key>LSUIElement</key>              <false/>
</dict>
</plist>
PLIST
} > "$APP_DIR/Contents/Info.plist"

if command -v touch >/dev/null 2>&1; then
  touch "$APP_DIR"
fi

echo "Shortcut created: $APP_DIR"
echo "Target: $APP_EXE"
if [[ -f "$ICON_ICNS" ]]; then
  echo "Icon:   $ICON_ICNS"
else
  echo "Icon:   (default)"
fi
