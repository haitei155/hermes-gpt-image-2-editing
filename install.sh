#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-$HERMES_HOME/hermes-agent}"

if [[ ! -d "$HERMES_AGENT_DIR" ]]; then
  echo "Hermes agent directory not found: $HERMES_AGENT_DIR" >&2
  echo "Set HERMES_AGENT_DIR=/path/to/hermes-agent and re-run." >&2
  exit 1
fi

if [[ ! -f "$HERMES_AGENT_DIR/tools/registry.py" ]]; then
  echo "This does not look like a Hermes source checkout: $HERMES_AGENT_DIR" >&2
  exit 1
fi

mkdir -p "$HERMES_HOME/skills/creative/gpt-image-2-editing"
mkdir -p "$HERMES_AGENT_DIR/tools"

cp tools/image_edit_tool.py "$HERMES_AGENT_DIR/tools/image_edit_tool.py"
cp skills/creative/gpt-image-2-editing/SKILL.md \
  "$HERMES_HOME/skills/creative/gpt-image-2-editing/SKILL.md"

python_bin="$HERMES_AGENT_DIR/venv/bin/python"
if [[ ! -x "$python_bin" ]]; then
  python_bin="$(command -v python3 || command -v python)"
fi

"$python_bin" -m py_compile "$HERMES_AGENT_DIR/tools/image_edit_tool.py"

# Best-effort patches for Hermes' tool UI/help metadata. The tool works without
# these, because self-registering tool files are discovered automatically.
"$python_bin" - "$HERMES_AGENT_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
patches = [
    (
        root / "hermes_cli" / "tools_config.py",
        "image_generate",
        "image_generate, image_edit",
    ),
    (
        root / "hermes_cli" / "config.py",
        '"tools": ["image_generate"],',
        '"tools": ["image_generate", "image_edit"],',
    ),
]

for path, old, new in patches:
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    if new in text:
        continue
    if old in text:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        print(f"Patched {path}")
PY

"$python_bin" - "$HERMES_AGENT_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root))
from tools.registry import discover_builtin_tools, registry

discover_builtin_tools(root / "tools")
entry = registry.get_entry("image_edit")
if not entry:
    raise SystemExit("image_edit did not register")
print("image_edit registered:", entry.toolset)
PY

echo
echo "Installed Hermes GPT Image 2 Editing."
echo "Restart hermes-gateway if you use messaging platforms:"
echo "  systemctl restart hermes-gateway"
