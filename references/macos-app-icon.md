# macOS App Icon (`.icns` / iconset / Dock icon)

Use when the deliverable is a **real macOS application icon** — not just icon artwork, but a
`.icns` (+ `.iconset` + a 1024² `AppIcon.png`) ready to drop into an app bundle / SwiftPM
resources. Triggers: "做成 mac 应用图标", "app icon", "Dock 图标", ".icns", "iconset",
"把这个 logo 做成应用图标".

This is a **post-processing pipeline on top of icon artwork**, not a new generation type. The
art can come from three places:

1. **The user hands you an image / website logo** — go straight to Step 1.
2. **The user references cutout art from `references/logo-icon.md`** — go straight to Step 1.
3. **The user gives you NO image**, just "做一个 XX 的 mac 应用图标" — do **Step 0** first to
   generate the icon art, then continue. This is common; do not ask the user for a source image
   when the request is "make me an app icon for X".

Load first:
- `references/generation.md` (for `gen_image_apiyi` + metadata helpers — always, since Step 0 and
  the metadata write need it)
- `references/prompt-compliance.md` (if generating in Step 0)
- `references/post-process.md`

---

## Step 0 — no source image? generate the icon art first

When the user gives no image, generate a **square, full-frame icon scene** (1024×1024), NOT a
transparent cutout. An app icon needs a background; a full-bleed scene masks into a clean squircle
in Step 1. (This is exactly how the Owlet owl-on-a-lake icon was made.)

Prompt shape — a single centered subject on a self-contained background that fills the frame:

```text
A square app icon of <SUBJECT>. Single clear subject, centered, filling most of the frame with
even margin. Self-contained <gradient / scene / solid> background that reaches all four edges.
<style: e.g. cute pixel-art / flat / 3D glossy>. Cohesive palette: <colors>.
no text, no letters, no words, no UI, no photo border, no drop shadow outside the artwork,
no rounded-rectangle frame baked in, no app-store mockup.
```

Notes:
- **Do not** append the `logo-icon.md` transparent-background block here — for an app icon you
  WANT a filled background, not a cutout.
- Tell the model **not** to bake its own rounded-rectangle tile/padding — we apply the squircle
  ourselves. Models often ignore this and return a padded tile anyway; that's fine, the Step 1
  autocrop removes the padding.
- Generate at `1024x1024`, GPT → Gemini (same fallback as logo/icon; no Doubao — its
  watermark crop wrecks icon edges).

```bash
OUT_DIR="${OUT_DIR:-$HOME/Pictures/better-imagegen}"; mkdir -p "$OUT_DIR"
ART="/tmp/icon_art.png"
PROMPT="$ICON_PROMPT"
if   GEN_LOG=$(gen_image_apiyi "$MODEL_GPT"    "1024x1024" "$ART"); then MODEL_USED="$MODEL_GPT"
elif GEN_LOG=$(gen_image_apiyi "$MODEL_GEMINI" "1024x1024" "$ART"); then MODEL_USED="$MODEL_GEMINI"
else echo "ICON_ART_GENERATION_FAILED"; exit 1
fi
SIZE="1024x1024"
GENERATION_MS=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^ELAPSED_MS:/{v=$2} END{print v+0}')
RESPONSE_FORMAT=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^RESPONSE_FORMAT:/{v=$2} END{print v}')
# then feed $ART into Step 1 as SRC (SRC="$ART")
```

If instead you already have a **transparent cutout** (from `logo-icon.md`), skip the Step 1
autocrop: paste the cutout centered onto a colored/gradient squircle you draw yourself, rather
than masking padding off a scene.

---

## The core problem

macOS does **not** round or mask app icons for you — the pixels you ship are exactly what shows
in the Dock. Two failure modes to avoid:

1. **AI "app icon" art with baked padding.** Models love to return a rounded tile floating on a
   solid dark/light background with a drop shadow (e.g. a squircle inset with ~12% margin).
   Ship that as-is and you get a **"tile inside a tile"** — a dark square with a smaller rounded
   card in the middle. Not native.
2. **Full-bleed square art.** Ship a plain square and macOS shows sharp corners — every other
   icon in the Dock is a squircle, so yours looks broken.

Fix: **extract the real artwork, then apply one clean macOS squircle mask** with transparent
corners so the icon is a proper edge-to-edge squircle.

---

## Squircle geometry

