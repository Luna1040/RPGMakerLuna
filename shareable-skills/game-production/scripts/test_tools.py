"""Offline tests for file and timing boundaries. Run with Python + Pillow."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pack_frames import pack
from PIL import Image


class PackTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.im = Image.new('RGBA', (8, 8))
        self.im.putpixel((4, 4), (220, 180, 50, 255))
        self.im.save(self.root / 'frame.png')
        self.spec = {'canvas': [8, 8], 'pivot': [4, 7], 'scale': 1,
                     'frames': [{'file': 'frame.png', 'source_frame': 18, 'duration_ms': 50}], 'event_ms': 20}

    def tearDown(self):
        self.im.close()
        self.tmp.cleanup()

    def run_pack(self):
        specfile = self.root / 'selection.json'
        specfile.write_text(json.dumps(self.spec), encoding='utf-8')
        return pack(self.root, specfile, self.root / 'export')

    def test_preserves_source_and_timing(self):
        result = self.run_pack()
        self.assertEqual(result['frames'][0]['source_frame'], 18)
        self.assertEqual(result['duration_ms'], 50)
        self.assertTrue((self.root / 'export/review.webp').exists())

    def test_rejects_clipped_frame(self):
        self.im.putpixel((0, 4), (255, 255, 255, 255))
        self.im.save(self.root / 'frame.png')
        with self.assertRaisesRegex(AssertionError, 'Opaque canvas edge'):
            self.run_pack()

    def test_rejects_event_outside_action(self):
        self.spec['event_ms'] = 50
        with self.assertRaisesRegex(AssertionError, 'Event outside'):
            self.run_pack()

    def test_rejects_traversal(self):
        self.spec['frames'][0]['file'] = '../outside.png'
        with self.assertRaisesRegex(AssertionError, 'Unsafe frame path'):
            self.run_pack()


if __name__ == '__main__':
    unittest.main()
