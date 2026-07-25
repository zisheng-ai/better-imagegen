# Text Poster / Competition Cover (backdrop + HTML text layer)

Use for **information-dense covers where accurate text must appear**: hackathon / 大赛 / 黑客松 competition entry covers, product launch key visuals, PPT hero slides, feature posters, "把产品讲清楚" 的封面. Route here whenever the deliverable needs a **product name, tagline, module names, or feature bullets rendered as real text** — especially Chinese.

Load first:
- `references/generation.md`
- `references/prompt-compliance.md`
- `references/post-process.md`

---

## Why not pure text-to-image

Image models garble multi-line text (Chinese especially) and cannot lay out structured info (title + tagline + N labelled cards) reliably. One wrong character kills a competition cover. So **split the job**:

1. The image model generates only an **atmospheric backdrop** (no text, big empty space).
2. An **HTML/CSS layer** carries all text and layout — 100% accurate, fully controllable.
3. **headless Chrome** composites them into one high-res PNG.

Never ask the image model to render the product name or bullets directly.

---

## Pipeline overview

```
generate backdrop (image model)  ─┐
build poster.html (text layer)   ─┼─► Chrome --screenshot @2x ─► 3200×1800 PNG ─► cwebp q90 + keep PNG
inject backdrop via CSS var      ─┘
```

---

## Step 1 — Generate the backdrop

Landscape, dark, with **large empty negative space** for text. Prompt rules:

