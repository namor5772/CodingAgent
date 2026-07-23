# CodingAgent — project memory

## What this is

Minimal Windows desktop demo: a window titled **Hello World** that plays a short looping animation of a stick figure with a top hat walking across a dark canvas, plus Desktop shortcuts with a custom icon.

Implementations:

- Python/Tkinter: `hello_world.py` (Canvas + `after` timer)
- Native Win32 C++: `hello_world.cpp` -> `hello_world_cpp.exe` via `build_cpp.ps1` (GDI + `SetTimer`, double-buffered)

## Environment

- **OS:** Windows (paths and shortcut creation assume Windows).
- **Python:** 3.13+ on PATH (`python`, `pythonw`).
- **Stdlib GUI:** `tkinter` (ships with the official Windows Python installer).
- **C++ build:** Visual Studio with MSVC x64 (`vswhere` + `vcvars64.bat`). Links `user32.lib` and `gdi32.lib` only.
- **Icon generation only:** Pillow (`PIL`) — needed to run `create_icon.py`, not to run either app.

## Layout

| Path | Role |
|------|------|
| `hello_world.py` | Python app — stick figure with hat walking on a Tk Canvas. |
| `hello_world.cpp` | Win32 C++ clone of the same animation (title, colors, minsize, icon). |
| `build_cpp.ps1` | MSVC build script producing `hello_world_cpp.exe` (WINDOWS subsystem). |
| `hello_world_cpp.exe` | Build output (gitignored). Run from repo root so `hello_world.ico` resolves. |
| `hello_world.ico` | Multi-size app icon (window + shortcut). Generated; commit if you want a clone to work without regenerating. |
| `create_icon.py` | Regenerates `hello_world.ico` (blue rounded tile with white **H**). |
| `create_shortcut.ps1` | Creates `%Desktop%\Hello World.lnk` → `pythonw.exe` + `hello_world.py`, icon from `hello_world.ico`. |
| `create_shortcut_cpp.ps1` | Creates `%Desktop%\Hello World (C++).lnk` → `hello_world_cpp.exe`, icon from `hello_world.ico`. Requires the exe (run `build_cpp.ps1` first). |
| `CLAUDE.md` | This file. |

## How to run

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

## Regenerate icon / shortcuts

```powershell
python create_icon.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut_cpp.ps1
```

Python shortcut target uses `pythonw.exe` next to whatever `python` is on PATH. C++ shortcut targets `hello_world_cpp.exe` with WorkingDirectory = repo root. Desktop folder is `[Environment]::GetFolderPath('Desktop')` (often OneDrive Desktop).

## Quick verification

- Parse/import: `python -c "import ast, pathlib; ast.parse(pathlib.Path('hello_world.py').read_text()); import hello_world"`
- GUI smoke (build window, advance a few animation ticks, assert canvas items, destroy): keep it headless-friendly with `root.update()` then `root.destroy()` — do not leave `mainloop()` running in automated checks.
- C++: build with `build_cpp.ps1`, launch `hello_world_cpp.exe`, assert a visible window titled `Hello World` (~400x200), then `WM_CLOSE` and expect a clean exit.
- Python shortcut: COM `WScript.Shell`.CreateShortcut on `%Desktop%\Hello World.lnk` — check `TargetPath` (pythonw), `Arguments` (hello_world.py), `IconLocation`.
- C++ shortcut: same for `%Desktop%\Hello World (C++).lnk` — `TargetPath` = `hello_world_cpp.exe`, empty `Arguments`, `WorkingDirectory` = repo root, `IconLocation` from `hello_world.ico`.

## Conventions

- Prefer **stdlib** / system libs for app runtime; optional tools (Pillow, PowerShell COM, MSVC) only for asset/shortcut/build setup.
- Keep the UI single-window and minimal unless the task expands scope.
- Match the Python UI when changing the C++ clone (title, walk cycle math, colors `#1a1a2e` / `#eaeaea` / hat `#c9a227`, ground `#2a2a44`, 400x200 default, 300x150 min, bundled `.ico`, ~50 ms frame timer).
- Use `pythonw` / WINDOWS subsystem for end-user launch so no console flashes.
- PowerShell scripts: stick to **ASCII** in string literals (encoding/code-page issues with em dashes etc.).
- Do not commit `__pycache__/` or MSVC build outputs (`*.obj`, `*.pdb`, `hello_world_cpp.exe`).
- Do not commit or push unless the user asks.

## Out of scope (for now)

- Packaging (PyInstaller/etc.), installer, tests framework, non-Windows shortcuts/ports.
