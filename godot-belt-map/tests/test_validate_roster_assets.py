import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageDraw

import validate_roster_assets as gate


class RosterReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.fixture_home = Path(__file__).resolve().parents[1] / "test-results" / "roster-fixtures"
        self.fixture_home.mkdir(parents=True, exist_ok=True)
        self.folder = tempfile.TemporaryDirectory(prefix="roster-release-test-", dir=self.fixture_home)
        self.root = Path(self.folder.name)
        self.manifests = {}
        for identity in gate.IDS:
            role = self.root / identity
            role.mkdir()
            clips = {}
            for action in gate.REQUIRED + (("cast",) if identity == "serin" else ()):
                (role / action).mkdir()
                frames = []
                for index in range(2):
                    image = Image.new("RGBA", gate.CANVAS)
                    ImageDraw.Draw(image).rectangle((320 + index, 160, 440 + index, 650), fill=(175, 123, 84, 255))
                    image.save(role / action / f"{index}.png")
                    frames.append({"file": f"{action}/{index}.png", "source_frame": index, "duration_ms": 80})
                    if action == "stand" and index == 0:
                        image.save(role / "portrait.png")
                clips[action] = {"frames": frames, "duration_ms": 160, "pivot": [384, 650], "scale": .4,
                                 "source_count": 124, "review_status": "visually_reviewed", "event_ms": 80}
            self.manifests[identity] = {"version": 1, "id": identity, "canvas": [768, 768], "portrait": "portrait.png", "actions": clips}
        self.save()

    def tearDown(self):
        self.assertTrue(self.root.resolve().is_relative_to(self.fixture_home.resolve()))
        self.folder.cleanup()

    def save(self):
        for identity, data in self.manifests.items():
            (self.root / identity / "animation.json").write_text(json.dumps(data), encoding="utf-8")

    def crop_action(self, identity="scout", action="stand", crop=(316, 156, 130, 499)):
        archive = self.root / "original-export"
        clip = self.manifests[identity]["actions"][action]
        for frame in clip["frames"]:
            path = self.root / identity / frame["file"]
            original = archive / identity / frame["file"]
            original.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(path) as source:
                source.save(original)
                x, y, width, height = crop
                cropped = source.crop((x, y, x + width, y + height))
            cropped.save(path)
        (archive / identity / "animation.json").write_text(json.dumps(self.manifests[identity]), encoding="utf-8")
        clip["storage_crop"] = list(crop)
        self.save()
        return archive

    def test_complete_reviewed_set_can_release(self):
        result = gate.validate(self.root)
        self.assertTrue(result["release_ready"], result["errors"])
        self.assertEqual(result["checked_frames"], 42)

    def test_pending_review_never_releases(self):
        self.manifests["serin"]["actions"]["cast"]["review_status"] = "needs_visual_review"
        self.save()
        self.assertFalse(gate.validate(self.root)["ok"])
        relaxed = gate.validate(self.root, require_review=False)
        self.assertTrue(relaxed["ok"], relaxed["errors"])
        self.assertFalse(relaxed["release_ready"])

    def test_bad_timing_and_per_frame_transform_rejected(self):
        action = self.manifests["scout"]["actions"]["attack"]
        action["event_ms"] = 160
        action["frames"][0]["duration_ms"] = True
        action["frames"][1]["pivot"] = [22, 33]
        self.save()
        errors = "\n".join(gate.validate(self.root)["errors"])
        self.assertIn("invalid duration", errors)
        self.assertIn("per-frame transforms", errors)
        self.assertIn("event", errors)

    def test_alpha_crop_and_solid_background_rejected(self):
        Image.new("RGBA", gate.CANVAS, (20, 40, 60, 255)).save(self.root / "boss" / "walk" / "0.png")
        errors = "\n".join(gate.validate(self.root)["errors"])
        self.assertIn("opaque border", errors)
        self.assertIn("transparent background", errors)

    def test_missing_cast_and_parent_path_rejected(self):
        del self.manifests["serin"]["actions"]["cast"]
        self.manifests["caster"]["actions"]["attack"]["frames"][0]["file"] = "../scout/attack/0.png"
        self.save()
        errors = "\n".join(gate.validate(self.root)["errors"])
        self.assertIn("serin/cast: missing", errors)
        self.assertIn("unsafe", errors)

    def test_repeated_still_image_rejected(self):
        first = self.root / "elite" / "stand" / "0.png"
        (first.parent / "1.png").write_bytes(first.read_bytes())
        errors = "\n".join(gate.validate(self.root)["errors"])
        self.assertIn("no authored motion", errors)

    def test_malformed_values_fail_without_crashing(self):
        action = self.manifests["boss"]["actions"]["hurt"]
        action["pivot"] = "not a vector"
        action["duration_ms"] = {"bad": 1}
        action["scale"] = 10**1000
        action["frames"][0]["file"] = "\x00.png"
        action["frames"][1]["source_frame"] = False
        self.save()
        self.assertFalse(gate.validate(self.root)["ok"])

    def test_storage_crop_restores_canvas_and_exact_visible_pixels(self):
        original = gate.validate(self.root)["characters"]["scout"]["actions"]["stand"]["frames"][0]
        archive = self.crop_action()
        # RGB in completely transparent archival pixels must not defeat a lossless visual crop.
        original_path = archive / "scout" / "stand" / "0.png"
        with Image.open(original_path) as source:
            changed = source.copy()
        changed.putpixel((0, 0), (255, 125, 20, 0))
        changed.save(original_path)
        result = gate.validate(self.root, source_root=archive)
        self.assertTrue(result["release_ready"], result["errors"])
        self.assertTrue(result["lossless_storage_verified"])
        self.assertEqual(result["source_checked_frames"], 2)
        frame = result["characters"]["scout"]["actions"]["stand"]["frames"][0]
        self.assertEqual(frame["size"], [768, 768])
        self.assertEqual(frame["stored_size"], [130, 499])
        self.assertEqual(frame["sha256"], original["sha256"])
        self.assertEqual(frame["transparent_fraction"], original["transparent_fraction"])

    def test_storage_crop_requires_four_clear_pixels(self):
        archive = self.crop_action(crop=(320, 160, 122, 491))
        result = gate.validate(self.root, source_root=archive)
        self.assertFalse(result["ok"])
        self.assertIn("four fully transparent", "\n".join(result["errors"]))

    def test_storage_crop_rejects_noninteger_and_out_of_bounds_metadata(self):
        for crop in ([316.0, 156, 130, 499], [True, 156, 130, 499], [-1, 156, 130, 499],
                     [700, 156, 130, 499], [316, 700, 130, 499], [316, 156, 8, 499], None, [0, 1, 2]):
            with self.subTest(crop=crop):
                self.manifests["scout"]["actions"]["stand"]["storage_crop"] = crop
                self.save()
                result = gate.validate(self.root)
                self.assertFalse(result["ok"])
                self.assertIn("storage_crop must be four integers", "\n".join(result["errors"]))

    def test_storage_crop_without_metadata_still_requires_full_canvas(self):
        self.crop_action()
        del self.manifests["scout"]["actions"]["stand"]["storage_crop"]
        self.save()
        self.assertIn("invalid canvas", "\n".join(gate.validate(self.root)["errors"]))

    def test_storage_crop_must_match_png_size_and_never_be_per_frame(self):
        self.crop_action()
        action = self.manifests["scout"]["actions"]["stand"]
        action["storage_crop"][2] += 1
        action["frames"][0]["storage_crop"] = [316, 156, 130, 499]
        self.save()
        errors = "\n".join(gate.validate(self.root)["errors"])
        self.assertIn("invalid canvas", errors)
        self.assertIn("per-frame transforms", errors)

    def test_archival_comparison_detects_detached_weapon_loss(self):
        path = self.root / "scout" / "stand" / "0.png"
        with Image.open(path) as source:
            original = source.copy()
        ImageDraw.Draw(original).rectangle((650, 650, 655, 655), fill=(200, 180, 100, 255))
        original.save(path)
        archive = self.crop_action()
        structural = gate.validate(self.root)
        self.assertTrue(structural["ok"], structural["errors"])
        self.assertFalse(structural["lossless_storage_verified"])
        self.assertFalse(structural["release_ready"])
        verified = gate.validate(self.root, source_root=archive)
        self.assertFalse(verified["ok"])
        self.assertIn("pixels lost or moved", "\n".join(verified["errors"]))

    def test_archival_comparison_detects_rgb_change_without_alpha_change(self):
        archive = self.crop_action()
        path = self.root / "scout" / "stand" / "0.png"
        with Image.open(path) as source:
            edited = source.copy()
        edited.putpixel((10, 10), (0, 0, 255, 255))
        edited.save(path)
        result = gate.validate(self.root, source_root=archive)
        self.assertFalse(result["ok"])
        self.assertIn("pixels lost or moved", "\n".join(result["errors"]))

    def test_optional_emitter_rejects_malformed_coordinates(self):
        for emitter in ([float("nan"), 100], [float("inf"), 100], ["40", 100], [769, 10], [10, -1],
                        [True, 100], [10], [10, 20, 30], None):
            with self.subTest(emitter=emitter):
                self.manifests["serin"]["actions"]["attack"]["emitter"] = emitter
                self.save()
                result = gate.validate(self.root, ids=("serin",))
                self.assertFalse(result["ok"])
                self.assertIn("emitter must contain two finite", "\n".join(result["errors"]))

    def test_archival_emitter_is_preserved_not_shifted_to_crop_coordinates(self):
        self.manifests["serin"]["actions"]["attack"]["emitter"] = [422.5, 280]
        archive = self.crop_action(identity="serin", action="attack")
        correct = gate.validate(self.root, source_root=archive)
        self.assertTrue(correct["release_ready"], correct["errors"])
        self.manifests["serin"]["actions"]["attack"]["emitter"] = [106.5, 124]
        self.save()
        shifted = gate.validate(self.root, source_root=archive)
        self.assertFalse(shifted["ok"])
        self.assertIn("emitter metadata differs", "\n".join(shifted["errors"]))
        del self.manifests["serin"]["actions"]["attack"]["emitter"]
        self.save()
        removed = gate.validate(self.root, source_root=archive)
        self.assertFalse(removed["ok"])
        self.assertIn("emitter metadata differs", "\n".join(removed["errors"]))

    def test_archival_clip_preserves_fixed_pivot(self):
        archive = self.crop_action()
        self.manifests["scout"]["actions"]["stand"]["pivot"][0] += 1
        self.save()
        result = gate.validate(self.root, source_root=archive)
        self.assertFalse(result["release_ready"])
        errors = "\n".join(result["errors"])
        self.assertIn("action metadata differs", errors)
        self.assertIn("pivot", errors)

    def test_archival_clip_preserves_frame_timing_even_with_valid_total(self):
        archive = self.crop_action()
        frames = self.manifests["scout"]["actions"]["stand"]["frames"]
        frames[0]["duration_ms"] = 70
        frames[1]["duration_ms"] = 90
        self.save()
        result = gate.validate(self.root, source_root=archive)
        self.assertFalse(result["release_ready"])
        errors = "\n".join(result["errors"])
        self.assertIn("action metadata differs", errors)
        self.assertIn("frames", errors)
        self.assertNotIn("total duration differs", errors)


if __name__ == "__main__":
    unittest.main()