- Dark gradient base (near-black navy → deep indigo), cinematic/premium.
- Soft blurred color auras placed to **match the brand/module colors** (e.g. blue upper-left, amber upper-right, green bottom) so the backdrop echoes the content.
- Edge circuitry / particle dust / bokeh for tech texture; keep it at the **edges**.
- **Center and upper-middle MUST stay dark, clean, empty** — that is where the title/paragraph land.
- Exclusions: `no text, no letters, no watermark, no logos, no humanoid figure, no faces, no icons, no focal subject in the center`.
- **List anything you specifically do not want**, by name. (Real case: a faint DNA helix kept appearing; adding `no DNA, no helix` to the prompt removed it. If an unwanted element survives, regenerate with an explicit negative — don't try to hide it in CSS.)

**Size: use `1280x720`** (lands in ~40s). Larger sizes like `1536x1024` frequently time out at the 300s API cap. The backdrop is upscaled for free by the 2× screenshot, so low base res is fine.

```bash
export PROMPT="Wide-format abstract dark tech background for an enterprise AI product poster, lots of empty negative space for text overlay. Deep gradient from near-black navy to dark indigo, cinematic premium. Soft blurred color auras: cool blue glow upper-left, warm amber glow upper-right, emerald green glow along the bottom edge, low-opacity, nebula bokeh. Fine particle dust and thin circuit-board traces along the left and right edges fading to black. Center and upper-middle stay dark, clean, empty. no text, no letters, no watermark, no logos, no humanoid figure, no faces, no icons, no focal subject, no DNA, no helix. Ultra minimal, moody, high-end keynote stage backdrop, studio-grade digital art, wide 16:9."
OUTPUT_PATH="/tmp/poster_bg.png"
if   GEN_LOG=$(gen_image_apiyi "$MODEL_GPT"    "1280x720" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_GPT";    SIZE="1280x720"
elif GEN_LOG=$(gen_image_apiyi "$MODEL_GEMINI" "1280x720" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_GEMINI"; SIZE="1280x720"
elif GEN_LOG=$(gen_image_apiyi "$MODEL_DOUBAO" "2560x1440" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_DOUBAO"; SIZE="2560x1440"
elif GEN_LOG=$(gen_image_apiyi "$MODEL_DOUBAO" "2560x1440" "$OUTPUT_PATH"); then MODEL_USED="$MODEL_DOUBAO"; SIZE="2560x1440"
else echo "POSTER_BACKDROP_GENERATION_FAILED"; exit 1
fi
GENERATION_MS=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^ELAPSED_MS:/{v=$2} END{print v+0}')
RESPONSE_FORMAT=$(printf '%s\n' "$GEN_LOG" | awk -F: '/^RESPONSE_FORMAT:/{v=$2} END{print v}')
if [ "$MODEL_USED" = "$MODEL_DOUBAO" ]; then
  strip_doubao_watermark "$OUTPUT_PATH" 1280 720
  SIZE="1280x720 (cropped from 2560x1440)"
fi
```

Preview it small before compositing (Read a resized copy), and regenerate if the center is too busy or an unwanted element appears:
```bash
"$BETTER_IMAGEGEN_PYTHON" -c "from PIL import Image; Image.open('/tmp/poster_bg.png').resize((900,506)).save('/tmp/poster_bg_small.png')"
```

---

## Step 2 — Build `poster.html` (the text layer)

Fixed-size canvas, layered composition. Inject the backdrop through a CSS variable so the file stays portable:

```css
:root { --bg-img: url('file:///tmp/poster_bg.png'); }
html, body { width: 1600px; height: 900px; }           /* logical size; ×2 DPR → 3200×1800 */
body { font-family: "PingFang SC", "Inter", -apple-system, sans-serif; background:#06070b; color:#e8ecf4; position:relative; overflow:hidden; }
```

Stack these full-bleed layers under a `z-index` content `.stage`:

| Layer | Purpose |
|---|---|
| `.bg` | `background-image: var(--bg-img); background-size: cover;` |
| `.glow` | `mix-blend-mode: screen` radial-gradients in the brand colors — deepens/repositions the auras to line up with the content |
| `.grid` | faint 56px grid, `mask-image: radial-gradient(...)` so it fades at edges |
| `.vignette` | top/bottom dark gradients + radial edge darkening so text reads |
| `.stage` | `z-index:5`, flex column, `padding: ~64px 84px` — holds all text |

Recommended content order inside `.stage`:
1. **kicker** — small uppercase org/context line with a glowing dot (e.g. `飞猪 · 体验治理 AI 平台`).
2. **hero** — huge gradient title (`font-size:~150px`, `background: linear-gradient(...); -webkit-background-clip:text; color:transparent; filter: drop-shadow(0 0 50px ...)`) beside an EN codename + divider + tagline.
3. **lead** — one paragraph (`max-width` ~1020px) summarizing the system; color-highlight each module name in its own color.
4. **flow pill** — `margin-top:auto` pushes it down; a rounded pill stating the loop/flow (`↻ 发起 → 执行 → 反哺进化`).
5. **module cards** — a flex row of glass cards (`background: rgba(...); backdrop not needed at screenshot time`), each with a colored top-bar (`::before` + box-shadow glow), an icon chip, title, role line, and 3–4 feature `<li>` bullets. Put `.conn` arrow columns (`→` + tiny label) between cards to show the pipeline.

Use one accent color per module via a `--c` custom property on each card (`style="--c: var(--blue)"`) and drive the top-bar, icon chip, role text, and bullet dots off it.

The reference implementation used for the 无界 cover lives at the end of this file as a template to copy.

---

## Step 3 — Composite with headless Chrome

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --force-device-scale-factor=2 --window-size=1600,900 \
  --screenshot="/tmp/poster_final.png" "file:///path/to/poster.html"
```

- `--allow-file-access-from-files` is **required** for the `file://` backdrop to load.
- `--force-device-scale-factor=2` → a 1600×900 logical canvas renders at **3200×1800** (retina-crisp text).
- `--window-size` must equal the `html,body` logical size.

Iterate: resize the PNG small, `Read` it, tweak CSS, re-shoot. Emoji icons (💬 ⚙️ 🔁) render fine and are the fastest way to get per-module glyphs.

---

## Step 4 — Deliver

Poster art has hard text edges, so use a **higher WebP quality than photos**:

```bash
DEST="${DEST:-$HOME/Pictures/better-imagegen/text-poster}"
mkdir -p "$DEST"
to_webp /tmp/poster_final.png "$DEST/cover.webp" 90                # web use (~300KB @ 3200px)
cp /tmp/poster_final.png "$DEST/cover.png"                         # print / PPT / submission
POSTPROCESS_NOTE="html text layer over $MODEL_USED backdrop, Chrome 2x screenshot, WebP q90"
write_image_metadata "$DEST/cover.webp" "$DEST/cover.json" "$MODEL_USED" "$SIZE" "$GENERATION_MS" "$RESPONSE_FORMAT" "$POSTPROCESS_NOTE"
write_image_metadata "$DEST/cover.png" "$DEST/cover-print.json" "$MODEL_USED" "$SIZE" "$GENERATION_MS" "$RESPONSE_FORMAT" "$POSTPROCESS_NOTE"
print_image_summary "$DEST/cover.json" "$DEST/cover-print.json"
```

Keep both: WebP for web/pages, PNG for PPT decks and competition upload. Then write metadata and print the summary as usual (`write_image_metadata` / `print_image_summary`), noting `postprocess: "html text layer over gpt backdrop, chrome 2x screenshot, cwebp q90"`.

---

## Gotchas

- **Don't render brand text via the image model** — that is the whole reason this type exists.
- **Backdrop timeouts:** stay at `1280x720`; retry once if the API returns `empty response (timeout)` at 300s.
- **Unwanted backdrop elements:** regenerate with an explicit negative (`no DNA`, `no robot`, …); don't mask in CSS.
- **Chinese font:** `PingFang SC` first in the stack, else macOS falls back and glyphs shift.
- **Contrast:** if title/lead sit over a bright aura, strengthen `.vignette` or nudge the `.glow` auras away from the text column rather than dimming the whole image.

---

## Reference template (无界 competition cover)

Copy and adapt. Swap the backdrop path, brand colors (`--blue/--amber/--green`), kicker, title/tagline, lead, flow pill, and the module cards. Keep the layer stack and screenshot command unchanged.

```html
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  :root { --blue: #3b82f6; --amber: #f59e0b; --green: #10b981; --bg-img: url('file:///tmp/showcase_bg.png'); }
  html, body { width: 1600px; height: 900px; }
  body {
    font-family: "PingFang SC", "Inter", -apple-system, sans-serif;
    background: #06070b; color: #e8ecf4; overflow: hidden; position: relative;
  }
  /* GPT 氛围底图 */
  .bg {
    position: absolute; inset: 0;
    background-image: var(--bg-img, none);
    background-size: cover; background-position: center;
  }
  /* 三色发光兜底（叠在图上增强） */
  .glow {
    position: absolute; inset: 0; mix-blend-mode: screen;
    background:
      radial-gradient(40% 52% at 5% 24%, rgba(59,130,246,0.20) 0%, transparent 60%),
      radial-gradient(44% 58% at 92% 20%, rgba(245,158,11,0.16) 0%, transparent 62%),
      radial-gradient(58% 55% at 55% 114%, rgba(16,185,129,0.20) 0%, transparent 60%);
  }
  .grid {
    position: absolute; inset: 0;
    background-image:
      linear-gradient(rgba(255,255,255,0.026) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,0.026) 1px, transparent 1px);
    background-size: 56px 56px;
    mask-image: radial-gradient(85% 78% at 50% 40%, #000 22%, transparent 82%);
  }
  .vignette {
    position: absolute; inset: 0;
    background:
      linear-gradient(180deg, rgba(6,7,11,0.55) 0%, transparent 22%, transparent 62%, rgba(6,7,11,0.4) 100%),
      radial-gradient(130% 105% at 50% 42%, transparent 54%, rgba(3,4,7,0.62) 100%);
  }

  .stage { position: relative; z-index: 5; width: 100%; height: 100%; padding: 64px 84px 58px; display: flex; flex-direction: column; }

  .kicker { display: flex; align-items: center; gap: 14px; }
  .kicker .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--blue); box-shadow: 0 0 14px 3px rgba(59,130,246,0.85); }
  .kicker .txt { font-size: 19px; letter-spacing: 0.34em; color: #909cb2; font-weight: 500; }
  .kicker .txt b { color: #d3dcec; font-weight: 600; }

  .hero { margin-top: 54px; }
  .title-line { display: flex; align-items: flex-end; gap: 36px; }
  .title {
    font-size: 152px; line-height: 0.9; font-weight: 800; letter-spacing: 0.03em;
    background: linear-gradient(150deg, #ffffff 0%, #d3e3ff 44%, #7fb0ff 100%);
    -webkit-background-clip: text; background-clip: text; color: transparent;
    filter: drop-shadow(0 0 50px rgba(90,150,255,0.4));
  }
  .title-side { padding-bottom: 18px; }
  .en { font-size: 25px; letter-spacing: 0.52em; color: #7b89a1; font-weight: 600; }
  .divider { width: 62px; height: 3px; margin: 15px 0 13px; background: linear-gradient(90deg, var(--blue), transparent); border-radius: 3px; }
  .subtitle { font-size: 39px; font-weight: 700; color: #f5f8fd; letter-spacing: 0.05em; }
  .lead { margin-top: 30px; max-width: 1020px; font-size: 22px; line-height: 1.72; color: #adb8cc; font-weight: 400; }
  .lead b { color: #e2e9f5; font-weight: 600; }
  .hl-blue { color: #85b3ff; font-weight: 600; }
  .hl-amber { color: #fbbf5a; font-weight: 600; }
  .hl-green { color: #4ade80; font-weight: 600; }

  .loop-row { margin-top: auto; margin-bottom: 18px; display: flex; }
  .loop-pill {
    font-size: 14.5px; letter-spacing: 0.18em; color: #b0bccf; font-weight: 600;
    padding: 9px 26px; border-radius: 999px;
    border: 1px solid rgba(255,255,255,0.14);
    background: rgba(16,20,30,0.5);
    display: flex; align-items: center; gap: 12px;
  }
  .loop-pill .cyc { font-size: 17px; color: #e0e8f4; }

  .modules { display: flex; align-items: stretch; gap: 0; }
  .card {
    position: relative; flex: 1;
    background: linear-gradient(180deg, rgba(22,28,40,0.72) 0%, rgba(11,15,22,0.78) 100%);
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 20px; padding: 24px 26px 26px;
  }
  .card::before {
    content: ""; position: absolute; top: 0; left: 24px; right: 24px; height: 3px; border-radius: 3px;
    background: var(--c); box-shadow: 0 0 18px 1px var(--c);
  }
  .card .cn { display: flex; align-items: center; gap: 12px; margin-bottom: 5px; }
  .card .ic {
    width: 42px; height: 42px; border-radius: 12px; display: flex; align-items: center; justify-content: center;
    font-size: 22px; background: color-mix(in srgb, var(--c) 16%, transparent);
    border: 1px solid color-mix(in srgb, var(--c) 45%, transparent);
  }
  .card h3 { font-size: 27px; font-weight: 700; color: #fff; }
  .card .role { font-size: 15px; color: var(--c); font-weight: 600; letter-spacing: 0.04em; margin-bottom: 15px; }
  .card ul { list-style: none; display: flex; flex-direction: column; gap: 9px; }
  .card li { font-size: 16.5px; color: #bac4d6; display: flex; align-items: center; gap: 9px; line-height: 1.3; }
  .card li::before { content: ""; width: 5px; height: 5px; border-radius: 50%; background: var(--c); flex-shrink: 0; box-shadow: 0 0 7px 1px var(--c); }

  .conn { width: 74px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 7px; }
  .conn .arrow { font-size: 28px; color: #7d8ba9; }
  .conn .lbl { font-size: 12px; color: #828ea6; letter-spacing: 0.1em; text-align: center; line-height: 1.35; }
</style>
</head>
<body>
  <div class="bg"></div>
  <div class="glow"></div>
  <div class="grid"></div>
  <div class="vignette"></div>

  <div class="stage">
    <div class="kicker">
      <span class="dot"></span>
      <span class="txt">飞猪 · <b>体验治理 AI 平台</b></span>
    </div>

    <div class="hero">
      <div class="title-line">
        <div class="title">无界</div>
        <div class="title-side">
          <div class="en">WUJIE</div>
          <div class="divider"></div>
          <div class="subtitle">体验走查数字员工</div>
        </div>
      </div>
      <div class="lead">
        一句话召唤数字员工<b>「小界」</b>，自动完成飞猪多端体验走查与治理 ——
        <span class="hl-blue">无界</span> 理解意图并发起，
        <span class="hl-amber">Fwork Agent</span> 自动化执行与探索，
        <span class="hl-green">Fwork Evolver</span> 让技能持续自进化，形成越用越准的智能闭环。
      </div>
    </div>

    <div class="loop-row">
      <div class="loop-pill"><span class="cyc">↻</span> 发起 → 执行 / 探索 → 反哺进化 · 技能越用越准的自进化闭环</div>
    </div>

    <div class="modules">
      <div class="card" style="--c: var(--blue)">
        <div class="cn"><span class="ic">💬</span><h3>无界</h3></div>
        <div class="role">对话入口 · 意图识别</div>
        <ul>
          <li>一句话召唤数字员工「小界」</li>
          <li>意图识别，智能推荐项目 / 技能</li>
          <li>HITL 关键节点人工确认</li>
          <li>多任务分身并行 · 可交互报告</li>
        </ul>
      </div>
      <div class="conn"><span class="arrow">→</span><span class="lbl">调用<br>技能</span></div>
      <div class="card" style="--c: var(--amber)">
        <div class="cn"><span class="ic">⚙️</span><h3>Fwork Agent</h3></div>
        <div class="role">自动化执行 · 探索模式</div>
        <ul>
          <li>自动化解决方案，调用沉淀技能</li>
          <li>探索模式：自主录制操作步骤</li>
          <li>卡住时人工接管远程浏览器引导</li>
          <li>引导后交还控制权继续执行</li>
        </ul>
      </div>
      <div class="conn"><span class="arrow">→</span><span class="lbl">结果<br>反哺</span></div>
      <div class="card" style="--c: var(--green)">
        <div class="cn"><span class="ic">🔁</span><h3>Fwork Evolver</h3></div>
        <div class="role">AI 自进化 · 版本沉淀</div>
        <ul>
          <li>执行失败自动生成修复方案</li>
          <li>技能版本化 diff 留痕</li>
          <li>真实反馈驱动技能进化</li>
          <li>进化后技能再供 Agent 调用</li>
        </ul>
      </div>
    </div>
  </div>
</body>
</html>
```
