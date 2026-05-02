#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-$HERMES_HOME/hermes-agent}"

rm -f "$HERMES_AGENT_DIR/tools/image_edit_tool.py"
rm -rf "$HERMES_HOME/skills/creative/gpt-image-2-editing"

python_bin="$HERMES_AGENT_DIR/venv/bin/python"
if [[ ! -x "$python_bin" ]]; then
  python_bin="$(command -v python3 || command -v python)"
fi

"$python_bin" - "$HERMES_AGENT_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
patches = [
    (
        root / "hermes_cli" / "tools_config.py",
        "image_generate, image_edit",
        "image_generate",
    ),
    (
        root / "hermes_cli" / "config.py",
        '"tools": ["image_generate", "image_edit"],',
        '"tools": ["image_generate"],',
    ),
]

for path, old, new in patches:
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    if old in text:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        print(f"Reverted {path}")
PY

echo "Uninstalled Hermes GPT Image 2 Editing."
echo "Restart hermes-gateway if you use messaging platforms:"
echo "  systemctl restart hermes-gateway"
