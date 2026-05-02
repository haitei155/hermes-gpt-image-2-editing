"""OpenAI/Codex-backed image editing tool for Hermes Agent.

The tool always sends the source image as an ``input_image`` to the Codex
Responses ``image_generation`` tool, so image-to-image/edit requests do not
degrade into pure text-to-image redraws.
"""

from __future__ import annotations

import base64
import json
import logging
import mimetypes
import os
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

from agent.image_gen_provider import (
    DEFAULT_ASPECT_RATIO,
    error_response,
    resolve_aspect_ratio,
    save_b64_image,
    success_response,
)
from tools.registry import registry

logger = logging.getLogger(__name__)

API_MODEL = "gpt-image-2"
DEFAULT_MODEL = "gpt-image-2-medium"
_CODEX_CHAT_MODEL = "gpt-5.4"
_CODEX_BASE_URL = "https://chatgpt.com/backend-api/codex"
_CODEX_INSTRUCTIONS = (
    "You are an assistant that must edit the provided input image with the "
    "image_generation tool. Preserve the source image composition, identity, "
    "pose, and layout unless the user explicitly asks to change them."
)

_MODELS: Dict[str, Dict[str, Any]] = {
    "gpt-image-2-low": {"quality": "low"},
    "gpt-image-2-medium": {"quality": "medium"},
    "gpt-image-2-high": {"quality": "high"},
}

_SIZES = {
    "landscape": "1536x1024",
    "square": "1024x1024",
    "portrait": "1024x1536",
}

_SUPPORTED_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp"}


def _load_image_gen_config() -> Dict[str, Any]:
    try:
        from hermes_cli.config import load_config

        cfg = load_config()
        section = cfg.get("image_gen") if isinstance(cfg, dict) else None
        return section if isinstance(section, dict) else {}
    except Exception as exc:
        logger.debug("Could not load image_gen config: %s", exc)
        return {}


def _resolve_model() -> tuple[str, Dict[str, Any]]:
    env_override = os.environ.get("OPENAI_IMAGE_MODEL")
    if env_override and env_override in _MODELS:
        return env_override, _MODELS[env_override]

    cfg = _load_image_gen_config()
    sub = cfg.get("openai-codex") if isinstance(cfg.get("openai-codex"), dict) else {}
    candidate: Optional[str] = None
    if isinstance(sub, dict):
        value = sub.get("model")
        if isinstance(value, str) and value in _MODELS:
            candidate = value
    if candidate is None:
        top = cfg.get("model")
        if isinstance(top, str) and top in _MODELS:
            candidate = top
    if candidate is not None:
        return candidate, _MODELS[candidate]
    return DEFAULT_MODEL, _MODELS[DEFAULT_MODEL]


def _read_codex_access_token() -> Optional[str]:
    try:
        from agent.auxiliary_client import _read_codex_access_token as _reader

        token = _reader()
        if isinstance(token, str) and token.strip():
            return token.strip()
    except Exception as exc:
        logger.debug("Could not resolve Codex access token: %s", exc)
    return None


def _build_codex_client():
    token = _read_codex_access_token()
    if not token:
        return None
    try:
        import openai
        from agent.auxiliary_client import _codex_cloudflare_headers

        return openai.OpenAI(
            api_key=token,
            base_url=_CODEX_BASE_URL,
            default_headers=_codex_cloudflare_headers(token),
        )
    except Exception as exc:
        logger.debug("Could not build Codex image edit client: %s", exc)
        return None


def _image_to_data_url(image_path: str) -> tuple[str, str]:
    path = Path(os.path.expanduser(image_path)).resolve()
    if not path.exists():
        raise FileNotFoundError(f"Image file not found: {path}")
    if not path.is_file():
        raise ValueError(f"Image path is not a file: {path}")
    if path.suffix.lower() not in _SUPPORTED_IMAGE_EXTS:
        raise ValueError(
            f"Unsupported image type '{path.suffix}'. Supported: "
            + ", ".join(sorted(_SUPPORTED_IMAGE_EXTS))
        )

    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    raw = path.read_bytes()
    if not raw:
        raise ValueError(f"Image file is empty: {path}")
    b64 = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{b64}", str(path)


def _collect_image_b64_from_response(final: Any) -> Optional[str]:
    for item in getattr(final, "output", None) or []:
        if getattr(item, "type", None) == "image_generation_call":
            result = getattr(item, "result", None)
            if isinstance(result, str) and result:
                return result
    return None


def _stream_image_edit(
    client: Any,
    *,
    prompt: str,
    data_url: str,
    size: str,
    quality: str,
    input_fidelity: str,
    include_action: bool,
    include_input_fidelity: bool,
) -> Optional[str]:
    tool: Dict[str, Any] = {
        "type": "image_generation",
        "model": API_MODEL,
        "size": size,
        "quality": quality,
        "output_format": "png",
        "background": "opaque",
        "partial_images": 1,
    }
    if include_action:
        tool["action"] = "edit"
    if include_input_fidelity:
        tool["input_fidelity"] = input_fidelity

    image_b64: Optional[str] = None
    with client.responses.stream(
        model=_CODEX_CHAT_MODEL,
        store=False,
        instructions=_CODEX_INSTRUCTIONS,
        input=[{
            "type": "message",
            "role": "user",
            "content": [
                {"type": "input_text", "text": prompt},
                {"type": "input_image", "image_url": data_url},
            ],
        }],
        tools=[tool],
        tool_choice={
            "type": "allowed_tools",
            "mode": "required",
            "tools": [{"type": "image_generation"}],
        },
    ) as stream:
        for event in stream:
            event_type = getattr(event, "type", "")
            if event_type == "response.output_item.done":
                item = getattr(event, "item", None)
                if getattr(item, "type", None) == "image_generation_call":
                    result = getattr(item, "result", None)
                    if isinstance(result, str) and result:
                        image_b64 = result
            elif event_type == "response.image_generation_call.partial_image":
                partial = getattr(event, "partial_image_b64", None)
                if isinstance(partial, str) and partial:
                    image_b64 = partial
        final = stream.get_final_response()

    return image_b64 or _collect_image_b64_from_response(final)


