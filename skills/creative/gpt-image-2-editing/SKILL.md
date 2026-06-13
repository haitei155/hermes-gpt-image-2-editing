---
name: gpt-image-2-editing
version: 1.1.1
description: Use this skill whenever the user asks to edit existing images, do image-to-image generation, 图生图, 改图, multi-image reference editing, preserve composition/pose/face/identity from a source image, transfer style/palette/clothing/accessory colors from references, or complains that image generation is only redrawing from text. Prefer image_edit over image_generate for these tasks.
metadata:
  hermes:
    tags: [image-edit, image-to-image, multi-reference, gpt-image-2, codex, 图生图, 改图]
---

# GPT Image 2 Editing

Use this skill for requests that edit existing images or use one or more uploaded images as source/reference material.

## Core Rule

For image-to-image, 图生图, 改图, partial modification, reference-image editing, style transfer, palette transfer, or identity/composition preservation, call `image_edit` first.

Do not call `vision_analyze` before or after normal image editing unless the user explicitly asks for visual QA. The editing tool sends raw image files to GPT Image 2; converting reference images into text first loses palette, facial, clothing, and style details.

Do not use `image_generate` unless the user explicitly wants a brand-new text-to-image result with no source image.

## Inputs

- `image_path`: absolute path to the primary source/base image to edit.
- `reference_image_paths`: optional absolute paths to style, palette, clothing, accessory, pose, or composition reference images.
- `prompt`: concise edit instruction that says what to change, what to preserve, and what each reference image controls.
- `aspect_ratio`: `landscape`, `square`, or `portrait`.
- `input_fidelity`: use `high` by default for identity, face, pose, and composition preservation.

## Multi-Image Mapping

When the user references upload numbers, first map the upload order to tool roles.

Example: if the user says "edit 图2 into 图1's pixel style; use 图3 for clothing and hair accessory colors":

```text
image_path = uploaded image 2
reference_image_paths = [uploaded image 1, uploaded image 3]
prompt = "Edit the PRIMARY SOURCE. Preserve its character identity, facial features, pose, and composition. Use REFERENCE IMAGE 1 only for the pixel-art rendering style. Use REFERENCE IMAGE 2 only for clothing colors, hair accessory colors, and palette. Do not collage, paste, or transplant parts from references."
```

After choosing `image_path`, avoid stale numbering in the tool prompt. Use `PRIMARY SOURCE`, `REFERENCE IMAGE 1`, `REFERENCE IMAGE 2`, etc.

## Prompt Pattern

```text
Edit the PRIMARY SOURCE image. Preserve the primary source composition, camera angle, pose, body proportions, facial identity, expression, lighting direction, and main layout unless explicitly changed.
Use REFERENCE IMAGE 1 only for <style/palette/etc>.
Use REFERENCE IMAGE 2 only for <style/palette/etc>.
Change: <requested changes>.
Avoid: collage, head transplant, clothing/body pasted from references, text-to-image redraw, unwanted background changes.
```

## Tool Choice

Preferred for one source image:

```text
image_edit(
  image_path="/absolute/path/to/source.png",
  prompt="Edit the PRIMARY SOURCE image. Preserve ... Change ...",
  aspect_ratio="portrait",
  input_fidelity="high"
)
```

Preferred for multi-reference edits:

```text
image_edit(
  image_path="/absolute/path/to/base.png",
  reference_image_paths=[
    "/absolute/path/to/style-reference.png",
    "/absolute/path/to/palette-reference.png"
  ],
  prompt="Edit the PRIMARY SOURCE. Preserve its identity and pose. Use REFERENCE IMAGE 1 only for style. Use REFERENCE IMAGE 2 only for palette and clothing colors.",
  aspect_ratio="landscape",
  input_fidelity="high"
)
```

Avoid for source-image edits:

```text
image_generate(prompt="description of original image plus changes")
vision_analyze(image_url="/path/to/reference.png", question="describe colors")
```

Those paths turn visual references into text and lose important details.

## Output Handling

`image_edit` returns JSON with `success`, `image`, `source_image`, `reference_images`, `edit_mode`, and diagnostic fields. If `success` is true, send or reference the returned `image` path. On messaging platforms, attach it with `MEDIA:/absolute/path` when appropriate.
