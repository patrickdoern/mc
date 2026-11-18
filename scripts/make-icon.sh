#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d)"
python3 - "$work" <<'PY'
import sys
from PIL import Image, ImageDraw
work = sys.argv[1]
source = Image.open("icon/logo.png").convert("RGB")
red, green, blue = source.split()
mask_blue = Image.new("L", source.size, 0)
mask_blue.putdata([255 if b - r > 90 and b > 200 else 0 for r, b in zip(red.getdata(), blue.getdata())])
left, top, right, bottom = mask_blue.getbbox()
side = min(right - left, bottom - top) - 2
crop = source.crop((left + 1, top + 1, left + 1 + side, top + 1 + side)).resize((824 * 4, 824 * 4), Image.LANCZOS)
mask = Image.new("L", crop.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, crop.size[0] - 1, crop.size[1] - 1), radius=int(crop.size[0] * 0.235), fill=255)
body = crop.convert("RGBA")
body.putalpha(mask)
body = body.resize((824, 824), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
canvas.paste(body, (100, 100), body)
canvas.save(work + "/icon_1024.png")
PY
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$work/icon_1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$work/icon_1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o ../Sources/MC/Resources/AppIcon.icns
rm -rf "$work"
echo Sources/MC/Resources/AppIcon.icns
