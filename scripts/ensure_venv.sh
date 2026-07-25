#!/usr/bin/env bash
# Environment helper for better-imagegen's local processing dependencies.
# Usage: eval "$(/path/to/better-imagegen/scripts/ensure_venv.sh)"

_better_imagegen_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BETTER_IMAGEGEN_SKILL_DIR="${BETTER_IMAGEGEN_SKILL_DIR:-$(cd "$_better_imagegen_script_dir/.." && pwd)}"
BETTER_IMAGEGEN_VENV="${BETTER_IMAGEGEN_VENV:-$BETTER_IMAGEGEN_SKILL_DIR/.venv}"
BETTER_IMAGEGEN_PYTHON="$BETTER_IMAGEGEN_VENV/bin/python"

if [ ! -x "$BETTER_IMAGEGEN_PYTHON" ]; then
  python3 -m venv "$BETTER_IMAGEGEN_VENV" || {
    echo "Unable to create better-imagegen virtual environment: $BETTER_IMAGEGEN_VENV" >&2
    exit 1
  }
fi

if ! "$BETTER_IMAGEGEN_PYTHON" -c 'from PIL import Image' >/dev/null 2>&1; then
  "$BETTER_IMAGEGEN_PYTHON" -m pip install --disable-pip-version-check -r "$BETTER_IMAGEGEN_SKILL_DIR/requirements.txt" || {
    echo "Unable to install better-imagegen local dependencies." >&2
    exit 1
  }
fi

printf 'export BETTER_IMAGEGEN_SKILL_DIR=%q\n' "$BETTER_IMAGEGEN_SKILL_DIR"
printf 'export BETTER_IMAGEGEN_VENV=%q\n' "$BETTER_IMAGEGEN_VENV"
printf 'export BETTER_IMAGEGEN_PYTHON=%q\n' "$BETTER_IMAGEGEN_PYTHON"
echo "better-imagegen Python: $BETTER_IMAGEGEN_PYTHON" >&2
