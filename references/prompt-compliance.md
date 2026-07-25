# GPT Prompt Compliance Layer

Load this reference after `references/generation.md` and before any type-specific reference.

Purpose: reduce accidental GPT Image 2 rejections and malformed outputs by normalizing prompts into safe, visual, generation-friendly language. This layer is not for bypassing safety rules. If the user asks for disallowed content, refuse or transform it into an allowed, non-explicit concept before generation.

---

## Operating Rules

1. Preserve the user's visual intent: subject, mood, composition, palette, format, and deliverable.
2. Remove or generalize terms that commonly trigger unnecessary rejection when they are not essential to the image.
3. Do not include platform names, brand marks, copyrighted logos, or UI trademarks unless the user owns them or explicitly requests a generic parody-free reference.
4. Avoid asking the model to render exact words inside the image. Generate clean negative space and add text later in a design tool when accuracy matters.
5. Require adult age language for romance, fashion, beauty, or allure prompts: `adult`, `mature adult`, or `age 25+`.
6. Reject underage sexualization, explicit sex acts, exposed genitals/nipples, pornographic framing, sexual violence, self-harm, graphic gore, and instructions to imitate a living artist's exact style.
7. When a prompt crosses a boundary, rewrite it into an allowed editorial, cinematic, product, or symbolic alternative.

---

## Rewrite Targets

Use these replacements before sending a GPT Image 2 request.

| Risky wording | Safer wording |
|---|---|
| `X.com`, `Twitter`, `Facebook`, `Meta`, `TikTok`, `Instagram` when not essential | `social media`, `feed banner`, `mobile ad creative` |
| `logo`, `official logo`, `brand mark` for third-party brands | `generic interface cue`, `abstract platform-inspired layout` |
| `viral`, `clickbait`, `irresistible click` | `high-converting visual hook`, `strong curiosity gap` |
| `ad`, `advertisement`, `campaign` when rejected | `social media banner`, `product launch visual` |
| exact in-image copy | `empty negative space for overlay copy, no text, no letters` |
| `nude`, `naked`, `topless`, `exposed breast` | `off-shoulder styling`, `elegant neckline`, `fashion editorial styling` |
| `erotic`, `sexual`, `pornographic` | `intimate atmosphere`, `romantic tension`, `alluring editorial mood` |
| `blood`, `gore`, `dismembered` | `dramatic aftermath`, `symbolic red accents`, `non-graphic tension` |
| `weapon aimed at viewer`, `shooting` | `suspenseful prop held low`, `tense cinematic scene` |
| `in the style of [living artist]` | `using general traits: medium, lighting, era, composition, color palette` |

---

## Prompt Contract

Every outbound prompt should follow this structure:

```text
{asset type and composition}. {subject and scene}. {style/medium}. {lighting and palette}. {camera/framing}. {format constraints}. {safety/output constraints}.
```

Default constraints to append when suitable:

```text
no text, no letters, no watermark, no brand marks, no platform logos
```

For ad/social assets, prefer:

```text
left third has clean negative space for overlay copy, right side has the main visual subject, no text, no letters, no watermark, no brand marks
```

For people:

```text
adult subject age 25+, non-explicit, editorial styling
```

---

## Shell Helper

Use this helper when composing prompts inside shell workflows. It performs a conservative first-pass normalization. Manual judgment still wins for complex prompts.

```bash
compliance_normalize_prompt() {
  local input
  input="$(cat)"
  PROMPT_INPUT="$input" "$BETTER_IMAGEGEN_PYTHON" - "$@" <<'PY'
import os, re
text = os.environ.get("PROMPT_INPUT", "")

replacements = [
    (r'\bX\.com\b|\bTwitter\b|\bFacebook\b|\bMeta\b|\bTikTok\b|\bInstagram\b', 'social media'),
    (r'\bofficial logo\b|\bbrand mark\b|\bplatform logo\b', 'generic interface cue'),
    (r'\bviral\b|\bclickbait\b|\birresistible click\b', 'high-converting visual hook'),
    (r'\badvertisement\b|\bad campaign\b|\bcampaign\b', 'social media banner'),
    (r'\bnude\b|\bnaked\b|\btopless\b', 'fashion editorial styling'),
    (r'\bexposed breast\b|\bexposed breasts\b', 'elegant neckline'),
    (r'\berotic\b|\bsexual\b|\bpornographic\b', 'romantic tension'),
    (r'\bblood\b|\bgore\b|\bdismembered\b', 'non-graphic dramatic tension'),
    (r'\bin the style of ([A-Z][A-Za-z .-]+)', r'using general visual traits inspired by the medium, lighting, palette, and composition'),
]

for pattern, replacement in replacements:
    text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)

constraints = 'no text, no letters, no watermark, no brand marks, no platform logos'
if not re.search(r'\bno text\b', text, flags=re.IGNORECASE):
    text = text.rstrip(' .') + '. ' + constraints + '.'

if re.search(r'\b(woman|man|person|couple|model|portrait|romance|alluring|intimate)\b', text, flags=re.IGNORECASE):
    if not re.search(r'\badult\b|age\s*25\+', text, flags=re.IGNORECASE):
        text = text.rstrip(' .') + '. adult subject age 25+, non-explicit, editorial styling.'

print(re.sub(r'\s+', ' ', text).strip())
PY
}
```

Usage:

```bash
PROMPT="$(printf '%s' "$RAW_PROMPT" | compliance_normalize_prompt)"
```

---

## Retry Policy

If GPT returns `invalid_prompt`, `safety`, `rejected`, `SOFT_REJECT`, or an API message saying the image was not generated as expected:

1. Apply the rewrite targets above.
2. Remove platform names, brand names, exact text, and aggressive marketing words.
3. Convert explicit or violent details into editorial, symbolic, or non-graphic equivalents.
4. Retry GPT once.
5. If it still fails, report the failed prompt class and last error. Do not keep probing with near-identical prompts.
