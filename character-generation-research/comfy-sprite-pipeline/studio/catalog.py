from __future__ import annotations

from copy import deepcopy
from typing import Any


SCHEMA_VERSION = 2

REFERENCE_ROLES: tuple[dict[str, Any], ...] = (
    {
        "id": "primary",
        "label": "Основной",
        "required": True,
        "accept": "image",
        "description": "Полный рост; обе руки, лицо и постоянный реквизит должны быть видны.",
    },
    {
        "id": "secondary",
        "label": "Дополнительный ракурс",
        "required": False,
        "accept": "image",
        "description": "Другой ракурс или изображение скрытой стороны персонажа.",
    },
    {
        "id": "detail",
        "label": "Деталь",
        "required": False,
        "accept": "image",
        "description": "Крупный план лица, кистей или важной детали дизайна.",
    },
)

PROP_SLOTS: tuple[dict[str, Any], ...] = (
    {"id": "left_hand", "label": "Левая рука", "handed": True},
    {"id": "right_hand", "label": "Правая рука", "handed": True},
    {"id": "both_hands", "label": "Обе руки", "handed": True},
    {"id": "back", "label": "Спина", "handed": False},
    {"id": "attached", "label": "Закреплён", "handed": False},
    {"id": "free", "label": "Свободный объект", "handed": False},
    {"id": "fx", "label": "FX-слой", "handed": False},
)

GRIP_TYPES: tuple[dict[str, str], ...] = (
    {"id": "none", "label": "Без хвата"},
    {"id": "one_handed", "label": "Одной рукой"},
    {"id": "two_handed", "label": "Двумя руками"},
)

BODY_CHANNELS: tuple[dict[str, Any], ...] = (
    {"id": "whole_body", "label": "Всё тело", "color": "#a78bfa"},
    {"id": "left_arm", "label": "Левая рука", "color": "#56d6c9"},
    {"id": "right_arm", "label": "Правая рука", "color": "#ffb454"},
    {"id": "both_arms", "label": "Обе руки", "color": "#f472b6"},
    {"id": "head", "label": "Голова", "color": "#60a5fa"},
    {"id": "torso", "label": "Корпус", "color": "#c4b5fd"},
    {"id": "locomotion", "label": "Перемещение", "color": "#fb7185"},
    {"id": "face", "label": "Лицо", "color": "#facc15"},
    {"id": "mouth", "label": "Рот", "color": "#f97316"},
)


