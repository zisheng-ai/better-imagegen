# Image Edit (图生图 / img2img)

Use when the user provides an existing image and wants a faithful variation: refine, upscale-with-redraw, style-preserving cleanup, pose change on the same character, or any "不要大改形象 / 保持原样但更精致" request.

Key insight: text-to-image regeneration ALWAYS drifts the character design, no matter how detailed the prompt. When the user says the character/subject must stay the same, use the **edits endpoint** with the original image as reference — never regenerate from text alone.

Load first:
- `references/generation.md`
- `references/prompt-compliance.md`
- `references/post-process.md`

---

## Endpoint

`POST https://api.apiyi.com/v1/images/edits` — multipart form (NOT JSON):

```bash
curl -s --max-time 300 "https://api.apiyi.com/v1/images/edits" \
  -H "Authorization: Bearer $APIYI_API_KEY" \
  -F "model=gpt-image-2-all" \
  -F "image=@input.png" \
  -F "prompt=$PROMPT" \
  -F "size=1024x1024"
```

Response is the same shape as generations: `data[0].b64_json` or `data[0].url`. Reuse the same Python extraction block from `gen_image_apiyi` in `references/generation.md`.

Notes:
- `image` accepts PNG with alpha; small inputs (e.g. 96px pixel art) work fine.
- Requested `size` is approximate — actual output may differ (e.g. 1254×1254 for 1024×1024 request). Always measure the real output.
- The model usually bakes a background (white or checkerboard) even when asked for transparency. Plan for background removal in post-processing — ask for "plain solid white background" in the prompt to make removal trivial, rather than fighting for real alpha.

---

## Prompt Template (faithful refinement)

The prompt must both describe the invariants explicitly AND forbid the common drift directions:

```text
Faithfully redraw this exact same <subject> at higher fidelity.
Keep the IDENTICAL character design: <enumerate concrete invariants — body shape,
proportions, eyes, palette hex, pose, style era>.
Keep the <style> and the cute/kawaii feeling — do NOT make it realistic,
do NOT add gradients or extra shading detail, do NOT change proportions.
Only <the single allowed change, e.g. "make the pixel edges slightly cleaner">.
Plain solid white background, no text, no border.
```

Enumerating invariants matters: "keep it the same" alone still drifts; listing "same blocky square body, same two ear tufts, same big round dot eyes, same warm amber-orange palette" holds the design.

---

## Batch: animation frames / multi-image edits

For frame sequences (e.g. a 6-frame menu bar sprite), edit each source frame in a parallel background process, one edits call per frame. Describe that frame's pose in its prompt so the model doesn't "correct" the pose toward a neutral one:

```bash
POSES=("wings fully tucked down" "wings slightly lifted" "wings at mid height" \
       "wings fully spread upward" "wings coming back down" "wings almost tucked")
for i in 0 1 2 3 4 5; do
  ( curl ... -F "image=@$SRC_DIR/frame-$i.png" \
      -F "prompt=... same wing pose as the input image (${POSES[$((i+1))]}) ..." \
      ... ) &
done
wait
```

Caveat: independently edited frames have slight frame-to-frame jitter (eye shape, outline width). At menu-bar size (~22px) this is invisible or reads as natural blinking. If jitter is unacceptable, fall back to the sprite-sheet flow in `references/sprite-loop.md` (better inter-frame consistency, worse fidelity to the original design).

---

## Post-processing pipeline

1. **Background removal** — use `"$BETTER_IMAGEGEN_PYTHON" scripts/ensure_transparent.py input.png output.png`. It handles solid black, white, gray, or tinted backgrounds by sampling the four corners and only clearing matching edge-connected pixels. Use `--edge-mode pixel` for pixel art; use the default soft mode for hair, fur, feathers, fringe, glass, smoke, or antialiased art. Do not use the older near-white-only flood fill for transparency-critical output.

```python
from PIL import Image
from collections import deque

def remove_bg(im):
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    def is_bg(p):
        r, g, b, a = p
        return a == 0 or (r > 200 and g > 200 and b > 200 and abs(r-g) < 18 and abs(g-b) < 18)
    seen = [[False]*w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h-1):
            if is_bg(px[x, y]) and not seen[y][x]:
                seen[y][x] = True; q.append((x, y))
    for y in range(h):
        for x in (0, w-1):
            if is_bg(px[x, y]) and not seen[y][x]:
                seen[y][x] = True; q.append((x, y))
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and is_bg(px[nx, ny]):
                seen[ny][nx] = True; q.append((nx, ny))
    return im
```

2. **Crop + center** — `im.crop(im.getbbox())`, then paste centered on a square transparent canvas with ~12% margin (`side = int(max(im.size) * 1.12)`), matching typical icon padding.

3. **Resize** — LANCZOS down to the delivery size (blocks are large after AI redraw, so LANCZOS stays crisp; NEAREST is only for integer-scaling true pixel sources).

4. **Verify alpha** — the script must print `TRANSPARENCY_OK`; additionally preserve its non-zero exit as a hard generation failure. Never deliver an asset merely because its file format supports alpha.
5. **Visual matte QA** — composite a 4× preview over white, black, and checkerboard backgrounds. Inspect fine strands and high-contrast contours for clipping, dark/light halos, matte-color contamination, and excessive feathering. Regenerate against a more contrasting matte when cleanup would require erasing subject-colored pixels.

5. For frame sequences, also emit a `preview.gif` (`duration=100, loop=0, disposal=2`) so the user can eyeball loop smoothness.

Deliver PNG with alpha (not WebP) when the asset is an icon/sprite; write metadata JSON per `references/generation.md`.

---

## When NOT to use edits

- Brand-new asset with no source image → generations endpoint (type-specific reference).
- Frame-to-frame consistency matters more than fidelity to an existing design → `references/sprite-loop.md` sprite sheet.
- Pure mechanical upscale where zero design change is acceptable → no API at all; integer-scale locally with PIL `Image.NEAREST`. Offer this first when the user says the image must not change AT ALL — it's free and instant. Only escalate to edits when the user wants "同样的形象但更精致" (same design, slightly refined).
