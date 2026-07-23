"""Minimal Tkinter app: stick figure with a hat walking across the window."""

from __future__ import annotations

import json
import math
import os
import sys
import tkinter as tk
from pathlib import Path

# Match prior chrome: dark bg, light strokes, default/min size.
BG = "#1a1a2e"
FG = "#eaeaea"
HAT = "#c9a227"  # muted gold brim/crown accent
FRAME_MS = 50
WALK_SPEED = 2.4  # px per frame at default scale baseline
DEFAULT_WIDTH = 400
DEFAULT_HEIGHT = 200
MIN_WIDTH = 300
MIN_HEIGHT = 150


def _config_path() -> Path:
    """Per-user geometry file for the Python app only (not shared with C++).

    Outside the repo: LocalAppData / XDG / ~/Library Application Support.
    C++ clones use hello_world_cpp_geometry.json in the same directory.
    """
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / "CodingAgent" / "hello_world_geometry.json"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "CodingAgent" / "hello_world_geometry.json"
    xdg = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(xdg) / "CodingAgent" / "hello_world_geometry.json"


def load_geometry() -> dict[str, int] | None:
    """Return {x, y, w, h} client geometry if the config is valid, else None."""
    path = _config_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(data, dict):
        return None
    try:
        x = int(data["x"])
        y = int(data["y"])
        w = int(data["w"])
        h = int(data["h"])
    except (KeyError, TypeError, ValueError):
        return None
    if w < MIN_WIDTH or h < MIN_HEIGHT:
        return None
    # Reject absurd values (corrupt file / multi-monitor gone wrong).
    if abs(x) > 100_000 or abs(y) > 100_000 or w > 20_000 or h > 20_000:
        return None
    return {"x": x, "y": y, "w": w, "h": h}


def save_geometry(x: int, y: int, w: int, h: int) -> None:
    path = _config_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"x": int(x), "y": int(y), "w": int(w), "h": int(h)}
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    except OSError:
        pass


def _parse_geometry(geo: str) -> tuple[int, int, int, int] | None:
    """Parse Tk geometry 'WxH+X+Y' (X/Y may use '-' for negative)."""
    try:
        x_sep = -1
        for i, ch in enumerate(geo):
            if ch in "+-" and i > 0 and geo[i - 1].isdigit():
                # First sign after WxH separates width/height from x.
                # Require the left side to contain 'x' so we don't trip on nothing.
                if "x" in geo[:i]:
                    x_sep = i
                    break
        if x_sep < 0:
            return None
        wh = geo[:x_sep]
        rest = geo[x_sep:]
        w_str, _, h_str = wh.partition("x")
        w = int(w_str)
        h = int(h_str)
        # rest is like "+120+80", "-10+20", "+120-40", "-10-20"
        i = 1  # skip first sign
        while i < len(rest) and rest[i] not in "+-":
            i += 1
        if i >= len(rest):
            return None
        x = int(rest[:i])
        y = int(rest[i:])
        return x, y, w, h
    except ValueError:
        return None


def walk_pose(phase: float) -> dict[str, float]:
    """Return limb angles (radians) for a simple bipedal walk cycle.

    phase is in [0, 1). Opposite limbs are 180 deg out of phase.
    """
    # Hip swing ~ +/- 28 deg; knee bends on the forward recovery.
    swing = math.sin(phase * math.tau)
    other = math.sin(phase * math.tau + math.pi)
    leg_l = 0.48 * swing
    leg_r = 0.48 * other
    # Knee flex when leg is swinging forward (positive swing).
    knee_l = 0.55 * max(0.0, -swing)
    knee_r = 0.55 * max(0.0, -other)
    arm_l = 0.40 * other  # arms counter leg
    arm_r = 0.40 * swing
    bob = 2.0 * abs(math.sin(phase * math.tau * 2.0))
    return {
        "leg_l": leg_l,
        "leg_r": leg_r,
        "knee_l": knee_l,
        "knee_r": knee_r,
        "arm_l": arm_l,
        "arm_r": arm_r,
        "bob": bob,
    }


def limb_end(x: float, y: float, angle: float, length: float) -> tuple[float, float]:
    # angle 0 = straight down; positive = clockwise (screen y grows downward).
    return x + length * math.sin(angle), y + length * math.cos(angle)


class WalkerApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Hello World")
        self.root.minsize(MIN_WIDTH, MIN_HEIGHT)
        self.root.configure(bg=BG)

        saved = load_geometry()
        if saved is not None:
            self.root.geometry(f"{saved['w']}x{saved['h']}+{saved['x']}+{saved['y']}")
        else:
            self.root.geometry(f"{DEFAULT_WIDTH}x{DEFAULT_HEIGHT}")

        # Window icon: .ico works on Windows via iconbitmap. On macOS the Desktop
        # .app bundle supplies the Dock icon (hello_world.icns); Tk may ignore .ico.
        icon_path = Path(__file__).resolve().parent / "hello_world.ico"
        if icon_path.is_file():
            try:
                self.root.iconbitmap(default=str(icon_path))
            except tk.TclError:
                pass

        self.canvas = tk.Canvas(self.root, bg=BG, highlightthickness=0, bd=0)
        self.canvas.pack(expand=True, fill=tk.BOTH)

        self.phase = 0.0
        self.x = 40.0
        self._after_id: str | None = None
        self._geometry_checked = False
        self.root.bind("<Configure>", self._on_configure)
        self._tick()

    def _on_configure(self, _event: tk.Event | None = None) -> None:
        # Redraw immediately on resize so the figure stays centered vertically.
        self._draw()
        # First real map/resize: if restored coords are off-screen, re-center defaults.
        if not self._geometry_checked:
            try:
                if int(self.root.winfo_width()) >= MIN_WIDTH and int(self.root.winfo_height()) >= MIN_HEIGHT:
                    self._geometry_checked = True
                    self._ensure_on_screen()
            except tk.TclError:
                pass

    def _ensure_on_screen(self) -> None:
        """If the restored top-left is off every screen, fall back to default size centered."""
        try:
            self.root.update_idletasks()
            x = int(self.root.winfo_x())
            y = int(self.root.winfo_y())
            w = int(self.root.winfo_width())
            h = int(self.root.winfo_height())
            sw = int(self.root.winfo_screenwidth())
            sh = int(self.root.winfo_screenheight())
        except tk.TclError:
            return
        # Require a minimum overlap with the primary virtual screen bounds.
        # (Multi-monitor virtual desktop still reports a large screenwidth/height on Windows.)
        margin = 40
        on_screen = (x + w > margin) and (y + h > margin) and (x < sw - margin) and (y < sh - margin)
        if not on_screen:
            self.root.geometry(f"{DEFAULT_WIDTH}x{DEFAULT_HEIGHT}")
            self.root.update_idletasks()
            try:
                self.root.geometry(
                    f"+{(sw - DEFAULT_WIDTH) // 2}+{(sh - DEFAULT_HEIGHT) // 2}"
                )
            except tk.TclError:
                pass

    def persist_geometry(self) -> None:
        """Write current window position and size for the next launch."""
        try:
            self.root.update_idletasks()
            # Prefer parsing geometry() ("WxH+X+Y", X/Y may be negative) so we
            # round-trip the same values Tk accepts on the next geometry() call.
            geo = self.root.geometry()
            parsed = _parse_geometry(geo)
            if parsed is not None:
                x, y, w, h = parsed
            else:
                x = int(self.root.winfo_x())
                y = int(self.root.winfo_y())
                w = int(self.root.winfo_width())
                h = int(self.root.winfo_height())
            save_geometry(x, y, max(MIN_WIDTH, w), max(MIN_HEIGHT, h))
        except (tk.TclError, ValueError):
            pass

    def _tick(self) -> None:
        self.phase = (self.phase + 0.045) % 1.0
        w = max(self.canvas.winfo_width(), 1)
        # Scale speed lightly with width so a lap takes a similar time.
        speed = WALK_SPEED * max(w / 400.0, 0.75)
        self.x += speed
        if self.x > w + 40:
            self.x = -40.0
        self._draw()
        self._after_id = self.root.after(FRAME_MS, self._tick)

    def _draw(self) -> None:
        c = self.canvas
        c.delete("all")
        w = max(c.winfo_width(), 1)
        h = max(c.winfo_height(), 1)

        # Scale figure with the shorter window dimension; baseline fits 200px height.
        scale = min(w / 400.0, h / 200.0)
        scale = max(scale, 0.55)

        pose = walk_pose(self.phase)
        cx = self.x
        cy = h * 0.55 + pose["bob"] * scale

        head_r = 12 * scale
        torso = 34 * scale
        upper_leg = 22 * scale
        lower_leg = 20 * scale
        upper_arm = 16 * scale
        lower_arm = 14 * scale
        stroke = max(2, int(round(3 * scale)))

        hip_y = cy + torso
        shoulder_y = cy + 8 * scale
        head_cx, head_cy = cx, cy - head_r - 2 * scale

        # Ground line
        ground_y = hip_y + upper_leg + lower_leg + 4 * scale
        c.create_line(0, ground_y, w, ground_y, fill="#2a2a44", width=max(1, stroke - 1))

        # Torso
        c.create_line(cx, cy, cx, hip_y, fill=FG, width=stroke, capstyle=tk.ROUND)

        # Head
        c.create_oval(
            head_cx - head_r,
            head_cy - head_r,
            head_cx + head_r,
            head_cy + head_r,
            outline=FG,
            width=stroke,
        )

        # Hat: brim + flat crown (top hat)
        brim_w = head_r * 1.7
        brim_y = head_cy - head_r * 0.55
        c.create_line(
            head_cx - brim_w,
            brim_y,
            head_cx + brim_w,
            brim_y,
            fill=HAT,
            width=stroke,
            capstyle=tk.ROUND,
        )
        crown_w = head_r * 1.05
        crown_h = head_r * 1.15
        c.create_rectangle(
            head_cx - crown_w,
            brim_y - crown_h,
            head_cx + crown_w,
            brim_y,
            outline=HAT,
            width=stroke,
        )

        # Arms from shoulders
        for ang, elbow_bend in (
            (pose["arm_l"], 0.25),
            (pose["arm_r"], 0.25),
        ):
            ex, ey = limb_end(cx, shoulder_y, ang, upper_arm)
            hx, hy = limb_end(ex, ey, ang + elbow_bend, lower_arm)
            c.create_line(cx, shoulder_y, ex, ey, fill=FG, width=stroke, capstyle=tk.ROUND)
            c.create_line(ex, ey, hx, hy, fill=FG, width=stroke, capstyle=tk.ROUND)

        # Legs from hips with simple knee
        for hip_ang, knee in ((pose["leg_l"], pose["knee_l"]), (pose["leg_r"], pose["knee_r"])):
            kx, ky = limb_end(cx, hip_y, hip_ang, upper_leg)
            fx, fy = limb_end(kx, ky, hip_ang + knee, lower_leg)
            c.create_line(cx, hip_y, kx, ky, fill=FG, width=stroke, capstyle=tk.ROUND)
            c.create_line(kx, ky, fx, fy, fill=FG, width=stroke, capstyle=tk.ROUND)

    def shutdown(self) -> None:
        if self._after_id is not None:
            self.root.after_cancel(self._after_id)
            self._after_id = None


