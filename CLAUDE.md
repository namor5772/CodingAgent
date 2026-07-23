# CodingAgent — project memory

## What this is

Minimal desktop demo: a window titled **Hello World** that plays a short looping animation of a stick figure with a top hat walking across a dark canvas, plus Desktop shortcuts with a custom icon.

Implementations:

- Python/Tkinter: `hello_world.py` (Canvas + `after` timer) — Windows and macOS
- Native Win32 C++: `hello_world.cpp` -> `hello_world_cpp.exe` via `build_cpp.ps1` (GDI + `SetTimer`, double-buffered)
- Native macOS C++/ObjC++: `hello_world_macos.mm` -> `hello_world_cpp` via `build_cpp_macos.sh` (Cocoa/AppKit + `NSTimer`, Core Graphics)

## Environment

- **OS:** Windows and macOS (platform-specific build/shortcut scripts).
- **Python:** 3.13+ preferred on PATH (`python` / `pythonw` on Windows, `python3` on macOS).
- **Stdlib GUI:** `tkinter` (ships with the official Windows Python installer). On macOS, **do not use Apple `/usr/bin/python3`** — its Tk 8.5 paints a blank Canvas on modern macOS. Use Homebrew (`brew install python python-tk`, typically `/opt/homebrew/bin/python3` with Tk 8.6+) or a python.org build. `create_shortcut_macos.sh` picks a Tk 8.6+ interpreter; `hello_world.py` exits with an error dialog if launched under Tk older than 8.6 on Darwin.
- **C++ build (Windows):** Visual Studio with MSVC x64 (`vswhere` + `vcvars64.bat`). Links `user32.lib` and `gdi32.lib` only.
- **C++ build (macOS):** Xcode Command Line Tools (`clang++`), links `-framework Cocoa`. Source is Objective-C++ (`.mm`) with ARC.
- **Icon generation only:** Pillow (`PIL`) — needed to run `create_icon.py`, not to run either app. macOS shortcuts also derive `hello_world.icns` from `hello_world.ico` via `sips` + `iconutil` when `.icns` is missing.

## Layout

| Path | Role |
|------|------|
| `hello_world.py` | Python app — stick figure with hat walking on a Tk Canvas. |
| `hello_world.cpp` | Win32 C++ clone of the same animation (title, colors, minsize, icon). |
| `hello_world_macos.mm` | macOS Cocoa/AppKit C++ clone of the same animation. |
| `build_cpp.ps1` | MSVC build script producing `hello_world_cpp.exe` (WINDOWS subsystem). |
| `build_cpp_macos.sh` | clang++ build script producing `hello_world_cpp` (Cocoa). |
| `hello_world_cpp.exe` | Windows build output (gitignored). Run from repo root so `hello_world.ico` resolves. |
| `hello_world_cpp` | macOS build output (gitignored). Run from repo root so `hello_world.icns` resolves. |
| `hello_world.ico` | Multi-size app icon (Windows window + shortcut). Generated; commit if you want a clone to work without regenerating. |
| `hello_world.icns` | macOS icon (window/Dock + `.app` bundle). Generated from `.ico` by shortcut scripts if missing; safe to commit. |
| `create_icon.py` | Regenerates `hello_world.ico` (blue rounded tile with white **H**). |
| `create_shortcut.ps1` | Creates `%Desktop%\Hello World.lnk` → `pythonw.exe` + `hello_world.py`, icon from `hello_world.ico`. |
| `create_shortcut_cpp.ps1` | Creates `%Desktop%\Hello World (C++).lnk` → `hello_world_cpp.exe`, icon from `hello_world.ico`. Requires the exe (run `build_cpp.ps1` first). |
| `create_shortcut_macos.sh` | Creates `~/Desktop/Hello World.app` → `python3` + `hello_world.py`, icon from `hello_world.icns`. |
| `create_shortcut_cpp_macos.sh` | Creates `~/Desktop/Hello World (C++).app` → `hello_world_cpp`, icon from `hello_world.icns`. Requires the binary (run `build_cpp_macos.sh` first). |
| `CLAUDE.md` | This file. |

## How to run

### Windows

Python:

```powershell
cd C:\Users\roman\ClonedProjects\CodingAgent
python hello_world.py
```

No-console launch (same as the shortcut):

