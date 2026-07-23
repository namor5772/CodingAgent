# CodingAgent — project memory

## What this is

Minimal Windows desktop demo: a Tkinter window that shows **HELLO WORLD**, plus a Desktop shortcut with a custom icon.

## Environment

- **OS:** Windows (paths and shortcut creation assume Windows).
- **Python:** 3.13+ on PATH (`python`, `pythonw`).
- **Stdlib GUI:** `tkinter` (ships with the official Windows Python installer).
- **Icon generation only:** Pillow (`PIL`) — needed to run `create_icon.py`, not to run the app itself.

## Layout

| Path | Role |
|------|------|
| `hello_world.py` | Main app — open a Tk window and display `HELLO WORLD`. |
| `hello_world.ico` | Multi-size app icon (window + shortcut). Generated; commit if you want a clone to work without regenerating. |
| `create_icon.py` | Regenerates `hello_world.ico` (blue rounded tile with white **H**). |
| `create_shortcut.ps1` | Creates `%Desktop%\Hello World.lnk` → `pythonw.exe` + `hello_world.py`, icon from `hello_world.ico`. |
| `CLAUDE.md` | This file. |

## How to run

```powershell
cd C:\Users\roman\ClonedProjects\CodingAgent
python hello_world.py
```

No-console launch (same as the shortcut):

```powershell
pythonw hello_world.py
```

Or double-click the Desktop shortcut **Hello World**.

## Regenerate icon / shortcut

```powershell
python create_icon.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\create_shortcut.ps1
```

Shortcut target uses `pythonw.exe` next to whatever `python` is on PATH. Desktop folder is `[Environment]::GetFolderPath('Desktop')` (often OneDrive Desktop).

## Quick verification

- Parse/import: `python -c "import ast, pathlib; ast.parse(pathlib.Path('hello_world.py').read_text()); import hello_world"`
- GUI smoke (build window, assert label, destroy): keep it headless-friendly with `root.update()` then `root.destroy()` — do not leave `mainloop()` running in automated checks.
- Shortcut: COM `WScript.Shell`.CreateShortcut and check `TargetPath`, `Arguments`, `IconLocation`.

## Conventions

- Prefer **stdlib** for the app runtime; optional tools (Pillow, PowerShell COM) only for asset/shortcut setup.
- Keep the UI single-window and minimal unless the task expands scope.
- Use `pythonw` for end-user launch so no console flashes.
- PowerShell scripts: stick to **ASCII** in string literals (encoding/code-page issues with em dashes etc.).
- Do not commit `__pycache__/`.
- Do not commit or push unless the user asks.

## Out of scope (for now)

- Packaging (PyInstaller/etc.), installer, tests framework, non-Windows shortcuts.