def image_edit_tool(
    image_path: str,
    prompt: str,
    aspect_ratio: str = DEFAULT_ASPECT_RATIO,
    input_fidelity: str = "high",
) -> str:
    """Edit an existing image using Codex OAuth + GPT Image 2."""
    prompt = (prompt or "").strip()
    if not prompt:
        return json.dumps(error_response(
            error="prompt is required for image editing",
            error_type="invalid_argument",
            provider="openai-codex",
        ), ensure_ascii=False)
    if not image_path:
        return json.dumps(error_response(
            error="image_path is required for image editing",
            error_type="invalid_argument",
            provider="openai-codex",
            prompt=prompt,
        ), ensure_ascii=False)

    try:
        data_url, source_path = _image_to_data_url(image_path)
    except Exception as exc:
        return json.dumps(error_response(
            error=str(exc),
            error_type=type(exc).__name__,
            provider="openai-codex",
            prompt=prompt,
        ), ensure_ascii=False)

    if input_fidelity not in {"low", "high"}:
        input_fidelity = "high"

    if not _read_codex_access_token():
        return json.dumps(error_response(
            error="No Codex/ChatGPT OAuth credentials available. Run `hermes auth codex` to sign in.",
            error_type="auth_required",
            provider="openai-codex",
            prompt=prompt,
        ), ensure_ascii=False)

    client = _build_codex_client()
    if client is None:
        return json.dumps(error_response(
            error="Could not initialize Codex image edit client",
            error_type="auth_required",
            provider="openai-codex",
            prompt=prompt,
        ), ensure_ascii=False)

    tier_id, meta = _resolve_model()
    aspect = resolve_aspect_ratio(aspect_ratio)
    size = _SIZES.get(aspect, _SIZES["square"])
    quality = meta["quality"]

    last_error: Optional[Exception] = None
    variants: Iterable[tuple[bool, bool, str]] = (
        (True, True, "edit+input_fidelity"),
        (False, True, "input_fidelity"),
        (False, False, "input_image_only"),
    )
    for include_action, include_input_fidelity, mode in variants:
        try:
            b64 = _stream_image_edit(
                client,
                prompt=prompt,
                data_url=data_url,
                size=size,
                quality=quality,
                input_fidelity=input_fidelity,
                include_action=include_action,
                include_input_fidelity=include_input_fidelity,
            )
            if b64:
                saved_path = save_b64_image(b64, prefix=f"openai_codex_edit_{tier_id}")
                return json.dumps(success_response(
                    image=str(saved_path),
                    model=tier_id,
                    prompt=prompt,
                    aspect_ratio=aspect,
                    provider="openai-codex",
                    extra={
                        "source_image": source_path,
                        "size": size,
                        "quality": quality,
                        "input_fidelity": input_fidelity if include_input_fidelity else None,
                        "edit_mode": mode,
                    },
                ), ensure_ascii=False, indent=2)
        except Exception as exc:
            last_error = exc
            logger.debug("Codex image edit variant failed (%s)", mode, exc_info=True)
            continue

    return json.dumps(error_response(
        error=f"OpenAI image edit via Codex auth failed: {last_error}",
        error_type=type(last_error).__name__ if last_error else "empty_response",
        provider="openai-codex",
        model=tier_id,
        prompt=prompt,
        aspect_ratio=aspect,
    ), ensure_ascii=False, indent=2)


def check_image_edit_requirements() -> bool:
    return _read_codex_access_token() is not None


IMAGE_EDIT_SCHEMA = {
    "name": "image_edit",
    "description": (
        "Edit an existing image using GPT Image 2 through Codex/ChatGPT OAuth. "
        "Use this for image-to-image, reference-image editing, partial modification, editing a source/reference image, preserving pose/composition/identity, "
        "or replacing parts of an existing picture. Requires an absolute local image_path."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "image_path": {
                "type": "string",
                "description": "Absolute path to the source image file (.png, .jpg, .jpeg, .webp).",
            },
            "prompt": {
                "type": "string",
                "description": "Editing instruction. Say what to change and what to preserve.",
            },
            "aspect_ratio": {
                "type": "string",
                "enum": ["landscape", "square", "portrait"],
                "description": "Output aspect ratio. Defaults to landscape.",
            },
            "input_fidelity": {
                "type": "string",
                "enum": ["high", "low"],
                "description": "Use high to preserve source details; low allows looser edits. Defaults to high.",
            },
        },
        "required": ["image_path", "prompt"],
    },
}


def _handle_image_edit(args, **kw):
    return image_edit_tool(
        image_path=args.get("image_path", ""),
        prompt=args.get("prompt", ""),
        aspect_ratio=args.get("aspect_ratio", DEFAULT_ASPECT_RATIO),
        input_fidelity=args.get("input_fidelity", "high"),
    )


registry.register(
    name="image_edit",
    toolset="image_gen",
    schema=IMAGE_EDIT_SCHEMA,
    handler=_handle_image_edit,
    check_fn=check_image_edit_requirements,
    requires_env=[],
    is_async=False,
    emoji="edit",
)
