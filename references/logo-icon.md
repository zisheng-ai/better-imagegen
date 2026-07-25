# Logo / Icon / Transparent Asset

Use for logos, favicons, app icon source art, stickers, badges, mascots, cutouts, and any asset where transparency matters.

Load first:
- `references/generation.md`
- `references/prompt-compliance.md`
- `references/post-process.md`

---

## Defaults

| Field | Value |
|---|---|
| Output directory | project-local when requested, otherwise `~/Pictures/better-imagegen/` |
| Final format | `.png` for transparency-critical assets |
| Logo output | `512x512` PNG |
| Favicon output | `256x256` PNG |
| Model flow | Gemini `1280x1280` → GPT `1280x1280` (no Doubao — watermark crop and upscale can damage alpha edges) |

Use PNG for source art because alpha is easier to verify and preserve. Use WebP only when the user explicitly wants WebP.

---

## Prompt Hard Constraint

Append this block unless the user explicitly asks for a filled tile or mockup:

```text
Transparent-background source artwork. Isolated subject only. Preserve alpha channel. No background layer.
Avoid: black background, white background, solid square background, rounded rectangle container, app icon tile, mockup frame, border, drop shadow outside the subject, canvas, backdrop, wallpaper, scene.
The output must be usable as a cutout logo/icon asset; the OS or app will apply any rounded mask later.
```

Do not ask for "a rounded app icon" unless the user wants the rounded tile baked into the pixels.

---

## Pipeline

```bash
OUT_DIR="${PROJECT_OUT_DIR:-$HOME/Pictures/better-imagegen}"
mkdir -p "$OUT_DIR"
OUTPUT_PATH="/tmp/logo_output.png"
FINAL_PATH="$OUT_DIR/${OUTPUT_NAME:-logo}.png"

if   GEN_LOG=$(gen_image_apiyi "$MODEL_GPT"    "1280x1280" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_GPT"
elif GEN_LOG=$(gen_image_apiyi "$MODEL_GEMINI" "1280x1280" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_GEMINI"
else echo "LOGO_GENERATION_FAILED"; exit 1
fi
SIZE="1280x1280"

GENERATION_MS=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^ELAPSED_MS:/{v=$2} END{print v+0}')
RESPONSE_FORMAT=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^RESPONSE_FORMAT:/{v=$2} END{print v}')

sips -z "${TARGET_H:-512}" "${TARGET_W:-512}" "$OUTPUT_PATH" --out "$FINAL_PATH" >/dev/null
if command -v pngquant >/dev/null 2>&1; then
  pngquant --force --quality=80-95 --speed 1 --output "$FINAL_PATH" "$FINAL_PATH"
fi

POSTPROCESS_NOTE="resize ${TARGET_W:-512}x${TARGET_H:-512}, pngquant if available"
rm -f "$OUTPUT_PATH"
write_image_metadata "$FINAL_PATH" "${FINAL_PATH%.*}.json" "$MODEL_USED" "$SIZE" "$GENERATION_MS" "$RESPONSE_FORMAT" "$POSTPROCESS_NOTE"
sips -g hasAlpha "$FINAL_PATH" || true
print_image_summary "${FINAL_PATH%.*}.json"
open "$FINAL_PATH"
```

If corners are black/white/gray/tinted or a tile is baked in, remove only edge-connected background:

```bash
"$BETTER_IMAGEGEN_PYTHON" scripts/ensure_transparent.py "$FINAL_PATH" /tmp/logo-transparent.png
mv /tmp/logo-transparent.png "$FINAL_PATH"
sips -g hasAlpha "$FINAL_PATH"
```
