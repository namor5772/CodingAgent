"""Minimal Tkinter app: stick figure with a hat walking across the window.

Tab one: the walker and his trotting dog. Tab two: a dog chasing a bird —
the bird takes off just before the dog reaches it and flies on just ahead.
"""

from __future__ import annotations

import json
import math
import os
import sys
import tkinter as tk
from pathlib import Path
from tkinter import ttk

# Match prior chrome: dark bg, light strokes, default/min size.
BG = "#1a1a2e"
FG = "#eaeaea"
HAT = "#c9a227"  # muted gold brim/crown accent
FRAME_MS = 50
WALK_SPEED = 2.4  # px per frame at default scale baseline
CHASE_SPEED = 3.2  # px per frame at default scale baseline (tab two dog)
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
    """Return {x, y, w, h, tab} client geometry if the config is valid, else None."""
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
    # Selected tab is optional (older files) — anything but 1 means tab one.
    try:
        tab = int(data.get("tab", 0))
    except (TypeError, ValueError):
        tab = 0
    if tab not in (0, 1):
        tab = 0
    return {"x": x, "y": y, "w": w, "h": h, "tab": tab}


def save_geometry(x: int, y: int, w: int, h: int, tab: int = 0) -> None:
    path = _config_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "x": int(x),
            "y": int(y),
            "w": int(w),
            "h": int(h),
            "tab": 1 if tab == 1 else 0,
        }
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
    """Return limb angles (radians) for a bipedal walk cycle.

    phase is in [0, 1); the legs run 180 deg out of phase. Each hip swings
    A*sin(t) with +ve toward the walking direction (+x). Per leg: heel strike
    at full forward swing with the knee straight, near-straight stance while
    the body passes over the planted foot, then the heel lifts and the knee
    flexes through the forward swing, straightening again before the next
    heel strike. Knee flexion is one-signed (shin folds backward only) and is
    drawn as hip_angle - knee.
    """
    t = phase * math.tau
    leg_l = 0.45 * math.sin(t)
    leg_r = 0.45 * math.sin(t + math.pi)
    # cos(t + lead) > 0 from late stance through the forward swing; the 0.6
    # lead starts the heel lift just before toe-off and peaks mid-recovery.
    knee_l = 1.0 * max(0.0, math.cos(t + 0.6))
    knee_r = 1.0 * max(0.0, math.cos(t + math.pi + 0.6))
    # Feet (pi/2 = flat on the ground, toes forward): dorsiflex (toes up)
    # into heel strike, rock flat by mid-stance, then plantarflex (heel up,
    # toes down) through toe-off into early swing — the second term is knee
    # flexion gated to the leg being behind the body, which is exactly the
    # heel-lift window.
    foot_l = (
        math.pi / 2
        + 0.4 * max(0.0, math.sin(t))
        - 0.8 * knee_l * max(0.0, -math.sin(t))
    )
    foot_r = (
        math.pi / 2
        + 0.4 * max(0.0, math.sin(t + math.pi))
        - 0.8 * knee_r * max(0.0, -math.sin(t + math.pi))
    )
    arm_l = 0.40 * math.sin(t + math.pi)  # arms counter same-side legs
    arm_r = 0.40 * math.sin(t)
    # One bounce per step: tallest as the stance leg passes vertical, lowest
    # at full stride split. 4.2 = 42 * (1 - cos(0.45)) keeps the straight
    # leg's foot on the ground line at both extremes (leg = 42 px at scale 1).
    bob = 4.2 * abs(math.sin(t))
    return {
        "leg_l": leg_l,
        "leg_r": leg_r,
        "knee_l": knee_l,
        "knee_r": knee_r,
        "foot_l": foot_l,
        "foot_r": foot_r,
        "arm_l": arm_l,
        "arm_r": arm_r,
        "bob": bob,
    }


