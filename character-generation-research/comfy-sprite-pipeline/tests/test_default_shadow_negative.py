import unittest
from pathlib import Path

from drivers.prompt_defaults import DEFAULT_SHADOW_NEGATIVE, merge_negative_prompts


ROOT = Path(__file__).resolve().parents[1]


class DefaultShadowNegativeTests(unittest.TestCase):
    def test_default_shadow_ban_covers_common_shadow_artifacts(self):
        for phrase in (
            "cast shadow",
            "drop shadow",
            "ground shadow",
            "contact shadow",
            "floor shadow",
            "shading below feet",
            "dark oval",
        ):
            self.assertIn(phrase, DEFAULT_SHADOW_NEGATIVE)

    def test_pipeline_applies_shadow_ban_to_w1_and_w2_defaults(self):
        source = (ROOT / "drivers/run_quick_sprite_pipeline.py").read_text(encoding="utf-8")

        self.assertIn("W1_NEGATIVE = merge_negative_prompts(", source)
        self.assertIn("W2_NEGATIVE = merge_negative_prompts(", source)
        self.assertIn("merge_negative_prompts(default_negative, negative_prompt)", source)

    def test_custom_negative_prompt_cannot_replace_default_shadow_ban(self):
        merged = merge_negative_prompts(DEFAULT_SHADOW_NEGATIVE, "custom unwanted artifact")

        self.assertIn(DEFAULT_SHADOW_NEGATIVE, merged)
        self.assertIn("custom unwanted artifact", merged)


if __name__ == "__main__":
    unittest.main()
