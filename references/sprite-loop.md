# Sprite Loop

Use for short looping frame animations like the macOS menu-bar app RunCat, loading indicators, tiny mascots, app status animations, game sprites, and widget loops.

The professional term to use in this skill is **sprite loop**: a frame-by-frame looping animation asset delivered as a numbered sprite sequence, plus optional preview formats.

Load first:
- `references/generation.md`
- `references/prompt-compliance.md`
- `references/post-process.md`

---

## Defaults

| Field | Value |
|---|---|
| Output directory | `~/Pictures/better-imagegen/sprite-loop/{slug}/` |
| Source image | `sprite-sheet.png` |
| Frame output | `frames/frame-001.png` ... |
| Preview output | `preview.gif` |
| Manifest | `manifest.json` |
| Default frames | 12 |
| Sprite sheet layout | 4 columns x 3 rows |
| Frame size | `256x256` |
| Model flow | Gemini `1280x960` → GPT `1280x960` (no Doubao — watermark crop and upscale break the sprite grid) |

The source sheet is a generation target, not the final asset. Split it into frames and verify the loop.

---

## Prompt Template

Generate a sprite sheet, not a single illustration:

```text
Create a professional sprite sheet for a tiny looping app-status animation.
Subject: <user subject>.
Action: <loop action, e.g. running, breathing, typing, loading, bouncing>.
Layout: 4 columns by 3 rows, 12 equal frames, left-to-right then top-to-bottom.
Consistent character design, same scale, centered in every cell, transparent background, alpha channel.
Keep the complete subject inside the central 76% of every cell, with at least 12% transparent safety padding on all four sides. Wings, tails, hair, props, effects, and shadows must never touch or cross a cell boundary. Keep a visibly empty transparent gutter between neighboring frames. Each cell must contain exactly one complete pose; never continue a clipped body part into the next cell and never leave a detached fragment from a neighboring pose.
Clean silhouette readable at 22px menu-bar size. No text, no watermark, no grid lines in the final art.
The first and last frames must connect smoothly for a seamless loop.
```

For RunCat-like requests, default action is `running loop`, with side-view silhouette and clear leg motion.

---

## Pipeline

```bash
SLUG="${OUTPUT_NAME:-sprite-loop}"
OUT_DIR="$HOME/Pictures/better-imagegen/sprite-loop/$SLUG"
FRAME_DIR="$OUT_DIR/frames"
mkdir -p "$FRAME_DIR"

OUTPUT_PATH="/tmp/${SLUG}_sheet.png"
SHEET_PATH="$OUT_DIR/sprite-sheet.png"

if   GEN_LOG=$(gen_image_apiyi "$MODEL_GPT"    "1280x960" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_GPT"
elif GEN_LOG=$(gen_image_apiyi "$MODEL_GEMINI" "1280x960" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_GEMINI"
else echo "SPRITE_LOOP_GENERATION_FAILED"; exit 1
fi
SIZE="1280x960"

GENERATION_MS=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^ELAPSED_MS:/{v=$2} END{print v+0}')
RESPONSE_FORMAT=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^RESPONSE_FORMAT:/{v=$2} END{print v}')

mv "$OUTPUT_PATH" "$SHEET_PATH"

# Hard gate: never split or deliver a sheet whose poses touch cell guard bands
# or contain substantial detached fragments. Regenerate the source sheet instead.
: "${SKILL_DIR:?Set SKILL_DIR to the installed better-imagegen directory (the directory containing SKILL.md).}"
"$BETTER_IMAGEGEN_PYTHON" "$SKILL_DIR/scripts/validate_sprite_cells.py" "$SHEET_PATH" \
  --columns 4 --rows 3 --guard-ratio 0.08 \
  --json-out "$OUT_DIR/cell-boundary-validation.json"

"$BETTER_IMAGEGEN_PYTHON" - "$SHEET_PATH" "$FRAME_DIR" "$OUT_DIR/preview.gif" <<'PY'
import os, sys, json, time
from PIL import Image

sheet_path, frame_dir, gif_path = sys.argv[1:]
cols, rows = 4, 3
target = 256
os.makedirs(frame_dir, exist_ok=True)

sheet = Image.open(sheet_path).convert("RGBA")
w, h = sheet.size
cell_w, cell_h = w // cols, h // rows
frames = []
frame_paths = []
for idx in range(cols * rows):
    x = (idx % cols) * cell_w
    y = (idx // cols) * cell_h
    frame = sheet.crop((x, y, x + cell_w, y + cell_h)).resize((target, target), Image.LANCZOS)
    frame_path = os.path.join(frame_dir, f"frame-{idx + 1:03d}.png")
    frame.save(frame_path)
    frames.append(frame)
    frame_paths.append(frame_path)

frames[0].save(gif_path, save_all=True, append_images=frames[1:], duration=80, loop=0, disposal=2)
manifest = {
    "type": "sprite-loop",
    "frame_count": len(frames),
    "frame_size": f"{target}x{target}",
    "layout": f"{cols}x{rows}",
    "frame_duration_ms": 80,
    "frames": frame_paths,
    "preview": gif_path,
    "source_sheet": sheet_path,
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
}
with open(os.path.join(os.path.dirname(gif_path), "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

POSTPROCESS_NOTE="split 4x3 sprite sheet into 12 256x256 png frames; preview gif 80ms"
write_image_metadata "$SHEET_PATH" "$OUT_DIR/sprite-sheet.json" "$MODEL_USED" "$SIZE" "$GENERATION_MS" "$RESPONSE_FORMAT" "$POSTPROCESS_NOTE"

META_FILES=("$OUT_DIR/sprite-sheet.json")
for FRAME_PATH in "$FRAME_DIR"/frame-*.png; do
  write_image_metadata "$FRAME_PATH" "${FRAME_PATH%.*}.json" "$MODEL_USED" "derived-from-$SIZE" "$GENERATION_MS" "$RESPONSE_FORMAT" "derived sprite frame from generated sheet"
  META_FILES+=("${FRAME_PATH%.*}.json")
done
write_image_metadata "$OUT_DIR/preview.gif" "$OUT_DIR/preview.json" "$MODEL_USED" "derived-from-$SIZE" "$GENERATION_MS" "$RESPONSE_FORMAT" "animated preview gif from sprite frames"
META_FILES+=("$OUT_DIR/preview.json")
print_image_summary "${META_FILES[@]}"
open "$OUT_DIR/preview.gif"
```

---

## Quality Checks

- **Mandatory clipping gate:** run `scripts/validate_sprite_cells.py` on the source sheet before splitting and again on any assembled atlas. A non-zero exit is a hard failure: regenerate/re-layout; do not erase the fragment, crop tighter, or claim the result is valid.
- When the source sheet uses a flat matte instead of alpha, pass `--chroma-key '#RRGGBB'`; otherwise the matte hides slot-boundary crossings from an alpha-only check.
- Every complete pose, including wings, tails, hair, glow, props, and shadows, must remain inside its cell's safety inset. Fixed-grid cropping is forbidden when foreground reaches the guard band.
- Reject any cell with a substantial detached component. A fragment from the previous/next frame inside the nominal cell is still clipping corruption even when no pixel touches the final cell edge.
- Inspect the split-frame contact sheet, not only the unsplit source. Check first/last frames and the widest pose at 4× on checkerboard and solid backgrounds.
- At 22px, the silhouette should still read.
- Character scale should remain stable across frames.
- The first and last frames should loop without a visible jump.
- No text, grid lines, watermark, or baked background.
- If transparency fails, rerun with stronger transparent-background wording or remove edge-connected background during post-processing.
