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
import re
import sys

root = Path(sys.argv[1])


def replace_if_present(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if old not in text:
        return
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Reverted {path}")


def replace_all_if_present(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if old not in text:
        return
    path.write_text(text.replace(old, new), encoding="utf-8")
    print(f"Reverted {path}")


replace_if_present(
    root / "model_tools.py",
    '"image_tools": ["image_generate", "image_edit"],',
    '"image_tools": ["image_generate"],',
)
replace_all_if_present(
    root / "toolsets.py",
    '"vision_analyze", "image_generate", "image_edit",',
    '"vision_analyze", "image_generate",',
)
replace_if_present(
    root / "toolsets.py",
    '"tools": ["image_generate", "image_edit"],',
    '"tools": ["image_generate"],',
)
replace_if_present(
    root / "hermes_cli" / "config.py",
    '"tools": ["image_generate", "image_edit"],',
    '"tools": ["image_generate"],',
)

gateway = root / "gateway" / "run.py"
if gateway.exists():
    text = gateway.read_text(encoding="utf-8")
    text = re.sub(
        r"\n# gpt-image-2-editing: direct image edit routing patch\n.*?\n# end gpt-image-2-editing direct image edit routing patch\n",
        "\n",
        text,
        count=1,
        flags=re.S,
    )
    fast_path = '''        # gpt-image-2-editing: pass direct edit/reference tasks through as raw image files.
        if _looks_like_direct_image_edit_request(user_text, len(image_paths)):
            logger.info(
                "Skipping vision auto-analysis for direct image edit request (%s images)",
                len(image_paths),
            )
            return _build_raw_image_edit_context(user_text, image_paths)

'''
    if fast_path in text:
        text = text.replace(fast_path, "", 1)
    gateway.write_text(text, encoding="utf-8")
    print(f"Reverted {gateway}")
PY

echo "Uninstalled Hermes GPT Image 2 Editing."
echo "Restart hermes-gateway if you use messaging platforms:"
echo "  systemctl restart hermes-gateway"
