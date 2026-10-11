"""CPU invariants for lossless runtime packing; fixtures are synthetic pixels."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import sys

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pack_roster_runtime import pack_character


class PackingTests(unittest.TestCase):
    def setUp(self):
        self.test_root = Path(__file__).resolve().parent / "test-results"
        self.test_root.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="pack-fixture-", dir=self.test_root)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.output = self.root / "runtime"
        self.character = self.source / "serin"
        (self.character / "stand").mkdir(parents=True)
        frames = []
        for index, bounds in enumerate([(100, 120, 301, 641), (90, 119, 309, 640)]):
            image = Image.new("RGBA", (768, 768), (255, 0, 255, 0))
            image.paste((70, 160, 230, 255), bounds)
            image.putpixel((350, 200 + index), (240, 200, 110, 1))
            relative = f"stand/{index:03}.png"
            image.save(self.character / relative)
            frames.append({"file": relative, "source_frame": 13 + index, "duration_ms": 125})
        Image.new("RGBA", (768, 768), (0, 0, 0, 0)).save(self.character / "portrait.png")
        self.manifest = {"version": 1, "id": "serin", "name": "Serin", "canvas": [768, 768], "portrait": "portrait.png", "actions": {
            "stand": {"frames": frames, "duration_ms": 250, "pivot": [393, 642], "scale": 0.486, "review_status": "visually_reviewed"}}}
        self.write_manifest()

    def tearDown(self):
        self.assertTrue(self.root.resolve().is_relative_to(self.test_root.resolve()))
        self.temporary.cleanup()

    def write_manifest(self):
        (self.character / "animation.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def pack(self):
        return pack_character("serin", self.source, self.output)

    def test_exact_visible_pixels_and_virtual_positions(self):
        hashes = {p.relative_to(self.character): hashlib.sha256(p.read_bytes()).hexdigest() for p in self.character.rglob("*") if p.is_file()}
        report = self.pack()
        packed = json.loads((self.output / "serin" / "animation.json").read_text(encoding="utf-8"))
        clip = packed["actions"]["stand"]
        crop = clip.pop("storage_crop")
        self.assertEqual(clip, self.manifest["actions"]["stand"])
        self.assertEqual(crop, [86, 115, 269, 530])
        self.assertEqual(packed["canvas"], [768, 768])
        for frame in clip["frames"]:
            stored = Image.open(self.output / "serin" / frame["file"]).convert("RGBA")
            self.assertEqual(stored.size, tuple(crop[2:]))
            self.assertIsNone(stored.getchannel("A").crop((0, 0, stored.width, 4)).getbbox())
            rebuilt = Image.new("RGBA", (768, 768))
            rebuilt.paste(stored, tuple(crop[:2]))
            source = Image.open(self.character / frame["file"]).convert("RGBA")
            self.assertIsNone(ImageChops.difference(source.getchannel("A"), rebuilt.getchannel("A")).getbbox())
            for y in range(768):
                for x in range(768):
                    if source.getpixel((x, y))[3]:
                        self.assertEqual(source.getpixel((x, y)), rebuilt.getpixel((x, y)))
        self.assertGreater(report["saved_rgba_bytes"], 0)
        for relative, expected in hashes.items():
            self.assertEqual(hashlib.sha256((self.character / relative).read_bytes()).hexdigest(), expected)

    def test_repeated_pack_reuses_verified_frames(self):
        self.pack()
        frame = self.output / "serin" / "stand" / "000.png"
        timestamp = frame.stat().st_mtime_ns
        report = self.pack()
        self.assertTrue(report["actions"]["stand"]["reused"])
        self.assertEqual(frame.stat().st_mtime_ns, timestamp)

    def test_external_overwrite_invalidates_cache(self):
        self.pack()
        frame = self.output / "serin" / "stand" / "000.png"
        frame.write_bytes((self.character / "stand" / "000.png").read_bytes())
        self.assertFalse(self.pack()["actions"]["stand"]["reused"])
        with Image.open(frame) as restored:
            self.assertNotEqual(restored.size, (768, 768))

    def test_source_edge_alpha_rejects_instead_of_truncating(self):
        frame = self.character / "stand" / "000.png"
        image = Image.open(frame).convert("RGBA")
        image.putpixel((0, 12), (255, 255, 255, 1))
        image.save(frame)
        with self.assertRaisesRegex(ValueError, "source edge"):
            self.pack()
        self.assertFalse((self.output / "serin" / "animation.json").exists())

    def test_unreviewed_actions_are_not_published(self):
        self.manifest["actions"]["stand"]["review_status"] = "needs_visual_review"
        self.write_manifest()
        report = self.pack()
        self.assertEqual(report["actions"], {})
        self.assertEqual(report["skipped_actions"], ["stand"])

    def test_original_directory_cannot_be_output(self):
        with self.assertRaisesRegex(ValueError, "separate directories"):
            pack_character("serin", self.source, self.source)

    def test_path_traversal_rejects(self):
        self.manifest["actions"]["stand"]["frames"][0]["file"] = "../../outside.png"
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "action directory|escapes"):
            self.pack()

    def test_later_invalid_action_does_not_partially_publish_earlier_actions(self):
        (self.character / "hurt").mkdir()
        image = Image.new("RGBA", (768, 768))
        image.putpixel((0, 1), (255, 255, 255, 255))
        image.save(self.character / "hurt" / "000.png")
        self.manifest["actions"]["hurt"] = {"frames": [{"file": "hurt/000.png", "duration_ms": 100}], "review_status": "visually_reviewed"}
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "source edge"):
            self.pack()
        self.assertFalse(self.output.exists())

    def test_dry_run_writes_nothing(self):
        result = pack_character("serin", self.source, self.output, dry_run=True)
        self.assertGreater(result["saved_rgba_bytes"], 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
