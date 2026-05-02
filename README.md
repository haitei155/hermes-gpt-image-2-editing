# Hermes GPT Image 2 Editing

Add a source-image editing tool and skill for Hermes Agent.

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

This project is built for Hermes Agent users who run a third-party main model, such as Kimi K2.6, while using Codex/OpenAI GPT Image 2 for image generation. It helps Hermes route image-to-image requests through a real source-image input path instead of asking the text model to describe the image and redraw it from text.

## What It Adds

- `image_edit`: a Hermes tool that passes the original file as `input_image` to GPT Image 2 through the Codex/ChatGPT OAuth backend.
- `gpt-image-2-editing`: a Hermes skill that tells the agent to prefer `image_edit` whenever the user asks to edit, transform, restyle, preserve, or partially modify an existing image.
- Small optional metadata patches so Hermes UI/help text can mention `image_edit` alongside `image_generate`.

## Important Requirement

You must have your own GPT Plus account with Codex access enabled/available.

Before installing this project, Codex must already be configured and logged in inside Hermes, either from Hermes WebUI or from CLI:

```bash
hermes auth codex
```

This project does not provide an OpenAI account, a GPT Plus subscription, Codex entitlement, an API key, or a bypass around account requirements. It only reuses the Codex login that Hermes already has.

## Why This Exists

Hermes' built-in `image_generate` flow is text-to-image. When a user asks to edit a source image, the agent may first describe the original image and then ask GPT Image 2 to redraw it from text. That loses pose, composition, face similarity, clothing details, lighting, and background structure.

This project changes the intended flow to:

```text
User asks to edit an existing image
-> Hermes loads the gpt-image-2-editing skill
-> Hermes calls image_edit(image_path, prompt, ...)
-> image_edit passes the original file as input_image
-> GPT Image 2 returns an edited image
```

The fallback path still sends the source image to the model. It is not the same as pure text-to-image redraw.

## Use Cases

Use this for:

- Editing an existing image instead of redrawing it from a text-only description.
- Image-to-image workflows where the original pose, camera angle, layout, face identity, or background should remain close.
- Outfit, hairstyle, prop, background, object, color, and style changes based on a source image.
- Character or cosplay transformations where the source composition should stay recognizable.
- Hermes setups where the conversation model is a third-party provider but GPT Image 2 is available through Codex.
- Feishu, QQ, Telegram, Slack, or other Hermes gateway workflows that need a reusable image editing tool.

Do not use this for:

- Pure text-to-image generation with no source image. Use Hermes `image_generate` for that.
- Exact deterministic Photoshop-style edits. This is model-based image editing, not pixel-level raster editing.
- Large automated batch jobs without checking Codex/OpenAI account limits.

## Requirements

- Hermes Agent installed from source or an editable checkout.
- A configured Hermes home, usually `~/.hermes`.
- Your own GPT Plus account with Codex access.
- Codex login already completed in Hermes WebUI or CLI.
- Hermes image generation configured to use the Codex image backend, for example:

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

Then restart the gateway if you use Hermes from Feishu, QQ, Telegram, Slack, Discord, or another chat platform:

```bash
systemctl restart hermes-gateway
```

For local CLI use, start a new Hermes session after installation.

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
    print(entry.toolset, entry.schema["description"])
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

## Example Prompt

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

## Backend Behavior

The tool tries multiple request shapes because the Codex GPT Image 2 backend may reject optional edit parameters depending on the current Hermes/Codex backend behavior:

- `edit+input_fidelity`: strict edit mode worked.
- `input_fidelity`: source image plus fidelity worked without explicit action.
- `input_image_only`: source image was provided, optional edit parameters were not accepted.

The returned JSON includes `edit_mode`, `output_path`, and `source_image_path` so you can inspect which path succeeded.

## Uninstall

```bash
./uninstall.sh
systemctl restart hermes-gateway
```

## Files Installed

- `tools/image_edit_tool.py` -> `~/.hermes/hermes-agent/tools/image_edit_tool.py`
- `skills/creative/gpt-image-2-editing/SKILL.md` -> `~/.hermes/skills/creative/gpt-image-2-editing/SKILL.md`

The installer also makes small best-effort patches so Hermes UI/help text mentions `image_edit` alongside `image_generate`.

## License

Apache License 2.0.
