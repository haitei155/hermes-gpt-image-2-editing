---
name: gpt-image-2-editing
version: 1.0.0
description: Use this skill whenever the user asks to edit an existing image, do image-to-image generation, use a reference image, preserve composition/pose/face/identity from a source image, replace clothing/background/objects in an existing picture, or complains that image generation is only redrawing from a prompt. Prefer the image_edit tool over image_generate for these tasks.
metadata:
  hermes:
    tags: [image-edit, image-to-image, gpt-image-2, codex, hermes-agent]
---

# GPT Image 2 Editing

Use this skill for any request that edits an existing image or uses a source/reference image.

## Rule

If the user wants image-to-image editing, reference-image editing, partial modification, or wants to preserve the original pose/composition/identity, call `image_edit` first. Do not use `image_generate` unless the user explicitly wants a brand-new image without a source image.

## Required Inputs

- `image_path`: absolute path to the source image file (`.png`, `.jpg`, `.jpeg`, `.webp`).
- `prompt`: concise edit instruction that says both what to change and what to preserve.

## Prompt Pattern

Write edit prompts like this:

```text
Edit the provided source image. Preserve the original composition, camera angle, pose, body proportions, facial identity, lighting direction, and main background structure unless explicitly changed. Change: <requested changes>. Remove/avoid: <things to remove>. Keep output natural and coherent.
```

Use `input_fidelity: high` by default for identity/pose/composition preservation. Use `low` only when the user wants a loose reinterpretation.

## Tool Choice

Preferred:

```text
image_edit(image_path="/absolute/path/to/source.png", prompt="...", aspect_ratio="portrait", input_fidelity="high")
```

Avoid for source-image edits:

```text
image_generate(prompt="description of original image plus changes")
```

That path is text-to-image redraw and loses pose, face similarity, layout, and small details.

## Output Handling

`image_edit` returns JSON with `success`, `image`, `source_image`, `edit_mode`, and diagnostic fields. If `success` is true, send or reference the returned `image` path. On messaging platforms, attach it with `MEDIA:/absolute/path` when appropriate.
