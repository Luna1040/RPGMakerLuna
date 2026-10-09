from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from studio.store import StudioStore


class ComponentActionRemovalTests(unittest.TestCase):
    def test_removing_one_action_deletes_only_its_records_and_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            store = StudioStore(Path(temporary))
            project = store.create_project("Removal test")
            project_id = project["id"]
            store.save_component_animation(
                project_id,
                action_id="idle",
                filename="idle.png",
                data=b"idle-sheet",
                frame_count=8,
                fps=12,
                w1_filename="idle-w1.png",
                w1_data=b"idle-w1",
                w2_filename="idle-w2.mp4",
                w2_data=b"idle-w2",
            )
            project, _ = store.save_component_animation(
                project_id,
                action_id="idle_3",
                filename="idle-3.png",
                data=b"idle-3-sheet",
                frame_count=8,
                fps=12,
                w1_filename="idle-3-w1.png",
                w1_data=b"idle-3-w1",
                w2_filename="idle-3-w2.mp4",
                w2_data=b"idle-3-w2",
            )
            store.set_component_actions(project_id, ["idle", "idle_3"])
            removed_ids = {
                project["component"]["actions"]["idle_3"]["asset_id"],
                *project["component"]["actions"]["idle_3"]["stages"].values(),
            }

            updated = store.remove_component_action(project_id, "idle_3")

            self.assertEqual(updated["component"]["requested_actions"], ["idle"])
            self.assertNotIn("idle_3", updated["component"]["actions"])
            self.assertIn("idle", updated["component"]["actions"])
            for asset_id in removed_ids:
                self.assertNotIn(asset_id, updated["assets"])
                self.assertFalse(any((store.projects_root / project_id / "assets").glob(f"{asset_id}.*")))

    def test_last_component_action_cannot_be_removed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            store = StudioStore(Path(temporary))
            project = store.create_project("Removal guard")
            store.set_component_actions(project["id"], ["idle"])

            with self.assertRaisesRegex(ValueError, "last component action"):
                store.remove_component_action(project["id"], "idle")


if __name__ == "__main__":
    unittest.main()