- Apple's icon shape is a continuous-corner superellipse. A rounded rectangle with
  **corner radius ≈ `0.2237 × side`** is a very close approximation and is indistinguishable at
  icon sizes. (This is the same `0.2237` used in Argos' `AppIconImage.swift` fallback.)
- **Margin:** Apple's grid leaves ~10% transparent margin for the system shadow. For menu-bar /
  indie apps an **edge-to-edge or ~4–5% margin** squircle reads bolder and crisper. Default to a
  small margin (`~0.045 × canvas`); go edge-to-edge only if the user wants maximum weight.
- Antialias the mask edge with a `GaussianBlur(0.6)` so the squircle border isn't jagged.

---

## Step 1 — build a 1024² RGBA master

`gen_macos_icon_master.py` — autocrops baked padding, squares the art, applies the squircle.
Handles both "padded tile" art and already-tight art (the autocrop just becomes a no-op).

```python
#!/usr/bin/env python3
"""AI/website icon art -> native macOS app icon master (1024 RGBA squircle)."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

SRC = os.environ["SRC"]                      # source art (png/webp/jpg)
OUT = os.environ.get("MASTER", "/tmp/icon_master.png")
MARGIN_FRAC = float(os.environ.get("MARGIN_FRAC", "0.045"))  # 0.0 = edge-to-edge
THRESH = int(os.environ.get("CROP_THRESH", "42"))            # bg-diff sensitivity

im = Image.open(SRC).convert("RGB")
W, H = im.size

# --- autocrop the inner artwork off any solid padding ---
# background colour = mean of the 4 corners; a padded tile differs strongly from it.
corners = [im.getpixel((2, 2)), im.getpixel((W - 3, 2)),
           im.getpixel((2, H - 3)), im.getpixel((W - 3, H - 3))]
bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))
px = im.load()
minx, miny, maxx, maxy = W, H, 0, 0
for y in range(0, H, 2):
    for x in range(0, W, 2):
        r, g, b = px[x, y]
        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > THRESH:
            minx, maxx = min(minx, x), max(maxx, x)
            miny, maxy = min(miny, y), max(maxy, y)
if maxx <= minx or maxy <= miny:             # no padding detected -> use whole image
    minx, miny, maxx, maxy = 0, 0, W, H
pad = int(0.010 * W)                          # drop the soft drop-shadow ring
minx, miny = max(0, minx + pad), max(0, miny + pad)
maxx, maxy = min(W, maxx - pad), min(H, maxy - pad)

# square, centered on the artwork
cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
half = max(maxx - minx, maxy - miny) / 2
box = (max(0, int(cx - half)), max(0, int(cy - half)),
       min(W, int(cx + half)), min(H, int(cy + half)))
tile = im.crop(box)
print(f"bg={bg} crop={box} tile={tile.size}")

# --- place on transparent canvas + squircle mask ---
S = 1024
margin = int(S * MARGIN_FRAC)
content = S - 2 * margin
tile = tile.resize((content, content), Image.LANCZOS).convert("RGBA")
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
canvas.paste(tile, (margin, margin))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [margin, margin, S - margin - 1, S - margin - 1],
    radius=int(content * 0.2237), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(0.6))

out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
out.paste(canvas, (0, 0), mask)
out.save(OUT)
print("saved", OUT, out.size)
```

If the source art is a **transparent cutout** (from `logo-icon.md`), skip autocrop: paste it
centered on a colored/gradient squircle instead of masking the padding. Most "make my logo an app
icon" requests, though, come from a padded AI tile and the script above just works.

**Preview before committing to the full iconset:** render a 512 downscale of the master and
actually view it. Check: artwork centered, corners cleanly transparent (not sharp, not double
-framed), no important pixels clipped by the squircle.

```bash
SRC="/path/to/art.webp" MASTER=/tmp/icon_master.png "$BETTER_IMAGEGEN_PYTHON" gen_macos_icon_master.py
"$BETTER_IMAGEGEN_PYTHON" -c "from PIL import Image; Image.open('/tmp/icon_master.png').resize((512,512)).save('/tmp/icon_preview.png')"
# then view /tmp/icon_preview.png
```

---

## Step 2 — iconset → `.icns`

```bash
MASTER=/tmp/icon_master.png
ICONSET=/tmp/AppIcon.iconset
NAME="${ICON_NAME:-AppIcon}"     # base name for the .icns
OUT_DIR="${OUT_DIR:-$HOME/Pictures/better-imagegen}"
mkdir -p "$OUT_DIR"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
gen() { "$BETTER_IMAGEGEN_PYTHON" -c "from PIL import Image; Image.open('$MASTER').resize(($1,$1), Image.LANCZOS).save('$ICONSET/$2')"; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$OUT_DIR/$NAME.icns"

# deliverables: the .icns, a 1024 AppIcon.png (Dock/⌘-Tab/DMG art), and metadata
cp "$MASTER" "$OUT_DIR/$NAME.png"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT_DIR/$NAME.icns" | tail -3
```

The 10-entry size table above is the full macOS set (16→1024 across @1x/@2x). `iconutil` is
part of Xcode command line tools; no extra deps. All resizes come from the single 1024 master —
never upscale a small source.

---

## Step 3 — wire into an app (if asked)

For a SwiftPM / `.app` bundle (e.g. Argos/Owlet):

- Drop `<Name>.icns` into the app's resources and set `CFBundleIconFile` = `<Name>` (no
  extension) in `Info.plist`. The build script copies the `.icns` into
  `Contents/Resources/`.
- Keep a 1024² `AppIcon.png` (RGBA) alongside for Dock/⌘-Tab rendering when run from SwiftPM, and
  for DMG volume/background art.
- Rebuild and verify the bundled icon: `sips -g pixelWidth <App>.app/Contents/Resources/<Name>.icns`
  and `PlistBuddy -c "Print :CFBundleIconFile"`.

Do **not** commit unrelated working-tree changes when installing the icon — stage only the icon
files.

---

## Deliverables checklist

- `<Name>.icns` (built via `iconutil`, contains all 10 sizes)
- `<Name>.png` — 1024² RGBA master (Dock / ⌘-Tab / DMG)
- `<Name>.iconset/` — optional, keep if the user wants the raw set
- metadata `.json` (reuse `write_image_metadata` from `generation.md`)
- Verified: `sips -g hasAlpha` shows the master has alpha; preview visually confirms a clean
  edge-to-edge squircle with transparent corners.
```
