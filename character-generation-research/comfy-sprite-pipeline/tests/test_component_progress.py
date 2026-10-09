import unittest
from pathlib import Path

from studio.components import component_build_progress


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class ComponentBuildProgressTests(unittest.TestCase):
    def test_non_rerun_w2_marker_overrides_stale_w1_progress_event(self):
        job = {
            "status": "running",
            "params": {"actions": ["walk_right"]},
            "log_text": "\n".join(
                [
                    "Build 2/3 (1/1): original W1/W2/W3 pipeline for walk_right.",
                    "[PIPE/W1] character_walk_right",
                    'PROGRESS_JSON: {"stage": "w1", "percent": 100}',
                    'STAGE_JSON: {"stage": "w1", "path": "/tmp/keyframe.png"}',
                    "[PIPE/W2] character_walk_right",
                    "  enqueued: prompt-id",
                ]
            ),
        }

        progress = component_build_progress(job)

        self.assertEqual(progress["progress"], 50)
        self.assertEqual(progress["stage"], "W2 · Видео: Шаг вправо")
        self.assertEqual(progress["active"], {"action": "walk_right", "stage": "w2"})

    def test_w2_marker_overrides_stale_w1_progress_event(self):
        job = {
            "status": "running",
            "params": {
                "actions": ["idle", "idle_smile"],
                "rerun_action": "idle_smile",
                "start_step": "w1",
            },
            "log_text": "\n".join(
                [
                    "[PIPE/W1] character_idle_smile",
                    'PROGRESS_JSON: {"stage": "w1", "percent": 100}',
                    'STAGE_JSON: {"stage": "w1", "path": "/tmp/keyframe.png"}',
                    "[PIPE/W2] character_idle_smile",
                    "  enqueued: prompt-id",
                ]
            ),
        }

        progress = component_build_progress(job)

        self.assertEqual(progress["progress"], 34)
        self.assertEqual(progress["stage"], "W2 · Генерируем видео: Idle с улыбкой")
        self.assertEqual(progress["active"], {"action": "idle_smile", "stage": "w2"})


class AdditionalAnimationsUiTests(unittest.TestCase):
    def test_ready_component_exposes_add_animations_dialog(self):
        html = (PROJECT_ROOT / "viewer/static/character-creator.html").read_text(encoding="utf-8")

        self.assertIn('id="addAnimations"', html)
        self.assertIn('id="addAnimationsDialog"', html)
        self.assertIn('id="addAnimationsForm"', html)
        self.assertIn('id="additionalMotions"', html)

    def test_polling_retries_transient_status_request_failures(self):
        script = (PROJECT_ROOT / "viewer/static/character-creator.js").read_text(encoding="utf-8")

        self.assertIn("let consecutivePollFailures = 0", script)
        self.assertIn("if (!isRetryableStatusError(error)) throw error", script)
        self.assertIn("if (consecutivePollFailures >= 120) throw error", script)
        self.assertIn("const retryDelay = Math.min(5000", script)
        self.assertIn("status === 408 || status === 429 || status >= 500", script)

    def test_add_animations_preserves_existing_actions_and_skips_ready_outputs(self):
        script = (PROJECT_ROOT / "viewer/static/character-creator.js").read_text(encoding="utf-8")

        self.assertIn("const actions = [...new Set([...currentPipelineActions, ...selected])]", script)
        self.assertIn('rerun_action: ""', script)
        self.assertIn('start_step: "w1"', script)
        self.assertIn("force: false", script)

    def test_add_animations_marks_existing_actions_and_only_submits_new_choices(self):
        html = (PROJECT_ROOT / "viewer/static/character-creator.html").read_text(encoding="utf-8")
        script = (PROJECT_ROOT / "viewer/static/character-creator.js").read_text(encoding="utf-8")

        self.assertIn('id="createdAnimationsCount"', html)
        self.assertIn('id="selectedAnimationsCount"', html)
        self.assertIn("input.checked = alreadyCreated", script)
        self.assertIn(':checked:not(:disabled)', script)
        self.assertIn("updateAdditionalAnimationSelection()", script)

    def test_add_animations_dialog_has_compact_responsive_styles(self):
        css = (PROJECT_ROOT / "viewer/static/character-creator.css").read_text(encoding="utf-8")

        self.assertIn(".add-animations-dialog", css)
        self.assertIn(".animation-choice.already-created", css)
        self.assertIn(".animation-picker-grid", css)
        self.assertIn("@media (max-width: 560px)", css)

    def test_pipeline_exposes_per_animation_delete_action(self):
        script = (PROJECT_ROOT / "viewer/static/character-creator.js").read_text(encoding="utf-8")
        server = (PROJECT_ROOT / "viewer/server.py").read_text(encoding="utf-8")

        self.assertIn('remove.className = "pipeline-delete"', script)
        self.assertIn('method: "DELETE"', script)
        self.assertIn("/actions/${encodeURIComponent(item.id)}", script)
        self.assertIn("remove_component_action", server)


if __name__ == "__main__":
    unittest.main()