```powershell
pythonw hello_world.py
```

Or double-click the Desktop shortcut **Hello World**.

C++:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
.\hello_world_cpp.exe
```

### macOS

Python:

```bash
cd /Users/roman/projects/CodingAgent
python3 hello_world.py
```

Or double-click the Desktop app **Hello World**.

C++:

```bash
./build_cpp_macos.sh
./hello_world_cpp
```

Or double-click the Desktop app **Hello World (C++)**.

## Regenerate icon / shortcuts

Windows:

```powershell
python create_icon.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut_cpp.ps1
```

macOS:

```bash
python3 create_icon.py   # optional; needs Pillow — produces .ico
./create_shortcut_macos.sh
./build_cpp_macos.sh
./create_shortcut_cpp_macos.sh
```

Windows Python shortcut target uses `pythonw.exe` next to whatever `python` is on PATH. macOS Python `.app` launcher uses `python3` on PATH (falls back to `/usr/bin/python3`). C++ shortcuts target the built binary with WorkingDirectory = repo root. Desktop folder is `[Environment]::GetFolderPath('Desktop')` on Windows (often OneDrive Desktop) and `~/Desktop` on macOS.

macOS "shortcuts" are minimal `.app` bundles (shell launcher in `Contents/MacOS`, `Info.plist`, optional `Resources/hello_world.icns`) — same pattern as other Desktop apps on this machine — not Finder aliases.

## Quick verification

- Parse/import: `python -c "import ast, pathlib; ast.parse(pathlib.Path('hello_world.py').read_text()); import hello_world"` (use `python3` on macOS)
- GUI smoke (build window, advance a few animation ticks, assert canvas items, destroy): keep it headless-friendly with `root.update()` then `root.destroy()` — do not leave `mainloop()` running in automated checks. Note: agent/CI environments without a usable Aqua session may hang on `tk.Tk()`.
- C++ Windows: build with `build_cpp.ps1`, launch `hello_world_cpp.exe`, assert a visible window titled `Hello World` (~400x200), then `WM_CLOSE` and expect a clean exit.
- C++ macOS: build with `build_cpp_macos.sh`, launch `./hello_world_cpp`, assert process stays up and an on-screen window ~400x200 content (outer height includes title bar), then terminate.
- Python shortcut Windows: COM `WScript.Shell`.CreateShortcut on `%Desktop%\Hello World.lnk` — check `TargetPath` (pythonw), `Arguments` (hello_world.py), `IconLocation`.
- C++ shortcut Windows: same for `%Desktop%\Hello World (C++).lnk` — `TargetPath` = `hello_world_cpp.exe`, empty `Arguments`, `WorkingDirectory` = repo root, `IconLocation` from `hello_world.ico`.
- macOS shortcuts: `~/Desktop/Hello World.app` and `~/Desktop/Hello World (C++).app` — check `Contents/MacOS/*` launcher paths, `Info.plist` `CFBundleExecutable` / icon, and `Resources/hello_world.icns` when present.

## Conventions

- Prefer **stdlib** / system libs for app runtime; optional tools (Pillow, PowerShell COM, MSVC, sips/iconutil) only for asset/shortcut/build setup.
- Keep the UI single-window and minimal unless the task expands scope.
- Match the Python UI when changing either C++ clone (title, walk cycle math, colors `#1a1a2e` / `#eaeaea` / hat `#c9a227`, ground `#2a2a44`, 400x200 default, 300x150 min, bundled icon, ~50 ms frame timer).
- Use `pythonw` / WINDOWS subsystem / macOS `.app` launchers for end-user launch so no console/Terminal flashes.
- PowerShell scripts: stick to **ASCII** in string literals (encoding/code-page issues with em dashes etc.). Shell scripts: ASCII preferred in generated plists/launchers.
- macOS drawing uses AppKit bottom-left origin; flip Y in the draw path so walk-cycle math stays identical to Win32/Tk (top-left).
- Do not commit `__pycache__/` or build outputs (`*.obj`, `*.o`, `*.pdb`, `hello_world_cpp.exe`, `hello_world_cpp`, `*.dSYM/`).
- Do not commit or push unless the user asks.

## Out of scope (for now)

- Packaging (PyInstaller/etc.), installer, tests framework, Linux ports.
