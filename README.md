# Hermes GPT Image 2 Editing

Add a real image-to-image editing tool to Hermes Agent.

This package adds:

- `image_edit`, a Hermes tool that sends the source image as `input_image` to GPT Image 2 through Codex/ChatGPT OAuth.
- `gpt-image-2-editing`, a Hermes skill that tells the agent to use `image_edit` for image-to-image, reference-image editing, 图生图, 改图, and partial image modification tasks.

It is designed for setups where the main Hermes model is a third-party LLM, such as Kimi K2.6, but image generation is configured through Codex/OpenAI GPT Image 2.

## Why this exists

Hermes' built-in `image_generate` flow is text-to-image. If the user asks to edit a source image, the agent may first describe the original image and then ask GPT Image 2 to redraw it from text. That loses pose, composition, face similarity, and small details.

This project changes the intended flow to:

```text
User asks to edit an existing image
-> Hermes loads gpt-image-2-editing skill
-> Hermes calls image_edit(image_path, prompt, ...)
-> image_edit passes the original file as input_image
-> GPT Image 2 returns an edited image
```

## Use cases

Use this for:

- Editing an existing image instead of redrawing from text
- 图生图 / 改图 / 局部修改
- Preserving pose, composition, layout, identity, lighting, or background structure
- Replacing clothes, props, background, objects, colors, or style in a source image
- Character/cosplay transformations where the original pose and framing should remain close
- Workflows where a third-party text model controls Hermes but Codex/OpenAI handles GPT Image 2 generation

Do not use this for:

- Pure text-to-image generation with no source image
- Batch editing many very large images without considering Codex/OpenAI limits
- Exact pixel-level Photoshop-style edits; this is model-based image editing, not deterministic raster editing

## Requirements

- Hermes Agent installed from source or an editable checkout.
- Hermes has Codex/ChatGPT OAuth configured:

```bash
hermes auth codex
```

- Hermes image generation is configured to use the Codex image backend, for example:

```yaml
image_gen:
  provider: openai-codex
  model: gpt-image-2-medium
```

## Install

Clone this repository on the machine running Hermes:

```bash
git clone https://github.com/haitei155/hermes-gpt-image-2-editing.git
cd hermes-gpt-image-2-editing
./install.sh
```

Then restart the gateway if you use Hermes from Feishu, QQ, Telegram, Slack, etc.:

```bash
systemctl restart hermes-gateway
```

For local CLI use, just start a new Hermes session.

## Verify

Run:

```bash
cd ~/.hermes/hermes-agent
python - <<'PY'
from tools.registry import discover_builtin_tools, registry
discover_builtin_tools()
entry = registry.get_entry("image_edit")
print("image_edit registered:", bool(entry))
if entry:
    print(entry.schema["description"])
PY
```

Expected:

```text
image_edit registered: True
```

You should also see the skill:

```bash
hermes skills list | grep gpt-image-2-editing
```

## Example

```text
Use image_edit. Edit /root/.hermes/image_cache/source.png.
Preserve the original pose, camera angle, face identity, lighting direction, and main background.
Change the outfit into Fate Rider Medusa's outfit, change the hair to a purple cosplay wig,
replace the yellow pom-poms with silver chained daggers, and remove the Blue Archive halo.
```

The agent should call:

```text
image_edit(
  image_path="/root/.hermes/image_cache/source.png",
  prompt="Edit the provided source image. Preserve ... Change ...",
  aspect_ratio="portrait",
  input_fidelity="high"
)
```

## Notes on backend behavior

The tool first tries the strict edit shape using GPT Image 2 with image-generation edit parameters. If the Codex backend rejects an optional edit parameter, the tool falls back to an `input_image` request without that optional parameter. This still passes the original image to the model and is not the same as pure text-to-image redraw.

Returned JSON includes `edit_mode` so you can see which path worked:

- `edit+input_fidelity`: strict edit mode worked
- `input_fidelity`: source image plus fidelity worked without explicit action
- `input_image_only`: source image was provided, optional edit parameters were not accepted

## Uninstall

```bash
./uninstall.sh
systemctl restart hermes-gateway
```

## Files installed

- `tools/image_edit_tool.py` -> `~/.hermes/hermes-agent/tools/image_edit_tool.py`
- `skills/creative/gpt-image-2-editing/SKILL.md` -> `~/.hermes/skills/creative/gpt-image-2-editing/SKILL.md`

The installer also makes small best-effort patches so Hermes UI/help text mentions `image_edit` alongside `image_generate`.
