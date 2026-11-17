#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d)"
python3 - "$work" <<'PY'
import sys
from PIL import Image, ImageDraw
work = sys.argv[1]
source = Image.open("icon/logo.webp").convert("RGB")
luma = source.convert("L").point(lambda value: 255 if value < 90 else 0)
left, top, right, bottom = luma.getbbox()
side = min(right - left, bottom - top) - 2
crop = source.crop((left + 1, top + 1, left + 1 + side, top + 1 + side)).resize((824 * 4, 824 * 4), Image.LANCZOS)
mask = Image.new("L", crop.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, crop.size[0] - 1, crop.size[1] - 1), radius=int(crop.size[0] * 0.2237), fill=255)
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
iconutil -c icns "$iconset" -o icon/AppIcon.icns
rm -rf "$work"
echo icon/AppIcon.icns
