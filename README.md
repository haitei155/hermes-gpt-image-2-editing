# Hermes GPT Image 2 Editing

Add a real image-to-image editing tool and skill for Hermes Agent.

Chinese documentation (中文文档): [README.zh-CN.md](README.zh-CN.md)

This project is for Hermes Agent setups where the main conversation model may be a third-party model, while GPT Image 2 is available through Hermes' Codex/ChatGPT OAuth login. It helps Hermes route editing requests through raw image inputs instead of first describing uploaded images with `vision_analyze` and redrawing from text.

## What It Adds

- `image_edit`: a Hermes tool that sends the primary source image and optional reference images as `input_image` parts to GPT Image 2 through Codex/ChatGPT OAuth.
- `gpt-image-2-editing`: a Hermes skill that tells the agent to prefer `image_edit` for image-to-image, multi-reference editing, style transfer, palette transfer, and identity-preserving edits.
- Gateway routing patch: direct edit/reference requests skip automatic `vision_analyze`, preserving the original image files for the image model.
- Toolset metadata patches so `image_edit` appears alongside `image_generate`.

## Latest Update

Compared with the previous release, this update mainly syncs the production fix from the VPS:

- Keeps the v1.1 multi-reference editing flow and role mapping for primary/source/reference images.
- Adds a Codex streaming parser fallback: if `openai-python` crashes on a final `response.completed` payload with `output=None` after the image result has already arrived, `image_edit` now keeps the captured image instead of reporting `TypeError: 'NoneType' object is not iterable`.
- This prevents successful GPT Image 2 edits from being discarded at the very end of the stream.

## Requirement

You need your own GPT Plus account with Codex access enabled/available, and Hermes must already be logged into Codex:

```bash
hermes auth codex
```

This project does not provide an OpenAI account, GPT Plus subscription, Codex entitlement, API key, or any bypass around account requirements.

## Why This Exists

The bad flow:

```text
uploaded images -> vision_analyze text descriptions -> image_generate redraw
```

That loses facial identity, exact colors, clothing/accessory details, pixel style, pose, and composition.

The intended flow:

```text
uploaded images -> image_edit raw input_image payloads -> GPT Image 2 edit result
```

For multi-image prompts such as "edit image 2 in image 1's pixel style, use image 3 for clothing colors", the gateway tells the agent to map upload numbers into tool roles:

```text
image_path = uploaded image 2
reference_image_paths = [uploaded image 1, uploaded image 3]
prompt = "Edit the PRIMARY SOURCE. Use REFERENCE IMAGE 1 only for style. Use REFERENCE IMAGE 2 only for palette/clothing colors."
```

## Demo

This example shows the exact case this package is designed to improve: a Feishu message with three reference images, where the user asks Hermes to edit the second image, borrow pixel-art style from the first, and borrow clothing/accessory colors from the third.

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>1. Multi-image request in Feishu</strong><br>
      The prompt names image roles in natural language: image 2 is the base character, image 1 is the pixel-art style reference, and image 3 is the palette reference.
      <br><br>
      <img src="assets/demo-feishu-request.png" alt="Feishu multi-image request asking Hermes to edit image 2 using image 1 style and image 3 colors" width="100%">
    </td>
    <td width="50%" valign="top">
      <strong>2. Hermes uses image_edit directly</strong><br>
      The agent calls <code>image_edit</code> with raw image files, then returns a generated pixel-art result instead of relying on text-only image descriptions.
      <br><br>
      <img src="assets/demo-feishu-result.png" alt="Hermes image_edit result showing a pixel-art character generated from multiple references" width="100%">
    </td>
  </tr>
</table>

The important behavior is not only the final picture. It is the routing:

```text
Feishu uploads -> raw cached image paths -> image_edit(image_path, reference_image_paths, prompt)
```

The gateway patch avoids the lossy path:

```text
Feishu uploads -> vision_analyze descriptions -> text-to-image redraw
```

## Install

Clone this repository on the machine running Hermes:

```bash
git clone https://github.com/haitei155/hermes-gpt-image-2-editing.git
cd hermes-gpt-image-2-editing
./install.sh
```

Then restart the gateway if you use Feishu, QQ, Telegram, Slack, Discord, or another chat platform:

```bash
systemctl restart hermes-gateway
```

For local CLI use, start a new Hermes session after installation.

## Verify

```bash
cd ~/.hermes/hermes-agent
python - <<'PY'
from tools.registry import discover_builtin_tools, registry
discover_builtin_tools()
entry = registry.get_entry("image_edit")
print("image_edit registered:", bool(entry))
if entry:
    print(entry.toolset)
    print("reference_image_paths" in entry.schema["parameters"]["properties"])
PY
```

Expected:

```text
image_edit registered: True
image_gen
True
```

## Example

User intent:

```text
Transform image 2 into image 1's late-90s pixel-art style. Preserve image 2's facial features and expression. Use image 3 for clothing colors and hair accessory colors. Solid #c0c0f8 background. 16:9.
```

The agent should call:

```text
image_edit(
  image_path="/path/to/uploaded-image-2.png",
  reference_image_paths=[
    "/path/to/uploaded-image-1.png",
    "/path/to/uploaded-image-3.png"
  ],
  prompt="Edit the PRIMARY SOURCE. Preserve its facial identity, expression, pose, and composition. Use REFERENCE IMAGE 1 only for the late-90s pixel-art rendering style. Use REFERENCE IMAGE 2 only for clothing colors, hair accessory colors, and palette. Set a solid #c0c0f8 background. Avoid collage, head transplant, and pasted reference parts.",
  aspect_ratio="landscape",
  input_fidelity="high"
)
```

## Uninstall

```bash
./uninstall.sh
systemctl restart hermes-gateway
```

## Files Installed

- `tools/image_edit_tool.py` -> `~/.hermes/hermes-agent/tools/image_edit_tool.py`
- `skills/creative/gpt-image-2-editing/SKILL.md` -> `~/.hermes/skills/creative/gpt-image-2-editing/SKILL.md`

The installer also patches Hermes toolset metadata and `gateway/run.py` so direct image edits do not get converted to lossy `vision_analyze` descriptions.

## License

Apache License 2.0.
