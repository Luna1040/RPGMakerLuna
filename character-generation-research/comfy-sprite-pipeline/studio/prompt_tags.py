from __future__ import annotations

import json
import re
import threading
import uuid
from pathlib import Path
from typing import Any, Iterable


TAGS: tuple[dict[str, str], ...] = (
    {"id": "one", "label": "Один персонаж", "kind": "positive", "text": "exactly one character"},
    {"id": "identity", "label": "Сохранить внешность", "kind": "positive", "text": "Preserve the exact character identity from the reference: identical face, eyes, hairstyle, body proportions, colors, lighting, line-art style and outline thickness in every frame. Do not redesign, reinterpret or replace any visual feature"},
    {"id": "outfit", "label": "Сохранить одежду", "kind": "positive", "text": "Preserve the exact clothing topology, materials, colors, connected fabric areas, decorations and every existing accessory. No removed pieces, new pieces, changing folds, holes, background bleed or costume regeneration"},
    {"id": "equipment", "label": "Сохранить экипировку", "kind": "positive", "text": "Preserve every held object and existing equipment with identical design, size and orientation. Each object remains continuously connected to the same anatomical hand with the same grip; never detach, morph, duplicate, disappear or swap hands"},
    {"id": "source_only", "label": "Только элементы референса", "kind": "positive", "text": "Use only anatomy, appendages, clothing, equipment and accessories actually present in the source reference. Never infer or invent a tail, wing, weapon, prop or body feature that is absent"},
    {"id": "layers", "label": "Сохранить порядок слоёв", "kind": "positive", "text": "Preserve every original attachment point and physically correct front-to-back depth and occlusion order. Existing rear-mounted elements stay behind torso and foreground clothing and appear only where physically visible around the silhouette"},
    {"id": "full_body", "label": "Полный рост", "kind": "positive", "text": "Keep the complete character silhouette fully visible, including head, hair, hands, fingers, feet, clothing edges and all existing equipment. Maintain safe equal canvas margins; never crop or push any part out of frame"},
    {"id": "camera", "label": "Фиксированная камера", "kind": "positive", "text": "The virtual camera is physically locked: fixed framing, focal length, distance, perspective and focus. No pan, tilt, roll, orbit, dolly, zoom, handheld motion, shake, reframing or lens change"},
    {"id": "scale", "label": "Фиксированный масштаб", "kind": "positive", "text": "Keep constant character scale, root position, pivot, baseline and screen position throughout. Motion occurs inside the body; the canvas never follows or recenters the movement"},
    {"id": "white", "label": "Белый фон", "kind": "positive", "text": "Use a uniform solid pure white (#FFFFFF) background with no floor, horizon, wall, gradient, texture, vignette, shadow, reflection, environment or particles"},
    {"id": "motion", "label": "Движение по пресету", "kind": "positive", "text": ""},
    {"id": "loop", "label": "Бесшовный цикл", "kind": "positive", "text": "Start at key pose A, perform the complete requested motion and return exactly to key pose A. First and last frames match in composition, scale, baseline, pivot and foot placement; no frozen middle frames or seam jump"},
    {"id": "two_steps", "label": "Два разных шага", "kind": "positive", "text": "exactly two distinct steps, each leg taking one turn as the leading leg"},
    {"id": "left", "label": "Ракурс влево", "kind": "positive", "text": "stable left-facing three-quarter side view"},
    {"id": "right", "label": "Ракурс вправо", "kind": "positive", "text": "stable right-facing three-quarter side view"},
    {"id": "no_extra", "label": "Без новых объектов", "kind": "negative", "text": "extra character, invented anatomy, invented appendage, new equipment, new accessory"},
    {"id": "no_crop", "label": "Без обрезания", "kind": "negative", "text": "cropped head, cropped body, cropped hands, cropped feet, cropped equipment, out of frame"},
    {"id": "no_anatomy", "label": "Без дефектов анатомии", "kind": "negative", "text": "extra limbs, missing limbs, malformed hands, fused anatomy, duplicate body parts"},
    {"id": "no_camera", "label": "Без движения камеры", "kind": "negative", "text": "camera motion, pan, tilt, orbit, zoom, shake, reframing, perspective drift"},
    {"id": "no_scale", "label": "Без дрейфа масштаба", "kind": "negative", "text": "scale drift, root drift, baseline drift, position drift"},
    {"id": "no_artifacts", "label": "Без артефактов", "kind": "negative", "text": "text, watermark, border, grid, guide lines, alpha holes, background leakage"},
    {"id": "no_layers", "label": "Без ошибок слоёв", "kind": "negative", "text": "incorrect layer order, impossible occlusion, rear element drawn over foreground clothing"},
    {"id": "no_mirror", "label": "Без отражения", "kind": "negative", "text": "mirrored character, swapped hand, swapped equipment"},
    {"id": "no_front", "label": "Не смотреть в камеру", "kind": "negative", "text": "front-facing, facing viewer, walking toward camera"},
)

