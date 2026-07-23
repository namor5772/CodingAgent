# CodingAgent

Minimal Windows desktop demo: a Tkinter window that displays **HELLO WORLD**, plus an optional Desktop shortcut with a custom icon.

## Requirements

- **OS:** Windows
- **Python:** 3.13+ on `PATH` (`python`, `pythonw`)
- **GUI:** `tkinter` (included with the official Windows Python installer)
- **Icon generation only:** [Pillow](https://pypi.org/project/Pillow/) (`pip install pillow`) — not required to run the app

## Quick start

```powershell
cd C:\Users\roman\ClonedProjects\CodingAgent
python hello_world.py
```

Launch without a console window (same as the Desktop shortcut):

```powershell
pythonw hello_world.py
```

## Project layout

| Path | Role |
|------|------|
| `hello_world.py` | Main app — Tk window titled "Hello World" showing **HELLO WORLD** |
| `hello_world.ico` | Multi-size app icon (window title bar / taskbar and shortcut) |
| `create_icon.py` | Regenerates `hello_world.ico` (blue rounded tile with white **H**) |
| `create_shortcut.ps1` | Creates `%Desktop%\Hello World.lnk` → `pythonw.exe` + `hello_world.py` |
| `CLAUDE.md` | Project memory / contributor conventions |

## Desktop shortcut

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1
```

The shortcut target is `pythonw.exe` next to whatever `python` is on `PATH`. The Desktop folder is resolved via `[Environment]::GetFolderPath('Desktop')` (often the OneDrive Desktop).

## Regenerate the icon

```powershell
pip install pillow   # once, if needed
python create_icon.py
```

## Notes

- Runtime depends only on the Python standard library (`tkinter`).
- Prefer `pythonw` for end-user launch so no console flashes.
- Packaging, installers, and non-Windows shortcuts are out of scope for now.