def dog_pose(phase: float) -> dict[str, float]:
    """Return angles (radians) for a trotting dog.

    Trot: diagonal leg pairs (front-left + rear-right, front-right +
    rear-left) move together, 180 deg apart, at the walker's cadence but
    offset so the trot is not step-synced with the man. Same conventions as
    walk_pose: folds are one-signed (lower leg drawn at angle - fold) and
    bob is px at scale 1.
    """
    t = phase * math.tau + 1.9
    pair_a = 0.60 * math.sin(t)  # front-left + rear-right
    pair_b = 0.60 * math.sin(t + math.pi)  # front-right + rear-left
    fold_a = 0.9 * max(0.0, math.cos(t + 0.6))
    fold_b = 0.9 * max(0.0, math.cos(t + math.pi + 0.6))
    tail = 0.25 * math.sin(t * 2.0)  # wag, twice per stride
    # 3.3 = 19 * (1 - cos(0.6)): the straight pair's paws stay on the ground
    # line at both stride extremes (dog leg = 19 px at scale 1).
    bob = 3.3 * abs(math.sin(t))
    return {
        "pair_a": pair_a,
        "pair_b": pair_b,
        "fold_a": fold_a,
        "fold_b": fold_b,
        "tail": tail,
        "bob": bob,
    }