TAG_BY_ID = {tag["id"]: tag for tag in TAGS}
BASE_POSITIVE = ("one", "identity", "outfit", "equipment", "source_only", "layers", "full_body", "camera", "scale", "white", "motion")
BASE_NEGATIVE = ("no_extra", "no_crop", "no_anatomy", "no_camera", "no_scale", "no_artifacts", "no_layers", "no_mirror")


def defaults(action: str, stage: str) -> dict[str, list[str]]:
    positive, negative = list(BASE_POSITIVE), list(BASE_NEGATIVE)
    if stage == "w2":
        positive.append("loop")
    if stage == "w2" and (action.startswith("walk_") or action.startswith("run_")):
        positive.append("two_steps")
    direction = {"walk_left": "left", "walk_right": "right", "run_left": "left", "run_right": "right"}.get(action)
    if direction:
        positive.append(direction)
        negative.append("no_front")
    return {"positive": positive, "negative": negative}


class PromptTagStore:
    def __init__(self, path: Path):
        self.path = path
        self._lock = threading.RLock()

    def list(self) -> list[dict[str, str]]:
        with self._lock:
            if not self.path.is_file():
                return []
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return [tag for tag in data if isinstance(tag, dict)]

    def create(self, *, label: str, text: str, kind: str) -> dict[str, str]:
        label, text, kind = label.strip(), text.strip(), kind.strip()
        if kind not in {"positive", "negative"}:
            raise ValueError("prompt tag kind must be positive or negative")
        if not (2 <= len(label) <= 60) or not re.search(r"[А-Яа-яЁё]", label):
            raise ValueError("prompt tag label must be 2-60 characters and contain Russian text")
        if not (3 <= len(text) <= 1000) or not re.search(r"[A-Za-z]", text):
            raise ValueError("prompt tag instruction must be 3-1000 characters and contain English text")
        with self._lock:
            tags = self.list()
            if any(tag.get("label", "").casefold() == label.casefold() and tag.get("kind") == kind for tag in tags):
                raise ValueError("a prompt tag with this label already exists")
            tag = {"id": f"custom_{uuid.uuid4().hex[:12]}", "label": label, "kind": kind, "text": text, "custom": True}
            tags.append(tag)
            self._write(tags)
            return tag

    def delete(self, tag_id: str) -> None:
        with self._lock:
            tags = self.list()
            remaining = [tag for tag in tags if tag.get("id") != tag_id]
            if len(remaining) == len(tags):
                raise ValueError("custom prompt tag not found")
            self._write(remaining)

    def by_id(self) -> dict[str, dict[str, str]]:
        return {str(tag["id"]): tag for tag in self.list()}

    def _write(self, tags: list[dict[str, str]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(tags, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(self.path)


def public_catalog(action: str = "", stage: str = "w1", custom: Iterable[dict[str, str]] = ()) -> dict[str, Any]:
    selected = defaults(action, stage)
    return {"tags": list(TAGS) + list(custom), "defaults": selected}


def compile_tags(ids: Iterable[Any], kind: str, custom: str = "", *, action: str = "", stage: str = "w1", custom_tags: dict[str, dict[str, str]] | None = None) -> str:
    fragments: list[str] = []
    for raw_id in ids:
        tag = TAG_BY_ID.get(str(raw_id).strip()) or (custom_tags or {}).get(str(raw_id).strip())
        if not tag or tag["kind"] != kind:
            raise ValueError(f"unsupported {kind} prompt tag: {raw_id}")
        text = tag["text"]
        if tag["id"] == "motion":
            from drivers.pose_presets import get_preset

            preset_id = {"idle": "idle_breathing", "idle_smile": "idle_smile"}.get(action, action)
            preset = get_preset(preset_id)
            text = preset.pose_description if stage == "w1" else preset.motion_prompt
        if text and text not in fragments:
            fragments.append(text)
    custom = str(custom or "").strip()
    if len(custom) > 1000:
        raise ValueError(f"custom {kind} prompt is too long")
    if custom:
        fragments.append(custom)
    return ", ".join(fragments)
