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

# Best-effort Hermes integration patches. The tool self-registers, but these
# patches expose it through the image_gen toolset and prevent gateway image
# edit requests from being reduced to lossy vision_analyze descriptions.
"$python_bin" - "$HERMES_AGENT_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])


def patch_once(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        return
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Patched {path}")


def patch_all(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if old not in text:
        return
    updated = text.replace(old, new)
    if updated == text:
        return
    path.write_text(updated, encoding="utf-8")
    print(f"Patched {path}")


patch_once(
    root / "model_tools.py",
    '"image_tools": ["image_generate"],',
    '"image_tools": ["image_generate", "image_edit"],',
)
patch_all(
    root / "toolsets.py",
    '"vision_analyze", "image_generate",',
    '"vision_analyze", "image_generate", "image_edit",',
)
patch_once(
    root / "toolsets.py",
    '"tools": ["image_generate"],',
    '"tools": ["image_generate", "image_edit"],',
)
patch_once(
    root / "hermes_cli" / "config.py",
    '"tools": ["image_generate"],',
    '"tools": ["image_generate", "image_edit"],',
)

gateway = root / "gateway" / "run.py"
if gateway.exists():
    text = gateway.read_text(encoding="utf-8")
    helper = r'''
# gpt-image-2-editing: direct image edit routing patch
_DIRECT_IMAGE_EDIT_KEYWORDS = (
    "image_edit",
    "edit image",
    "image-to-image",
    "img2img",
    "reference image",
    "style reference",
    "color reference",
    "palette reference",
    "base image",
    "source image",
    "transform this",
    "turn this",
    "make it",
    "pixel art",
    "pixelate",
    "sprite",
    "16:9",
    "\u56fe\u751f\u56fe",
    "\u6539\u56fe",
    "\u4fee\u56fe",
    "\u7f16\u8f91\u56fe\u7247",
    "\u4fee\u6539\u56fe\u7247",
    "\u50cf\u7d20",
    "\u50cf\u7d20\u98ce",
    "\u753b\u98ce",
    "\u98ce\u683c",
    "\u914d\u8272",
    "\u989c\u8272\u53c2\u8003",
    "\u670d\u88c5",
    "\u53d1\u9970",
    "\u80cc\u666f\u8272",
    "\u5e95\u56fe",
    "\u53c2\u8003\u56fe",
    "\u751f\u6210\u56fe",
)

_DIRECT_IMAGE_EDIT_REGEXES = (
    re.compile(r"(?:image|img|photo|picture)\s*\d+", re.IGNORECASE),
    re.compile(r"\u56fe\s*\d+"),
)


def _looks_like_direct_image_edit_request(user_text: str, image_count: int) -> bool:
    """Return True when uploaded images should be passed through raw to image_edit."""
    text = (user_text or "").strip().lower()
    if not text:
        return False
    if image_count >= 2 and any(regex.search(text) for regex in _DIRECT_IMAGE_EDIT_REGEXES):
        return True
    return any(keyword.lower() in text for keyword in _DIRECT_IMAGE_EDIT_KEYWORDS)


def _build_raw_image_edit_context(user_text: str, image_paths: List[str]) -> str:
    paths = "\n".join(
        f"- image {idx}: {path}"
        for idx, path in enumerate(image_paths, start=1)
    )
    prefix = (
        "[The user attached image files for a direct image edit/reference task. "
        "Do not call vision_analyze before or after image_edit unless the user "
        "explicitly asks for visual QA. Preserve the raw files as visual inputs: "
        "call image_edit directly when generating or modifying an image.\n"
        "Upload order for references like image 1 / image 2 / image 3, "
        "\u56fe1 / \u56fe2 / \u56fe3, first / second / third:\n"
        f"{paths}\n"
        "When calling image_edit, put the image that should be changed in "
        "image_path and put all style, palette, clothing, accessory, pose, or "
        "composition references in reference_image_paths. Use the prompt to "
        "state each reference role explicitly. Rewrite user numbering into "
        "tool-call roles, e.g. if the user says '\u56fe2 as base, \u56fe1 style, "
        "\u56fe3 palette', call image_edit with uploaded image 2 as image_path, "
        "uploaded images 1 and 3 as reference_image_paths, and phrase the "
        "prompt as 'edit the PRIMARY SOURCE; use REFERENCE IMAGE 1 for style "
        "and REFERENCE IMAGE 2 for palette'. Do not convert reference images "
        "into text descriptions first.]"
    )
    if user_text:
        return f"{prefix}\n\n{user_text}"
    return prefix
# end gpt-image-2-editing direct image edit routing patch
'''
    anchor = "_AGENT_CACHE_IDLE_TTL_SECS = 3600.0  # evict agents idle for >1h\n"
    if "_looks_like_direct_image_edit_request" not in text and anchor in text:
        text = text.replace(anchor, anchor + helper, 1)

    fast_path = '''        # gpt-image-2-editing: pass direct edit/reference tasks through as raw image files.
        if _looks_like_direct_image_edit_request(user_text, len(image_paths)):
            logger.info(
                "Skipping vision auto-analysis for direct image edit request (%s images)",
                len(image_paths),
            )
            return _build_raw_image_edit_context(user_text, image_paths)

'''
    needle = '        """\n        from tools.vision_tools import vision_analyze_tool\n'
    if "Skipping vision auto-analysis for direct image edit request" not in text and needle in text:
        text = text.replace(needle, '        """\n' + fast_path + "        from tools.vision_tools import vision_analyze_tool\n", 1)

    gateway.write_text(text, encoding="utf-8")
    print(f"Patched {gateway}")
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
schema = entry.schema.get("parameters", {}).get("properties", {})
if "reference_image_paths" not in schema:
    raise SystemExit("image_edit registered, but multi-image references are missing")
print("image_edit registered:", entry.toolset)
PY

echo
echo "Installed Hermes GPT Image 2 Editing."
echo "Restart hermes-gateway if you use messaging platforms:"
echo "  systemctl restart hermes-gateway"