def view_scale(w: float, h: float) -> float:
    """Figure scale for a client size: 400x200 baseline, floor 0.55."""
    return max(min(w / 400.0, h / 200.0), 0.55)


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

        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(expand=True, fill=tk.BOTH)

        tab_one = tk.Frame(self.notebook, bg=BG)
        self.canvas = tk.Canvas(tab_one, bg=BG, highlightthickness=0, bd=0)
        self.canvas.pack(expand=True, fill=tk.BOTH)
        self.notebook.add(tab_one, text="one")

        tab_two = tk.Frame(self.notebook, bg=BG)
        self.canvas_two = tk.Canvas(tab_two, bg=BG, highlightthickness=0, bd=0)
        self.canvas_two.pack(expand=True, fill=tk.BOTH)
        self.notebook.add(tab_two, text="two")

        if saved is not None and saved.get("tab") == 1:
            self.notebook.select(tab_two)

        self.phase = 0.0
        self.x = 40.0
        # Tab two chase scene: the dog runs in from the left; the bird waits
        # on the ground, then takes off just before the dog reaches it.
        self.chase_phase = 0.0
        self.chase_dog_x = -60.0
        self.bird_flying = False
        self.bird_fly_x = 0.0
        self.bird_alt = 0.0  # px climbed since takeoff (0 = perched)
        self.bird_flap = 0.0
        self._after_id: str | None = None
        self._geometry_checked = False
        self.root.bind("<Configure>", self._on_configure)
        self._tick()

    def _on_configure(self, _event: tk.Event | None = None) -> None:
        # Redraw immediately on resize so the figure stays centered vertically.
        self._draw()
        self._draw_chase()
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
        """Write current window position, size, and selected tab for the next launch."""
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
            try:
                tab = self.notebook.index(self.notebook.select())
            except (tk.TclError, ValueError):
                tab = 0
            save_geometry(x, y, max(MIN_WIDTH, w), max(MIN_HEIGHT, h), tab)
        except (tk.TclError, ValueError):
            pass

    def _tick(self) -> None:
        self.phase = (self.phase + 0.045) % 1.0
        w = max(self.canvas.winfo_width(), 1)
        h = max(self.canvas.winfo_height(), 1)
        # Scale speed lightly with width so a lap takes a similar time.
        speed = WALK_SPEED * max(w / 400.0, 0.75)
        self.x += speed
        # Wrap only once the trailing dog (tail ~90 px behind at scale 1) has
        # also left the right edge; both re-enter from the left, man first.
        if self.x > w + 40 + 90 * view_scale(w, h):
            self.x = -40.0
        self._draw()
        self._tick_chase()
        self._after_id = self.root.after(FRAME_MS, self._tick)

    def _draw(self) -> None:
        c = self.canvas
        c.delete("all")
        w = max(c.winfo_width(), 1)
        h = max(c.winfo_height(), 1)

        # Scale figure with the shorter window dimension; baseline fits 200px height.
        scale = view_scale(w, h)

        pose = walk_pose(self.phase)
        cx = self.x
        base_cy = h * 0.55  # un-bobbed body reference; anchors the ground line
        cy = base_cy + pose["bob"] * scale

        head_r = 12 * scale
        torso = 34 * scale
        upper_leg = 22 * scale
        lower_leg = 20 * scale
        foot_len = 8 * scale
        upper_arm = 16 * scale
        lower_arm = 14 * scale
        stroke = max(2, int(round(3 * scale)))

        hip_y = cy + torso
        shoulder_y = cy + 8 * scale
        head_cx, head_cy = cx, cy - head_r - 2 * scale

        # Ground line: anchored to the un-bobbed pose (does not bounce with the
        # body) at exactly straight-leg reach, so planted feet touch it.
        ground_y = base_cy + torso + upper_leg + lower_leg
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

        # Face (right profile, facing the walking direction): eye dot, nose
        # wedge poking past the head outline, short mouth line.
        face_w = max(1, stroke - 1)
        eye_r = max(1.2, head_r * 0.12)
        eye_x = head_cx + head_r * 0.38
        eye_y = head_cy - head_r * 0.18
        c.create_oval(
            eye_x - eye_r,
            eye_y - eye_r,
            eye_x + eye_r,
            eye_y + eye_r,
            fill=FG,
            outline=FG,
        )
        c.create_line(
            head_cx + head_r * 0.92,
            head_cy + head_r * 0.02,
            head_cx + head_r * 1.30,
            head_cy + head_r * 0.14,
            head_cx + head_r * 0.88,
            head_cy + head_r * 0.30,
            fill=FG,
            width=face_w,
            capstyle=tk.ROUND,
            joinstyle=tk.ROUND,
        )
        c.create_line(
            head_cx + head_r * 0.22,
            head_cy + head_r * 0.55,
            head_cx + head_r * 0.75,
            head_cy + head_r * 0.48,
            fill=FG,
            width=face_w,
            capstyle=tk.ROUND,
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
        # Crown interior is filled with the background color so the top of
        # the head circle (drawn earlier) is not visible inside the hat.
        c.create_rectangle(
            head_cx - crown_w,
            brim_y - crown_h,
            head_cx + crown_w,
            brim_y,
            outline=HAT,
            fill=BG,
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

        # Legs from hips; knee flexion folds the shin backward (heel toward
        # the body), so the knee vertex points in the walking direction. The
        # foot line is ground-anchored (angle is absolute, not shin-relative).
        for hip_ang, knee, foot_ang in (
            (pose["leg_l"], pose["knee_l"], pose["foot_l"]),
            (pose["leg_r"], pose["knee_r"], pose["foot_r"]),
        ):
            kx, ky = limb_end(cx, hip_y, hip_ang, upper_leg)
            fx, fy = limb_end(kx, ky, hip_ang - knee, lower_leg)
            tx_, ty_ = limb_end(fx, fy, foot_ang, foot_len)
            c.create_line(cx, hip_y, kx, ky, fill=FG, width=stroke, capstyle=tk.ROUND)
            c.create_line(kx, ky, fx, fy, fill=FG, width=stroke, capstyle=tk.ROUND)
            c.create_line(fx, fy, tx_, ty_, fill=FG, width=stroke, capstyle=tk.ROUND)

        # Dog trotting behind the walker, on the same ground line.
        self._draw_dog(c, cx - 65 * scale, ground_y, scale, dog_pose(self.phase))

    def _draw_dog(
        self,
        c: tk.Canvas,
        dog_cx: float,
        ground_y: float,
        scale: float,
        dpose: dict[str, float],
    ) -> None:
        """Stick-figure dog with its spine on the ground line (shared by both tabs).

        Drawn one stroke thinner than the walker so it reads as the smaller figure.
        """
        dog_w = max(1, max(2, int(round(3 * scale))) - 1)
        d_upper = 10 * scale
        d_lower = 9 * scale
        half_body = 14 * scale
        spine_y = ground_y - 19 * scale + dpose["bob"] * scale
        shoulder_x = dog_cx + half_body
        hip_x = dog_cx - half_body

        # Spine
        c.create_line(hip_x, spine_y, shoulder_x, spine_y, fill=FG, width=dog_w, capstyle=tk.ROUND)

        # Legs: both legs of a diagonal pair share angle/fold; front pair
        # hangs from the shoulder, rear pair from the hip.
        for ax, ang, fold in (
            (shoulder_x, dpose["pair_a"], dpose["fold_a"]),
            (shoulder_x, dpose["pair_b"], dpose["fold_b"]),
            (hip_x, dpose["pair_b"], dpose["fold_b"]),
            (hip_x, dpose["pair_a"], dpose["fold_a"]),
        ):
            kx, ky = limb_end(ax, spine_y, ang, d_upper)
            px_, py_ = limb_end(kx, ky, ang - fold, d_lower)
            c.create_line(ax, spine_y, kx, ky, fill=FG, width=dog_w, capstyle=tk.ROUND)
            c.create_line(kx, ky, px_, py_, fill=FG, width=dog_w, capstyle=tk.ROUND)

        # Tail: up-backward from the hip, wagging about its base angle.
        tx, ty = limb_end(hip_x, spine_y, math.pi + 0.55 + dpose["tail"], 12 * scale)
        c.create_line(hip_x, spine_y, tx, ty, fill=FG, width=dog_w, capstyle=tk.ROUND)

        # Neck (stops at the head outline), head, muzzle, ear, eye.
        c.create_line(
            shoulder_x,
            spine_y,
            shoulder_x + 4.1 * scale,
            spine_y - 5.9 * scale,
            fill=FG,
            width=dog_w,
            capstyle=tk.ROUND,
        )
        dh_x = shoulder_x + 7 * scale
        dh_y = spine_y - 10 * scale
        dh_r = 5 * scale
        c.create_oval(dh_x - dh_r, dh_y - dh_r, dh_x + dh_r, dh_y + dh_r, outline=FG, width=dog_w)
        c.create_line(
            dh_x + 3.5 * scale,
            dh_y + 0.8 * scale,
            dh_x + 10 * scale,
            dh_y + 2.2 * scale,
            fill=FG,
            width=dog_w,
            capstyle=tk.ROUND,
        )
        c.create_line(
            dh_x - 1.5 * scale,
            dh_y - 4 * scale,
            dh_x - 4 * scale,
            dh_y - 9.5 * scale,
            fill=FG,
            width=dog_w,
            capstyle=tk.ROUND,
        )
        der = max(1.0, 0.9 * scale)
        c.create_oval(
            dh_x + 1.8 * scale - der,
            dh_y - 1.2 * scale - der,
            dh_x + 1.8 * scale + der,
            dh_y - 1.2 * scale + der,
            fill=FG,
            outline=FG,
        )

    def _tick_chase(self) -> None:
        """Advance the tab two chase: the dog runs right; the bird flees just ahead."""
        c = self.canvas_two
        w = max(c.winfo_width(), 1)
        h = max(c.winfo_height(), 1)
        scale = view_scale(w, h)

        self.chase_phase = (self.chase_phase + 0.065) % 1.0
        speed = CHASE_SPEED * max(w / 400.0, 0.75)
        self.chase_dog_x += speed
        dog_nose_x = self.chase_dog_x + 31 * scale

        if not self.bird_flying:
            # Perched bird waits at a fixed spot; it takes off just before the
            # dog's nose reaches it.
            if w * 0.62 - dog_nose_x < 30 * scale:
                self.bird_flying = True
                self.bird_fly_x = w * 0.62
                self.bird_alt = 0.0
        else:
            self.bird_flap += 0.35
            # Climb to cruise height, just above the dog's reach. alt is in
            # px, so clamp it too in case the window shrank mid-flight.
            cruise = 52 * scale
            self.bird_alt = min(self.bird_alt, cruise)
            if self.bird_alt < cruise:
                self.bird_alt = min(cruise, self.bird_alt + 1.4 * scale)
            # Fly on just ahead of the dog (barely pulling away).
            self.bird_fly_x += speed + 0.2 * scale
            # Both off the right edge: restart the chase from the left.
            if self.bird_fly_x > w + 30 and self.chase_dog_x - 26 * scale > w:
                self.chase_dog_x = -60.0
                self.bird_flying = False
                self.bird_alt = 0.0
                self.bird_flap = 0.0
        self._draw_chase()

    def _draw_chase(self) -> None:
        c = self.canvas_two
        c.delete("all")
        w = max(c.winfo_width(), 1)
        h = max(c.winfo_height(), 1)
        scale = view_scale(w, h)
        stroke = max(2, int(round(3 * scale)))
        bird_w = max(1, stroke - 1)

        # Same ground height as tab one (h*0.55 body anchor + 34+22+20 leg reach).
        ground_y = h * 0.55 + 76.0 * scale
        c.create_line(0, ground_y, w, ground_y, fill="#2a2a44", width=max(1, stroke - 1))

        # Chasing dog: same figure as tab one's trot, driven by the chase phase.
        self._draw_dog(c, self.chase_dog_x, ground_y, scale, dog_pose(self.chase_phase))

        # Bird: perched on the ground until takeoff, then flapping just above
        # the dog, body bobbing with the wingbeat.
        if self.bird_flying:
            bx = self.bird_fly_x
            by = ground_y - 5 * scale - self.bird_alt + 1.5 * scale * math.sin(self.bird_flap)
        else:
            bx = w * 0.62
            by = ground_y - 5 * scale

        # Tail fanning from the rear of the body.
        c.create_line(bx - 5 * scale, by, bx - 9.5 * scale, by - 2.5 * scale, fill=FG, width=bird_w, capstyle=tk.ROUND)
        c.create_line(bx - 5 * scale, by, bx - 9 * scale, by + 1.5 * scale, fill=FG, width=bird_w, capstyle=tk.ROUND)
        # Body
        c.create_line(bx - 5 * scale, by, bx + 5.5 * scale, by, fill=FG, width=bird_w, capstyle=tk.ROUND)

        wing_x, wing_y = bx + 1.0 * scale, by - 0.5 * scale
        if self.bird_flying:
            # Two wings flapping out of phase (far wing slightly shorter).
            for phase_off, wing_len in ((0.0, 9.0), (0.9, 7.5)):
                ang = 2.36 - 1.1 * math.sin(self.bird_flap + phase_off)
                wx, wy = limb_end(wing_x, wing_y, ang, wing_len * scale)
                c.create_line(wing_x, wing_y, wx, wy, fill=FG, width=bird_w, capstyle=tk.ROUND)
            # Tucked feet trailing under the body.
            c.create_line(bx + 0.5 * scale, by + 0.5 * scale, bx + 2.5 * scale, by + 3 * scale, fill=FG, width=bird_w, capstyle=tk.ROUND)
        else:
            # Folded wing along the body; two legs down to the ground.
            c.create_line(wing_x, wing_y, bx - 6.5 * scale, by - 2 * scale, fill=FG, width=bird_w, capstyle=tk.ROUND)
            c.create_line(bx - 1 * scale, by, bx - 2 * scale, ground_y, fill=FG, width=bird_w, capstyle=tk.ROUND)
            c.create_line(bx + 2.5 * scale, by, bx + 2.5 * scale, ground_y, fill=FG, width=bird_w, capstyle=tk.ROUND)

        # Head, beak, eye.
        hx, hy, hr = bx + 8 * scale, by - 2.5 * scale, 3 * scale
        c.create_oval(hx - hr, hy - hr, hx + hr, hy + hr, outline=FG, width=bird_w)
        c.create_line(hx + 2.4 * scale, hy - 1.1 * scale, hx + 5.6 * scale, hy + 0.2 * scale, fill=FG, width=bird_w, capstyle=tk.ROUND)
        c.create_line(hx + 2.4 * scale, hy + 1.1 * scale, hx + 5.6 * scale, hy + 0.2 * scale, fill=FG, width=bird_w, capstyle=tk.ROUND)
        ber = max(0.8, 0.7 * scale)
        c.create_oval(
            hx + 0.8 * scale - ber,
            hy - 0.8 * scale - ber,
            hx + 0.8 * scale + ber,
            hy - 0.8 * scale + ber,
            fill=FG,
            outline=FG,
        )

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