def _tk_patchlevel() -> str:
    try:
        return str(tk.Tcl().eval("info patchlevel"))
    except tk.TclError:
        return "unknown"


def _tk_is_usable() -> bool:
    """Apple's system Tk 8.5 on modern macOS often paints an empty Canvas."""
    try:
        parts = [int(p) for p in _tk_patchlevel().split(".")[:2]]
        while len(parts) < 2:
            parts.append(0)
        return tuple(parts[:2]) >= (8, 6)
    except ValueError:
        return True  # don't block unknown formats


def main() -> None:
    # Fail fast with a clear message instead of a blank dark window (macOS system Tk 8.5).
    if sys.platform == "darwin" and not _tk_is_usable():
        msg = (
            f"This Python's Tk {_tk_patchlevel()} cannot reliably draw the walker "
            f"on macOS (need Tk 8.6+).\n"
            f"Python: {sys.executable}\n"
            f"Install/use Homebrew Python instead, then recreate the Desktop app:\n"
            f"  brew install python python-tk\n"
            f"  /opt/homebrew/bin/python3 hello_world.py\n"
            f"  ./create_shortcut_macos.sh\n"
        )
        try:
            root = tk.Tk()
            root.withdraw()
            from tkinter import messagebox

            messagebox.showerror("Hello World — Tk too old", msg)
            root.destroy()
        except Exception:
            print(msg, file=sys.stderr)
        raise SystemExit(1)

    root = tk.Tk()
    app = WalkerApp(root)

    def on_close() -> None:
        app.persist_geometry()
        app.shutdown()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
