from __future__ import annotations

from copy import deepcopy
from typing import Any

from .visemes import VISEME_ATLAS_SCHEMA, VISEME_TIMELINE_SCHEMA


def build_runtime_manifest(project: dict[str, Any], loadout_id: str | None = None) -> dict[str, Any]:
    """Build a deterministic playback contract for one loadout.

    Body clips may only switch after their final runtime frame; the next clip
    always enters through frame zero of the accepted loadout anchor. Mouth and
    face layers are intentionally independent channels.
    """

    selected = str(loadout_id or project.get("active_loadout_id", "default"))
    loadout = next((item for item in project.get("loadouts", []) if item.get("id") == selected), None)
    if loadout is None:
        raise ValueError(f"unknown loadout: {selected}")
    anchors = project.get("anchors", {})
    anchor = anchors.get(selected) if isinstance(anchors, dict) else None
    if not isinstance(anchor, dict):
        anchor = project.get("anchor", {}) if selected == project.get("active_loadout_id", "default") else {}
    if anchor.get("status") != "ready" or not anchor.get("asset_id"):
        raise ValueError(f"loadout anchor is not ready: {selected}")
    assets = project.get("assets", {}) if isinstance(project.get("assets"), dict) else {}
    anchor_asset = assets.get(anchor.get("asset_id"))
    if not isinstance(anchor_asset, dict) or anchor_asset.get("role") != "anchor":
        raise ValueError(f"loadout anchor asset is missing or invalid: {selected}")

    clips: dict[str, dict[str, Any]] = {}
    face_clips: dict[str, dict[str, Any]] = {}
    for clip in project.get("clips", {}).values():
        if str(clip.get("loadout_id", "default")) != selected:
            continue
        runtime_frames = int(clip.get("runtime_frame_count", 0) or 0)
        spritesheet_asset_id = clip.get("runtime_spritesheet_asset_id") or clip.get("spritesheet_asset_id")
        if (
            runtime_frames < 1
            or clip.get("runtime_ready") is not True
            or clip.get("status") != "ready"
            or not spritesheet_asset_id
            or clip.get("anchor_asset_id") != anchor.get("asset_id")
            or clip.get("anchor_revision") != anchor.get("revision")
            or not isinstance(assets.get(spritesheet_asset_id), dict)
            or assets[spritesheet_asset_id].get("role") != "clip_runtime_spritesheet"
        ):
            continue
        motion_id = str(clip.get("id", ""))
        if not motion_id:
            continue
        target = face_clips if clip.get("layer") == "face" or clip.get("channel") == "face" else clips
        target[motion_id] = {
            "id": motion_id,
            "status": clip.get("status"),
            "runtime_ready": True,
            "spritesheet_asset_id": spritesheet_asset_id,
            "frame_count": runtime_frames,
            "entry_gate_frame": int(clip.get("entry_gate_frame", 0)),
            "exit_gate_frame": int(clip.get("exit_gate_frame", runtime_frames - 1)),
            "neutral_corridor_frames": int(clip.get("neutral_corridor_frames", 0) or 0),
            "switch_policy": "neutral_gate",
            "roi_kind": "eye" if motion_id == "blink" else "mouth" if target is face_clips else None,
            "anchor_asset_id": clip.get("anchor_asset_id"),
            "anchor_revision": clip.get("anchor_revision"),
        }

    neutral_clip = clips.get("idle_breathing")
    if neutral_clip is None and clips:
        neutral_clip = clips[sorted(clips)[0]]

    voice = project.get("voice", {})
    atlases = voice.get("atlases", {})
    atlas = atlases.get(selected, {}) if isinstance(atlases, dict) else {}
    if not atlas and selected == project.get("active_loadout_id", "default"):
        atlas = {
            "status": voice.get("atlas_status"),
            "atlas_asset_id": voice.get("atlas_asset_id"),
            "manifest": voice.get("atlas_manifest"),
        }
    timeline = voice.get("timeline") if isinstance(voice.get("timeline"), dict) else None
    atlas_manifest = atlas.get("manifest") if isinstance(atlas.get("manifest"), dict) else None
    timeline_atlas = timeline.get("atlas") if isinstance(timeline, dict) and isinstance(timeline.get("atlas"), dict) else None
    timeline_audio = timeline.get("audio") if isinstance(timeline, dict) and isinstance(timeline.get("audio"), dict) else None
    audio_asset_id = voice.get("audio_asset_id")
    atlas_asset_valid = bool(
        isinstance(assets.get(atlas.get("atlas_asset_id")), dict)
        and assets[atlas.get("atlas_asset_id")].get("role") == "viseme_atlas"
    )
    timeline_asset_valid = bool(
        isinstance(assets.get(voice.get("timeline_asset_id")), dict)
        and assets[voice.get("timeline_asset_id")].get("role") == "voice_timeline"
    )
    audio_asset_valid = bool(
        isinstance(assets.get(audio_asset_id), dict)
        and assets[audio_asset_id].get("role") == "audio"
    )
    mouth_ready = bool(
        atlas.get("status") == "ready"
        and atlas.get("atlas_asset_id")
        and atlas_asset_valid
        and atlas.get("anchor_asset_id") == anchor.get("asset_id")
        and atlas.get("anchor_revision") == anchor.get("revision")
        and atlas_manifest
        and atlas_manifest.get("schema_version") == VISEME_ATLAS_SCHEMA
        and atlas_manifest.get("loadout_id") == selected
        and atlas_manifest.get("anchor_asset_id") == anchor.get("asset_id")
        and atlas_manifest.get("anchor_revision") == anchor.get("revision")
        and voice.get("timeline_status") == "ready"
        and voice.get("timeline_asset_id")
        and timeline_asset_valid
        and timeline
        and timeline.get("schema_version") == VISEME_TIMELINE_SCHEMA
        and timeline.get("runtime_ready") is True
        and timeline_atlas
        and timeline_atlas.get("atlas_asset_id") == atlas.get("atlas_asset_id")
        and timeline_atlas.get("loadout_id") == selected
        and timeline_atlas.get("anchor_asset_id") == anchor.get("asset_id")
        and timeline_atlas.get("anchor_revision") == anchor.get("revision")
        and audio_asset_id
        and audio_asset_valid
        and timeline_audio
        and timeline_audio.get("asset_id") == audio_asset_id
    )
    return {
        "schema": "studio.runtime.v1",
        "project_id": project.get("id"),
        "project_revision": project.get("revision"),
        "loadout_id": selected,
        "loadout": deepcopy(loadout),
        "anchor": {
            "asset_id": anchor.get("asset_id"),
            "revision": anchor.get("revision"),
            # A published body clip always begins with the exact accepted
            # anchor. Reuse its W12 RGBA frame as the transparent neutral base
            # instead of drawing the original white-background review image.
            "runtime_ready": neutral_clip is not None,
            "runtime_spritesheet_asset_id": (
                neutral_clip.get("spritesheet_asset_id") if neutral_clip is not None else None
            ),
            "runtime_frame": (
                int(neutral_clip.get("entry_gate_frame", 0)) if neutral_clip is not None else None
            ),
            "canvas": deepcopy(anchor.get("canvas")),
            "root": deepcopy(anchor.get("root")),
            "ground_y": anchor.get("ground_y"),
            "mouth_roi": deepcopy(anchor.get("mouth_roi") or voice.get("mouth_roi")),
            "eye_roi": deepcopy(anchor.get("eye_roi")),
        },
        "channels": {
            "body": {"switch_policy": "neutral_gate", "clips": clips},
            "face": {"switch_policy": "neutral_gate", "clips": face_clips},
            "mouth": {
                "mode": voice.get("mode", "viseme_atlas"),
                "runtime_ready": mouth_ready,
                "atlas_status": atlas.get("status", "missing"),
                "atlas_asset_id": atlas.get("atlas_asset_id") if mouth_ready else None,
                "atlas_manifest_asset_id": atlas.get("manifest_asset_id") if mouth_ready else None,
                "atlas": deepcopy(atlas_manifest) if mouth_ready else None,
                "timeline_status": voice.get("timeline_status", "missing"),
                "timeline_asset_id": voice.get("timeline_asset_id") if mouth_ready else None,
                "timeline": deepcopy(timeline) if mouth_ready else None,
                "audio_asset_id": audio_asset_id if mouth_ready else None,
                "clock": "audio",
            },
        },
    }


class NeutralGateController:
    """Small state machine used by tests and non-browser runtimes."""

    def __init__(self, manifest: dict[str, Any], initial_clip: str | None = None):
        self.manifest = manifest
        self.clips = manifest.get("channels", {}).get("body", {}).get("clips", {})
        self.current = (
            initial_clip
            if initial_clip in self.clips and self.clips[initial_clip].get("runtime_ready") is True
            else None
        )
        self.pending: str | None = None

    def request(self, motion_id: str) -> None:
        if motion_id not in self.clips or self.clips[motion_id].get("runtime_ready") is not True:
            raise ValueError(f"unknown runtime motion: {motion_id}")
        if self.current is None:
            self.current = motion_id
            self.pending = None
        else:
            self.pending = motion_id

    def advance(self, frame_index: int) -> str | None:
        if self.current is None or self.pending is None:
            return self.current
        current = self.clips[self.current]
        if frame_index >= int(current["exit_gate_frame"]):
            self.current = self.pending
            self.pending = None
        return self.current
