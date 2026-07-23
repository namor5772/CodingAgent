"""Minimal Tkinter app that displays HELLO WORLD."""

import tkinter as tk
from pathlib import Path


def main() -> None:
    root = tk.Tk()
    root.title("Hello World")
    root.geometry("400x200")
    root.minsize(300, 150)
    root.configure(bg="#1a1a2e")

    # Prefer the bundled icon when present (window title-bar / taskbar).
    icon_path = Path(__file__).resolve().parent / "hello_world.ico"
    if icon_path.is_file():
        try:
            root.iconbitmap(default=str(icon_path))
        except tk.TclError:
            pass

    label = tk.Label(
        root,
        text="HELLO WORLD",
        font=("Segoe UI", 32, "bold"),
        fg="#eaeaea",
        bg="#1a1a2e",
    )
    label.pack(expand=True, fill=tk.BOTH)

    root.mainloop()


if __name__ == "__main__":
    main()
