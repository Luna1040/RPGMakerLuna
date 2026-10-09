from __future__ import annotations

import math
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageOps


SLOT_PROMPTS = {
    "left_hand": "held in the character's anatomical LEFT hand",
    "right_hand": "held in the character's anatomical RIGHT hand",
    "both_hands": "held with BOTH hands",
    "back": "secured on the character's back",
    "attached": "physically attached to the character",
    "free": "present as a separate nearby object",
    "fx": "present only as a separate effect layer",
}


def select_loadout_props(project: dict[str, Any], loadout_id: str = "default") -> list[dict[str, Any]]:
    loadout = next((item for item in project.get("loadouts", []) if item.get("id") == loadout_id), None)
    if loadout is None:
        raise ValueError(f"unknown loadout: {loadout_id}")
    selected_ids = set(loadout.get("prop_ids", []))
    return [item for item in project.get("props", []) if item.get("id") in selected_ids]


def persistent_loadout_props(project: dict[str, Any], loadout_id: str = "default") -> list[dict[str, Any]]:
    return [item for item in select_loadout_props(project, loadout_id) if item.get("persistent")]


def equipment_prompt(props: Iterable[dict[str, Any]]) -> str:
    descriptions: list[str] = []
    for prop in props:
        slot = str(prop.get("slot", "free"))
        description = f"exactly one {prop.get('name', prop.get('id', 'prop'))}, {SLOT_PROMPTS.get(slot, slot)}"
        hint = str(prop.get("prompt_hint", "")).strip()
        if hint:
            description += f" ({hint})"
        descriptions.append(description)
    if not descriptions:
        return ""
    return (
        " Persistent equipment instances that must remain visible, distinct and unchanged in every frame: "
        + "; ".join(descriptions)
        + ". Do not duplicate, swap, mirror, drop or redesign any instance."
    )


def canonical_equipment_prompt(props: Iterable[dict[str, Any]]) -> str:
    """Describe equipment cardinality for multi-view W6 identity consolidation."""

    selected = list(props)
    view_contract = (
        " Image 1 is the sole authority for equipment count and anatomical placement. "
        "Images 2 and 3 are alternate views or details of the SAME physical character and SAME physical objects; "
        "an object appearing on another screen side in a back or detail view is not another instance. "
        "Never merge screen-left and screen-right appearances into duplicate equipment."
    )
    if not selected:
        return (
            view_contract
            + " Preserve exactly the equipment instances visible in image 1 and add no extra held, carried, "
            "attached or nearby object from the alternate/detail views."
        )
    return (
        view_contract
        + " The following declared loadout is the complete equipment list; include exactly these instances and no "
        "other held, carried, attached or nearby objects:"
        + equipment_prompt(selected)
    )


def build_reference_contact_sheet(
    sources: Iterable[str | Path],
    target: str | Path,
    *,
    width: int,
    height: int,
) -> Path:
    """Pack detail/prop references into Qwen's third image without changing their aspect ratios."""

    paths = [Path(item) for item in sources]
    if not paths:
        raise ValueError("contact sheet requires at least one source")
    if width <= 0 or height <= 0:
        raise ValueError("contact sheet size must be positive")
    columns = 1 if len(paths) == 1 else 2
    rows = math.ceil(len(paths) / columns)
    gap = max(2, round(min(width, height) * 0.01))
    tile_width = (width - gap * (columns + 1)) // columns
    tile_height = (height - gap * (rows + 1)) // rows
    if tile_width <= 0 or tile_height <= 0:
        raise ValueError("too many references for the contact sheet canvas")

    canvas = Image.new("RGB", (width, height), "white")
    for index, path in enumerate(paths):
        with Image.open(path) as opened:
            reference = ImageOps.exif_transpose(opened).convert("RGB")
            fitted = ImageOps.contain(reference, (tile_width, tile_height), Image.Resampling.LANCZOS)
        column = index % columns
        row = index // columns
        tile_x = gap + column * (tile_width + gap)
        tile_y = gap + row * (tile_height + gap)
        x = tile_x + (tile_width - fitted.width) // 2
        y = tile_y + (tile_height - fitted.height) // 2
        canvas.paste(fitted, (x, y))

    output = Path(target)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="PNG")
    return output
