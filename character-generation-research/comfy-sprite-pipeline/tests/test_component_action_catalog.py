from __future__ import annotations

import re
import unittest
from pathlib import Path

from drivers.pose_presets import POSE_PRESETS
from studio.components import PUBLIC_ACTIONS, component_motion_id, component_requested_actions


ROOT = Path(__file__).resolve().parents[1]
CREATOR_HTML = ROOT / "viewer" / "static" / "character-creator.html"


def _html_action_ids(attribute: str) -> list[str]:
    html = CREATOR_HTML.read_text(encoding="utf-8")
    return re.findall(rf'{attribute}="([a-z0-9_]+)"', html)


def _creator_uses_public_catalog() -> bool:
    script = (ROOT / "viewer" / "static" / "character-creator.js").read_text(encoding="utf-8")
    return "/api/component-actions" in script and "renderActionOptions" in script


class ComponentActionCatalogTest(unittest.TestCase):
    def test_every_result_button_has_an_end_to_end_public_action(self) -> None:
        button_actions = _html_action_ids("data-command")

        self.assertEqual(len(button_actions), len(set(button_actions)))
        self.assertEqual(set(button_actions), set(PUBLIC_ACTIONS))
        for action_id, definition in PUBLIC_ACTIONS.items():
            self.assertIn(definition["motion_id"], POSE_PRESETS, action_id)

    def test_every_result_button_can_be_selected_during_character_creation(self) -> None:
        self.assertTrue(_creator_uses_public_catalog())

    def test_original_pipeline_resolves_every_public_action_to_its_preset(self) -> None:
        runner = (ROOT / "studio" / "runner.py").read_text(encoding="utf-8")

        self.assertIn("component_motion_id(action)", runner)
        for action_id, definition in PUBLIC_ACTIONS.items():
            with self.subTest(action_id=action_id):
                self.assertEqual(component_motion_id(action_id), definition["motion_id"])

    def test_public_action_definitions_expose_ui_metadata(self) -> None:
        allowed_groups = {"idle", "locomotion", "traversal", "combat", "interaction", "spells"}
        for action_id, definition in PUBLIC_ACTIONS.items():
            with self.subTest(action_id=action_id):
                self.assertTrue(definition["label"])
                self.assertIn(definition["group"], allowed_groups)
                self.assertIsInstance(definition["default_selected"], bool)
                self.assertIn(definition.get("playback", "loop"), {"loop", "once_return"})

    def test_project_requested_actions_override_stale_failed_job_actions(self) -> None:
        project = {
            "component": {
                "requested_actions": ["idle", "idle_smile"],
                "actions": {"idle": {"status": "ready"}, "idle_3": {"status": "rendering"}},
            }
        }

        self.assertEqual(
            component_requested_actions(project, ["idle", "idle_smile", "idle_3"]),
            ["idle", "idle_smile"],
        )

    def test_legacy_project_uses_ready_records_instead_of_failed_job_clutter(self) -> None:
        project = {
            "component": {
                "actions": {
                    "idle": {"status": "ready"},
                    "idle_smile": {"status": "ready"},
                    "idle_3": {"status": "rendering"},
                },
            }
        }

        self.assertEqual(
            component_requested_actions(project, ["idle", "idle_smile", "idle_3", "attack_light"]),
            ["idle", "idle_smile"],
        )


if __name__ == "__main__":
    unittest.main()
