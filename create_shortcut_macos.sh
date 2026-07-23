#!/usr/bin/env bash
# Creates ~/Desktop/Hello World.app that launches hello_world.py (no Terminal).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_SCRIPT="$REPO_ROOT/hello_world.py"
ICON_ICNS="$REPO_ROOT/hello_world.icns"
ICON_ICO="$REPO_ROOT/hello_world.ico"
DESKTOP="${HOME}/Desktop"
APP_DIR="$DESKTOP/Hello World.app"
EXEC_NAME="Hello World"
BUNDLE_ID="com.codingagent.HelloWorld"

if [[ ! -f "$APP_SCRIPT" ]]; then
  echo "error: app script not found: $APP_SCRIPT" >&2
  exit 1
fi

# Prefer a Python whose tkinter can actually paint on modern macOS.
# Apple /usr/bin/python3 ships Tk 8.5, which often shows a blank Canvas window.
# Homebrew python3 (python-tk / tcl-tk) provides Tk 8.6+ / 9.x and works.
pick_python() {
  local candidates=()
  # Homebrew first (Apple Silicon, then Intel), then PATH, then system.
  [[ -x /opt/homebrew/bin/python3 ]] && candidates+=(/opt/homebrew/bin/python3)
  [[ -x /usr/local/bin/python3 ]] && candidates+=(/usr/local/bin/python3)
  if command -v python3 >/dev/null 2>&1; then
    candidates+=("$(command -v python3)")
  fi
  [[ -x /usr/bin/python3 ]] && candidates+=(/usr/bin/python3)

  local py ver
  local seen=""
  for py in "${candidates[@]}"; do
    # De-dupe
    case " $seen " in
      *" $py "*) continue ;;
    esac
    seen+=" $py"
    [[ -x "$py" ]] || continue
    # Must import tkinter and report a Tcl patchlevel >= 8.6
    ver="$("$py" -c 'import tkinter as t; print(t.Tcl().eval("info patchlevel"))' 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
      continue
    fi
    # Numeric compare major.minor (8.6, 9.0.3 -> 8.6 / 9.0)
    if "$py" -c 'import tkinter as t,sys; v=t.Tcl().eval("info patchlevel").split("."); sys.exit(0 if (int(v[0]),int(v[1]))>=(8,6) else 1)' 2>/dev/null; then
      echo "$py"
      echo "Using $py (Tk $ver)" >&2
      return 0
    else
      echo "skip $py (Tk $ver too old for reliable Canvas)" >&2
    fi
  done
  return 1
}

PYTHON="$(pick_python || true)"
if [[ -z "${PYTHON}" || ! -x "$PYTHON" ]]; then
  echo "error: no suitable python3 with Tk 8.6+ found." >&2
  echo "Install one of:" >&2
  echo "  brew install python python-tk" >&2
  echo "  (or any python.org installer that bundles Tk 8.6+)" >&2
  echo "Apple /usr/bin/python3 (Tk 8.5) draws a blank window on modern macOS." >&2
  exit 1
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
  # sips reads multi-size ICO and writes a PNG we can resize into an iconset.
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

# Launcher: cd to repo root so relative assets resolve; exec python (no Terminal.app).
cat > "$APP_DIR/Contents/MacOS/$EXEC_NAME" <<EOF
#!/bin/bash
PYTHON="$PYTHON"
SCRIPT="$APP_SCRIPT"
[ -x "\$PYTHON" ] || PYTHON="\$(/usr/bin/command -v python3 || echo /usr/bin/python3)"
cd "$REPO_ROOT"
exec "\$PYTHON" "\$SCRIPT" "\$@"
EOF
chmod +x "$APP_DIR/Contents/MacOS/$EXEC_NAME"

if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/hello_world.icns"
  ICON_KEY="hello_world"
else
  ICON_KEY=""
fi

# Info.plist (ASCII only).
{
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>Hello World</string>
    <key>CFBundleDisplayName</key>      <string>Hello World</string>
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

# Refresh Finder icon cache for this bundle path.
if command -v touch >/dev/null 2>&1; then
  touch "$APP_DIR"
fi

echo "Shortcut created: $APP_DIR"
echo "Target: $PYTHON $APP_SCRIPT"
if [[ -f "$ICON_ICNS" ]]; then
  echo "Icon:   $ICON_ICNS"
else
  echo "Icon:   (default)"
fi
