# CodingAgent

Minimal Windows desktop demo: a window that displays **HELLO WORLD**, plus an optional Desktop shortcut with a custom icon.

Two equivalent implementations ship side by side:

- **Python** — `hello_world.py` (Tkinter)
- **C++** — `hello_world.cpp` (native Win32)

## Requirements

- **OS:** Windows
- **Python app:** Python 3.13+ on `PATH` (`python`, `pythonw`) with `tkinter` (official Windows installer)
- **C++ app:** Visual Studio with the **Desktop development with C++** workload (MSVC x64)
- **Icon generation only:** [Pillow](https://pypi.org/project/Pillow/) (`pip install pillow`) — not required to run either app

## Quick start (Python)

```powershell
cd C:\Users\roman\ClonedProjects\CodingAgent
python hello_world.py
```

Launch without a console window (same as the Desktop shortcut):

```powershell
pythonw hello_world.py
```

## Quick start (C++)

```powershell
cd C:\Users\roman\ClonedProjects\CodingAgent
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
.\hello_world_cpp.exe
```

`build_cpp.ps1` locates MSVC via `vswhere`, runs `vcvars64.bat`, and produces `hello_world_cpp.exe` (Windows subsystem, no console). Place `hello_world.ico` next to the exe (repo root) so the window picks up the same icon as the Python app.

## Project layout

| Path | Role |
|------|------|
| `hello_world.py` | Python/Tk app — window titled "Hello World" showing **HELLO WORLD** |
| `hello_world.cpp` | Native Win32 clone of the same UI |
| `build_cpp.ps1` | Builds `hello_world_cpp.exe` with MSVC x64 |
| `hello_world.ico` | Multi-size app icon (window title bar / taskbar and shortcut) |
| `create_icon.py` | Regenerates `hello_world.ico` (blue rounded tile with white **H**) |
| `create_shortcut.ps1` | Creates `%Desktop%\Hello World.lnk` → `pythonw.exe` + `hello_world.py` |
| `create_shortcut_cpp.ps1` | Creates `%Desktop%\Hello World (C++).lnk` → `hello_world_cpp.exe` |
| `CLAUDE.md` | Project memory / contributor conventions |

## Desktop shortcuts

Python:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1
```

C++ (build the exe first):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut_cpp.ps1
```

| Shortcut | Target |
|----------|--------|
| **Hello World** | `pythonw.exe` + `hello_world.py` |
| **Hello World (C++)** | `hello_world_cpp.exe` |

Both use `hello_world.ico` when present. Working directory is the repo root (so the C++ app finds the icon). Desktop folder is `[Environment]::GetFolderPath('Desktop')` (often the OneDrive Desktop).

## Regenerate the icon

```powershell
pip install pillow   # once, if needed
python create_icon.py
```

## Notes

- Python runtime depends only on the standard library (`tkinter`).
- C++ runtime depends only on system Win32 libraries (`user32`, `gdi32`).
- Prefer `pythonw` / the `.exe` subsystem for end-user launch so no console flashes.
- Packaging, installers, and non-Windows ports are out of scope for now.
