# CodingAgent

Minimal desktop demo: a window titled **Hello World** with a short looping animation of a stick figure in a top hat walking across the window, plus optional Desktop shortcuts with a custom icon.

Implementations ship side by side:

- **Python** — `hello_world.py` (Tkinter Canvas) on Windows and macOS
- **C++ (Windows)** — `hello_world.cpp` (native Win32 GDI)
- **C++ (macOS)** — `hello_world_macos.mm` (native Cocoa / AppKit)

## Requirements

### Windows

- **Python app:** Python 3.13+ on `PATH` (`python`, `pythonw`) with `tkinter` (official Windows installer)
- **C++ app:** Visual Studio with the **Desktop development with C++** workload (MSVC x64)
- **Icon generation only:** [Pillow](https://pypi.org/project/Pillow/) (`pip install pillow`) — not required to run either app

### macOS

- **Python app:** `python3` on `PATH` with **Tk 8.6+** (`tkinter`). Homebrew: `brew install python python-tk` (use `/opt/homebrew/bin/python3`). Apple `/usr/bin/python3` (Tk 8.5) shows a **blank window** and is rejected at startup.
- **C++ app:** Xcode Command Line Tools (`clang++`)
- **Shortcuts / icon:** `sips` and `iconutil` (system) to derive `hello_world.icns` from `hello_world.ico` when needed
- **Icon generation only:** Pillow — not required to run either app

## Quick start (Python)

From the repo root:

Windows:

```powershell
python hello_world.py
```

Launch without a console window (same as the Desktop shortcut):

```powershell
pythonw hello_world.py
```

macOS (Homebrew Python with Tk 8.6+ — not Apple `/usr/bin/python3`):

```bash
/opt/homebrew/bin/python3 hello_world.py
# or, if that python3 is first on your PATH:
python3 hello_world.py
```

## Quick start (C++)

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
.\hello_world_cpp.exe
```

`build_cpp.ps1` locates MSVC via `vswhere`, runs `vcvars64.bat`, and produces `hello_world_cpp.exe` (Windows subsystem, no console). Keep `hello_world.ico` in the repo root so the window picks up the same icon as the Python app.

macOS:

```bash
./build_cpp_macos.sh
./hello_world_cpp
```

`build_cpp_macos.sh` compiles `hello_world_macos.mm` with `clang++` and links AppKit/Cocoa. Keep `hello_world.icns` in the repo root (shortcut scripts can generate it from `hello_world.ico`) so the app can set its icon when launched outside a bundle.

## Project layout

| Path | Role |
|------|------|
| `hello_world.py` | Python/Tk app — stick figure with hat walking on a Canvas |
| `hello_world.cpp` | Native Win32 clone of the same animation |
| `hello_world_macos.mm` | Native macOS Cocoa clone of the same animation |
| `build_cpp.ps1` | Builds `hello_world_cpp.exe` with MSVC x64 |
| `build_cpp_macos.sh` | Builds `hello_world_cpp` with clang++ / Cocoa |
| `hello_world.ico` | Multi-size app icon (Windows title bar / taskbar and shortcut) |
| `hello_world.icns` | macOS icon (Dock / `.app` bundle); generated from `.ico` if missing |
| `create_icon.py` | Regenerates `hello_world.ico` (blue rounded tile with white **H**) |
| `create_shortcut.ps1` | Creates `%Desktop%\Hello World.lnk` → `pythonw.exe` + `hello_world.py` |
| `create_shortcut_cpp.ps1` | Creates `%Desktop%\Hello World (C++).lnk` → `hello_world_cpp.exe` |
| `create_shortcut_macos.sh` | Creates `~/Desktop/Hello World.app` → `python3` + `hello_world.py` |
| `create_shortcut_cpp_macos.sh` | Creates `~/Desktop/Hello World (C++).app` → `hello_world_cpp` |
| `CLAUDE.md` | Project memory / contributor conventions |

## Desktop shortcuts

### Windows

Full setup (build C++ then create both shortcuts):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut_cpp.ps1
```

Or individually:

```powershell
# Python only
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1

# C++ only (build the exe first)
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut_cpp.ps1
```

| Shortcut | Target |
|----------|--------|
| **Hello World** | `pythonw.exe` + `hello_world.py` |
| **Hello World (C++)** | `hello_world_cpp.exe` |

Both use `hello_world.ico` when present. Working directory is the repo root (so the C++ app finds the icon). Desktop folder is `[Environment]::GetFolderPath('Desktop')` (often the OneDrive Desktop).

### macOS

Full setup (build C++ then create both Desktop apps):

```bash
./build_cpp_macos.sh
./create_shortcut_macos.sh
./create_shortcut_cpp_macos.sh
```

Or individually:

```bash
# Python only
./create_shortcut_macos.sh

# C++ only (build the binary first)
./build_cpp_macos.sh
./create_shortcut_cpp_macos.sh
```

| Shortcut | Target |
|----------|--------|
| **Hello World.app** | Homebrew `python3` (Tk 8.6+) + `hello_world.py` |
| **Hello World (C++).app** | `hello_world_cpp` |

These are minimal `.app` bundles (launcher script + `Info.plist` + `hello_world.icns`), not Finder aliases — double-clickable from Desktop without opening Terminal. Working directory is the repo root. `create_shortcut_macos.sh` selects a Python with Tk 8.6+ (prefers `/opt/homebrew/bin/python3`) and refuses Apple system Tk 8.5. If `hello_world.icns` is missing, the scripts generate it from `hello_world.ico` via `sips` / `iconutil`.

## Cross-platform notes

The same git tree works on both OSes. After `git pull`:

| | Windows | macOS |
|--|---------|--------|
| Python app | `python` / `pythonw hello_world.py` | Homebrew `python3 hello_world.py` (Tk 8.6+) |
| C++ source | `hello_world.cpp` | `hello_world_macos.mm` |
| Build | `build_cpp.ps1` → `hello_world_cpp.exe` | `build_cpp_macos.sh` → `hello_world_cpp` |
| Desktop shortcut | `create_shortcut*.ps1` → `.lnk` | `create_shortcut*_macos.sh` → `.app` |
| Icon | `hello_world.ico` | `hello_world.icns` (optional; derived from `.ico`) |

Platform-specific scripts are no-ops on the other OS — use the matching ones for the machine you are on. Build outputs are gitignored; rebuild after pull.

## Regenerate the icon

```powershell
pip install pillow   # once, if needed
python create_icon.py
```

On macOS, `python3 create_icon.py` writes `.ico`; the shortcut scripts also produce `hello_world.icns` when creating Desktop apps.

## UI parity (Python and C++)

All apps aim to match:

- Window title **Hello World**, dark canvas `#1a1a2e`, figure `#eaeaea`, hat `#c9a227`, ground `#2a2a44`
- Default **client** size 400x200 and minimum **client** size 300x150 (Win32 converts client to outer size with `AdjustWindowRectEx`; macOS uses `contentRect` / `setContentMinSize` so chrome does not shrink the canvas vs Tk)
- ~50 ms frame timer, shared walk-cycle math and scaling
- Bundled icon for the window and Desktop shortcuts (`.ico` on Windows, `.icns` on macOS)
- Window geometry (position/size) is restored on launch and saved on close

Windows C++ draws with double-buffered GDI (`WM_PAINT` + compatible bitmap), round pen caps via `ExtCreatePen`, and the same draw order as the Python canvas (torso, head, hat, arms, legs).

macOS C++ draws with Core Graphics in an `NSView` (`drawRect:`), round line caps/joins, Y-flipped so the shared top-left walk math matches Win32/Tk, and the same draw order.

## Window geometry persistence

Each implementation remembers its own window **position and client size** across launches (JSON under a per-user config directory). Python and C++ **do not share** the same file, so moving or resizing one app does not affect the other.

| App | Config file |
|-----|-------------|
| Python (`hello_world.py`) | `hello_world_geometry.json` |
| C++ (Win32 / macOS) | `hello_world_cpp_geometry.json` |

| OS | Directory |
|----|-----------|
| Windows | `%LOCALAPPDATA%\CodingAgent\` (typically `AppData\Local\CodingAgent`) |
| macOS | `~/Library/Application Support/CodingAgent/` |
| Other (Python) | `$XDG_CONFIG_HOME/CodingAgent/` or `~/.config/CodingAgent/` |

Invalid, too-small, or off-screen restored values fall back to the default 400x200 client size (centered when possible).

## Notes

- Python runtime depends only on the standard library (`tkinter`).
- Windows C++ runtime depends only on system Win32 libraries (`user32`, `gdi32`).
- macOS C++ runtime depends only on system Cocoa/AppKit.
- Prefer `pythonw` / the Windows subsystem `.exe` / macOS `.app` launchers for end-user launch so no console or Terminal flashes.
- On macOS, `hello_world.py` exits with an error dialog if Tk is older than 8.6 (blank-canvas bug with Apple system Tk 8.5).
- Do not commit build outputs (`hello_world_cpp.exe`, `hello_world_cpp`, `*.obj`, `*.o`, `*.pdb`, `*.dSYM/`) or `__pycache__/`.
- Packaging and installers remain out of scope for now.
