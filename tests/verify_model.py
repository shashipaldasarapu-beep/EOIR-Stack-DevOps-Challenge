import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
model = root / "models" / "eo_detector_fp16.engine"
manifest_path = root / "models" / "manifest.json"

if not model.is_file():
    raise SystemExit("ERROR: Model artifact is missing")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
expected = manifest.get("sha256", "")

if not isinstance(expected, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
    raise SystemExit("ERROR: Invalid SHA256 in manifest")

actual = hashlib.sha256(model.read_bytes()).hexdigest()

print("Expected SHA256:", expected)
print("Actual SHA256:  ", actual)

if actual.lower() != expected.lower():
    raise SystemExit("ERROR: Model checksum mismatch")

print("Model checksum verification PASSED")
