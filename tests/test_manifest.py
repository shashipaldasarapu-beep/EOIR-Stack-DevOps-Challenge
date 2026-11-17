import hashlib
import json
import re
import unittest
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
MODEL_PATH = BASE / "models" / "eo_detector_fp16.engine"
MANIFEST_PATH = BASE / "models" / "manifest.json"


class TestModelManifest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        with MANIFEST_PATH.open("r", encoding="utf-8") as file:
            cls.manifest = json.load(file)

    def test_engine_file_exists(self):
        self.assertTrue(MODEL_PATH.is_file())

    def test_required_manifest_fields(self):
        required = [
            "model_name",
            "version",
            "target_arch",
            "input_resolution",
            "precision",
            "sha256"
        ]

        for field in required:
            with self.subTest(field=field):
                self.assertIn(field, self.manifest)

    def test_checksum_format(self):
        checksum = self.manifest["sha256"]
        self.assertRegex(checksum, r"^[a-fA-F0-9]{64}$")

    def test_engine_checksum_matches_manifest(self):
        actual = hashlib.sha256(MODEL_PATH.read_bytes()).hexdigest()
        expected = self.manifest["sha256"].lower()

        self.assertEqual(
            expected,
            actual,
            "Engine SHA256 does not match models/manifest.json"
        )

    def test_model_metadata(self):
        self.assertEqual(self.manifest["version"], "1.4.2")
        self.assertEqual(self.manifest["precision"], "FP16")
        self.assertEqual(self.manifest["input_resolution"], [1920, 1080])


if __name__ == "__main__":
    unittest.main()
