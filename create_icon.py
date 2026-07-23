"""Generate hello_world.ico — a simple blue rounded tile with a white 'H'."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def make_icon(path: Path) -> None:
    sizes = [16, 32, 48, 64, 128, 256]
    images: list[Image.Image] = []

    for size in sizes:
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        # Rounded square background (indigo / deep blue).
        margin = max(1, size // 16)
        radius = max(2, size // 5)
        draw.rounded_rectangle(
            [margin, margin, size - margin - 1, size - margin - 1],
            radius=radius,
            fill=(67, 97, 238, 255),  # #4361ee
        )

        # Centered bold "H".
        font_size = max(10, int(size * 0.55))
        font = None
        for name in (
            "segoeuib.ttf",
            "arialbd.ttf",
            "C:/Windows/Fonts/segoeuib.ttf",
            "C:/Windows/Fonts/arialbd.ttf",
            "C:/Windows/Fonts/arial.ttf",
        ):
            try:
                font = ImageFont.truetype(name, font_size)
                break
            except OSError:
                continue
        if font is None:
            font = ImageFont.load_default()

        text = "H"
        bbox = draw.textbbox((0, 0), text, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = (size - tw) / 2 - bbox[0]
        y = (size - th) / 2 - bbox[1]
        draw.text((x, y), text, font=font, fill=(255, 255, 255, 255))

        images.append(img)

    path.parent.mkdir(parents=True, exist_ok=True)
    # Pillow ICO: pass all frames via append_images; sizes= lists each dimension.
    largest = images[-1]
    largest.save(
        path,
        format="ICO",
        sizes=[(im.width, im.height) for im in images],
        append_images=images[:-1],
    )
    print(f"Wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    make_icon(Path(__file__).resolve().parent / "hello_world.ico")
