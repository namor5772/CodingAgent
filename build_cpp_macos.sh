#!/usr/bin/env bash
# Build hello_world_macos.mm -> hello_world_cpp (clang++, Cocoa/AppKit).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

OUT="$REPO_ROOT/hello_world_cpp"
SRC="$REPO_ROOT/hello_world_macos.mm"

if [[ ! -f "$SRC" ]]; then
  echo "error: source not found: $SRC" >&2
  exit 1
fi

if ! command -v clang++ >/dev/null 2>&1; then
  echo "error: clang++ not found. Install Xcode Command Line Tools (xcode-select --install)." >&2
  exit 1
fi

clang++ -std=c++17 -fobjc-arc -O2 -Wall -Wextra \
  -framework Cocoa \
  "$SRC" \
  -o "$OUT"

echo "Built: $OUT"
