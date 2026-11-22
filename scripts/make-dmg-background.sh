#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for scale in 1 2; do
python3 - "$work/background_$scale.png" "$scale" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont
path, s = sys.argv[1], int(sys.argv[2])
blue, cyan, yellow, frame = (0, 0, 158), (115, 242, 242), (255, 230, 51), (191, 191, 242)
image = Image.new("RGB", (640 * s, 400 * s), blue)
draw = ImageDraw.Draw(image)
def font(size, bold=False):
    return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", size * s, index=1 if bold else 0)
for inset in (10, 14):
    draw.rectangle((inset * s, inset * s, (640 - inset) * s - 1, (400 - inset) * s - 1), outline=frame, width=s)
title = " Moonlight Commander "
title_font = font(18, bold=True)
width = draw.textlength(title, font=title_font)
draw.rectangle(((640 * s - width) / 2, 0, (640 * s + width) / 2, 26 * s), fill=blue)
draw.text((320 * s, 12 * s), title, font=title_font, fill=cyan, anchor="mm")
draw.text((320 * s, 182 * s), "═════►", font=font(30), fill=yellow, anchor="mm")
for center in (160, 480):
    draw.rectangle(((center - 95) * s, 257 * s, (center + 95) * s, 279 * s), fill=cyan)
hint = "Zum Installieren auf „Applications“ ziehen"
draw.text((320 * s, 322 * s), hint, font=font(13), fill=cyan, anchor="mm")
draw.text((320 * s, 344 * s), "Drag to Applications to install", font=font(13), fill=frame, anchor="mm")
image.save(path)
PY
done
tiffutil -cathidpicheck "$work/background_1.png" "$work/background_2.png" -out dmg-background.tiff >/dev/null
echo scripts/dmg-background.tiff
