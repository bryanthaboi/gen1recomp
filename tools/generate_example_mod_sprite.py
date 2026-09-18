#!/usr/bin/env python3
"""Create the inverted battle sprites used by the example native mod."""

from pathlib import Path
import sys

from PIL import Image, ImageOps

GBA_PIC = 64
MEW = 151


def invert_image(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    r, g, b, a = image.split()
    inverted = ImageOps.invert(Image.merge("RGB", (r, g, b)))
    inverted.putalpha(a)
    return inverted


def save(image: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)
    print(f"generated {destination} ({image.width}x{image.height})")


def invert(source: Path, destination: Path) -> None:
    save(invert_image(Image.open(source)), destination)


def invert_rgba(source: Path, destination: Path) -> None:
    raw = source.read_bytes()
    size = GBA_PIC * GBA_PIC * 4
    if len(raw) < size:
        raise SystemExit(f"{source}: expected {size} bytes of 64x64 RGBA, got {len(raw)}")
    image = Image.frombytes("RGBA", (GBA_PIC, GBA_PIC), raw[:size])
    save(invert_image(image), destination)


def main() -> int:
    args = sys.argv[1:]
    if len(args) not in (2, 3):
        print("usage: generate_example_mod_sprite.py <gen1-source-dir|-> <output-dir> "
              "[<firered-gba-cache-dir>]")
        print("  gen1-source-dir: an assets/generated dir (battle/front/mew.png); '-' skips it")
        print("  firered-gba-cache-dir: <identity>/firered/data/generated/gba "
              "(pokemon/front/151.rgba)")
        return 2
    source_dir, output_dir = args[0], Path(args[1])
    if source_dir != "-":
        source = Path(source_dir)
        invert(source / "battle/front/mew.png",
               output_dir / "assets/mew_front_inverted.png")
        invert(source / "battle/back/mewb.png",
               output_dir / "assets/mew_back_inverted.png")
    if len(args) == 3:
        gba = Path(args[2])
        invert_rgba(gba / f"pokemon/front/{MEW}.rgba",
                    output_dir / "assets/mew_front_inverted_64.png")
        invert_rgba(gba / f"pokemon/back/{MEW}.rgba",
                    output_dir / "assets/mew_back_inverted_64.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
