"""Minimal Tkinter app: stick figure with a hat walking across the window."""

from __future__ import annotations

import math
import tkinter as tk
from pathlib import Path

# Match prior chrome: dark bg, light strokes, default/min size.
BG = "#1a1a2e"
FG = "#eaeaea"
HAT = "#c9a227"  # muted gold brim/crown accent
FRAME_MS = 50
WALK_SPEED = 2.4  # px per frame at default scale baseline


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
        self.root.geometry("400x200")
        self.root.minsize(300, 150)
        self.root.configure(bg=BG)

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
        self.root.bind("<Configure>", self._on_configure)
        self._tick()

    def _on_configure(self, _event: tk.Event | None = None) -> None:
        # Redraw immediately on resize so the figure stays centered vertically.
        self._draw()

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


def main() -> None:
    root = tk.Tk()
    app = WalkerApp(root)

    def on_close() -> None:
        app.shutdown()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
