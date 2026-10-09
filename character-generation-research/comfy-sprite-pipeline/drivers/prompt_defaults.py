from __future__ import annotations


DEFAULT_SHADOW_NEGATIVE = (
    "shadow, cast shadow, drop shadow, ground shadow, contact shadow, floor shadow, "
    "shading below feet, dark shape under character, dark oval, ellipse under feet, "
    "floor ellipse, ground marker"
)


def merge_negative_prompts(*parts: str) -> str:
    """Combine required and user negative prompts without dropping defaults."""

    return ", ".join(part.strip(" ,") for part in parts if part and part.strip(" ,"))
