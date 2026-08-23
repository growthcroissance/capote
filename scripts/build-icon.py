#!/usr/bin/env python3

import argparse
import struct
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_ICONSET_DIR = PROJECT_DIR / "packaging" / "AppIcon.iconset"
DEFAULT_OUTPUT_PATH = PROJECT_DIR / "packaging" / "Capote.icns"

REPRESENTATIONS = (
    (b"icp4", "icon_16x16.png", 16),
    (b"ic11", "icon_16x16@2x.png", 32),
    (b"icp5", "icon_32x32.png", 32),
    (b"ic12", "icon_32x32@2x.png", 64),
    (b"ic07", "icon_128x128.png", 128),
    (b"ic13", "icon_128x128@2x.png", 256),
    (b"ic08", "icon_256x256.png", 256),
    (b"ic14", "icon_256x256@2x.png", 512),
    (b"ic09", "icon_512x512.png", 512),
    (b"ic10", "icon_512x512@2x.png", 1024),
)


def read_png(path: Path, expected_size: int) -> bytes:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"PNG invalide : {path}")

    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (expected_size, expected_size):
        raise ValueError(
            f"Dimensions inattendues pour {path}: {width} x {height}, "
            f"attendu {expected_size} x {expected_size}"
        )
    return data


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Construire l’icône ICNS de Capote")
    parser.add_argument("--iconset", type=Path, default=DEFAULT_ICONSET_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    chunks = []
    for chunk_type, filename, expected_size in REPRESENTATIONS:
        png_data = read_png(args.iconset / filename, expected_size)
        chunks.append(chunk_type + struct.pack(">I", len(png_data) + 8) + png_data)

    payload = b"".join(chunks)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print(f"Icône créée : {args.output}")


if __name__ == "__main__":
    main()