def _motion(
    motion_id: str,
    label: str,
    channel: str,
    prompt: str,
    *,
    side: str = "none",
    mode: str = "prompt_loop",
    frames: int = 17,
    fps: int = 16,
    amplitude: str = "medium",
    hand_policy: str = "any",
    one_shot: bool = True,
    neutral_corridor_frames: int | None = None,
) -> dict[str, Any]:
    corridor = neutral_corridor_frames
    if corridor is None:
        corridor = 4 if frames >= 33 else 2
    corridor = max(1, min(int(corridor), max(1, (frames - 1) // 4)))
    return {
        "id": motion_id,
        "label": label,
        "channel": channel,
        "side": side,
        "generation_mode": mode,
        "frames": frames,
        "runtime_frames": frames - 1,
        "fps": fps,
        "amplitude": amplitude,
        "hand_policy": hand_policy,
        "playback": "once_return" if one_shot else "loop",
        "neutral_corridor_frames": corridor,
        "entry_gate_frame": 0,
        "exit_gate_frame": frames - 2,
        "prompt": prompt,
    }


MOTIONS: tuple[dict[str, Any], ...] = (
    _motion(
        "idle_breathing",
        "Спокойное дыхание",
        "whole_body",
        "one complete subtle breathing cycle, feet and root locked, return exactly to the neutral anchor",
        frames=33,
        fps=12,
        mode="pose_control",
        amplitude="subtle",
        one_shot=False,
    ),
    _motion(
        "idle_smile",
        "Спокойное дыхание с улыбкой",
        "whole_body",
        "one complete subtle breathing cycle with a clear warm closed-mouth smile and happy eyes during the action phase, feet and root locked, return exactly to the neutral anchor",
        frames=33,
        fps=12,
        mode="pose_control",
        amplitude="subtle",
        one_shot=False,
    ),
    _motion(
        "bounce",
        "Мягко подпрыгнуть",
        "whole_body",
        "one small friendly body bounce in place, settle and return exactly to the neutral anchor",
        mode="pose_control",
        frames=33,
        amplitude="small",
    ),
    _motion(
        "wave_left",
        "Махнуть левой рукой",
        "left_arm",
        "the character raises and waves their anatomical LEFT hand once, the right arm stays neutral, then returns exactly to anchor",
        side="anatomical_left",
        mode="pose_control",
        frames=33,
        hand_policy="left_free_or_attached",
    ),
    _motion(
        "wave_right",
        "Махнуть правой рукой",
        "right_arm",
        "the character raises and waves their anatomical RIGHT hand once, the left arm stays neutral, then returns exactly to anchor",
        side="anatomical_right",
        mode="pose_control",
        frames=33,
        hand_policy="right_free_or_attached",
    ),
    _motion(
        "point_left",
        "Указать левой рукой",
        "left_arm",
        "point clearly with the anatomical LEFT hand, hold briefly, lower the arm and return exactly to anchor",
        side="anatomical_left",
        mode="pose_control",
        frames=33,
        hand_policy="left_free",
    ),
    _motion(
        "point_right",
        "Указать правой рукой",
        "right_arm",
        "point clearly with the anatomical RIGHT hand, hold briefly, lower the arm and return exactly to anchor",
        side="anatomical_right",
        mode="pose_control",
        frames=33,
        hand_policy="right_free",
    ),
    _motion(
        "present_left",
        "Показать слева",
        "left_arm",
        "open the anatomical LEFT palm in a presenting gesture toward screen left, then return exactly to anchor",
        side="anatomical_left",
        mode="pose_control",
        frames=33,
        hand_policy="left_free",
    ),
    _motion(
        "present_right",
        "Показать справа",
        "right_arm",
        "open the anatomical RIGHT palm in a presenting gesture toward screen right, then return exactly to anchor",
        side="anatomical_right",
        mode="pose_control",
        frames=33,
        hand_policy="right_free",
    ),
    _motion(
        "shrug",
        "Пожать плечами",
        "both_arms",
        "one clear friendly shrug with both palms open, relax and return exactly to anchor",
        mode="pose_control",
        frames=33,
        hand_policy="both_free",
    ),
    _motion(
        "clap_once",
        "Хлопнуть в ладоши",
        "both_arms",
        "bring both hands together for exactly one clap, separate, relax and return exactly to anchor",
        mode="pose_control",
        frames=33,
        hand_policy="both_free",
    ),
    _motion(
        "welcome",
        "Приветственный жест",
        "both_arms",
        "open both arms in one warm welcoming gesture, hold briefly, then return exactly to anchor",
        mode="pose_control",
        frames=33,
        hand_policy="both_free_or_attached",
    ),
    _motion(
        "look_left",
        "Голова влево",
        "head",
        "turn only the head toward the character's anatomical left, hold, return exactly to the neutral head pose",
        side="anatomical_left",
        mode="pose_control",
        amplitude="small",
    ),
    _motion(
        "look_right",
        "Голова вправо",
        "head",
        "turn only the head toward the character's anatomical right, hold, return exactly to the neutral head pose",
        side="anatomical_right",
        mode="pose_control",
        amplitude="small",
    ),
    _motion(
        "look_up",
        "Голова вверх",
        "head",
        "tilt the gaze and head slightly upward, hold, return exactly to neutral",
        mode="pose_control",
        amplitude="small",
    ),
    _motion(
        "look_down",
        "Голова вниз",
        "head",
        "tilt the gaze and head slightly downward, hold, return exactly to neutral",
        mode="pose_control",
        amplitude="small",
    ),
    _motion(
        "nod",
        "Кивнуть",
        "head",
        "perform exactly one readable head nod, torso stable, return exactly to neutral",
        mode="pose_control",
        amplitude="small",
    ),
    _motion(
        "shake_head",
        "Покачать головой",
        "head",
        "perform one gentle left-right head shake, torso stable, return exactly to neutral",
        mode="pose_control",
        amplitude="small",
    ),
    _motion(
        "lean_left",
        "Наклон корпуса влево",
        "torso",
        "lean the torso slightly to the character's anatomical left while feet and root stay fixed, return exactly to anchor",
        side="anatomical_left",
        mode="pose_control",
        frames=33,
        amplitude="small",
    ),
    _motion(
        "lean_right",
        "Наклон корпуса вправо",
        "torso",
        "lean the torso slightly to the character's anatomical right while feet and root stay fixed, return exactly to anchor",
        side="anatomical_right",
        mode="pose_control",
        frames=33,
        amplitude="small",
    ),
    _motion(
        "jump_vertical",
        "Прыжок на месте",
        "locomotion",
        "one complete vertical jump in place, land on the identical ground line and return exactly to anchor",
        mode="pose_control",
        frames=33,
        fps=16,
    ),
    _motion(
        "walk_in_place",
        "Шаг на месте",
        "locomotion",
        "one complete two-step walk cycle in place with root motion disabled and exact return to the starting pose",
        mode="pose_control",
        frames=25,
        fps=12,
        one_shot=False,
    ),
    _motion(
        "run_in_place",
        "Бег на месте",
        "locomotion",
        "one complete running cycle in place with root motion disabled and exact return to the starting pose",
        mode="pose_control",
        frames=25,
        fps=14,
        one_shot=False,
    ),
    _motion(
        "blink",
        "Моргание",
        "face",
        "one natural blink while the rest of the face and body stay unchanged",
        mode="face_layer",
        frames=9,
        amplitude="subtle",
    ),
    _motion(
        "smile",
        "Улыбка",
        "face",
        "form a warm smile, hold briefly, then return to the neutral expression",
        mode="face_layer",
        frames=17,
        amplitude="small",
    ),
)

VISEMES: tuple[dict[str, Any], ...] = (
    {"id": "closed", "label": "Закрыт", "examples": "silence, pause", "hotkey": "0"},
    {"id": "rest", "label": "Покой", "examples": "neutral", "hotkey": "1"},
    {"id": "A_AI", "label": "A / AI", "examples": "а, я, ай", "hotkey": "2"},
    {"id": "E", "label": "E", "examples": "э, е", "hotkey": "3"},
    {"id": "I", "label": "I", "examples": "и, й", "hotkey": "4"},
    {"id": "O", "label": "O", "examples": "о, ё", "hotkey": "5"},
    {"id": "U", "label": "U", "examples": "у, ю", "hotkey": "6"},
    {"id": "FV", "label": "F / V", "examples": "ф, в", "hotkey": "7"},
    {"id": "L", "label": "L", "examples": "л", "hotkey": "8"},
    {"id": "MBP", "label": "M / B / P", "examples": "м, б, п", "hotkey": "9"},
)

QUALITY_PROFILES: tuple[dict[str, Any], ...] = (
    {
        "id": "local_12gb",
        "label": "Local 12 GB",
        "width": 384,
        "height": 384,
        "default": True,
        "description": "Фазовая загрузка и агрессивный offload для RTX 4070 12 GB.",
    },
    {
        "id": "quality_512",
        "label": "Quality 512",
        "width": 512,
        "height": 512,
        "default": False,
        "description": "Медленнее и с большим CPU offload; требует отдельной проверки памяти.",
    },
)

# Deterministic COCO-18 guide generators implemented by studio.pose_guides.
# Motions outside this set remain explicitly blocked even if the VACE model is installed.
POSE_GUIDE_MOTIONS: frozenset[str] = frozenset(
    {
        "idle_breathing",
        "idle_smile",
        "bounce",
        "wave_left",
        "wave_right",
        "point_left",
        "point_right",
        "present_left",
        "present_right",
        "shrug",
        "clap_once",
        "welcome",
        "look_left",
        "look_right",
        "look_up",
        "look_down",
        "nod",
        "shake_head",
        "lean_left",
        "lean_right",
        "jump_vertical",
        "walk_in_place",
        "run_in_place",
    }
)


def studio_schema() -> dict[str, Any]:
    """Return an isolated JSON-serializable schema for the Studio UI."""
    return deepcopy(
        {
            "schema_version": SCHEMA_VERSION,
            "reference_roles": REFERENCE_ROLES,
            "prop_slots": PROP_SLOTS,
            "grip_types": GRIP_TYPES,
            "body_channels": BODY_CHANNELS,
            "motions": MOTIONS,
            "visemes": VISEMES,
            "quality_profiles": QUALITY_PROFILES,
            "direction_convention": {
                "left": "anatomical left of the character",
                "right": "anatomical right of the character",
            },
        }
    )


def get_motion(motion_id: str) -> dict[str, Any] | None:
    return next((deepcopy(item) for item in MOTIONS if item["id"] == motion_id), None)
