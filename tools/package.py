"""Build a self-contained mod archive from an explicit runtime-file allowlist."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
MOD_ID = "roguelike_mode"
TOP_FILES = ("manifest.json", "main.lua", "README.md", "LICENSE")
MODULE_DIRS = ("lib", "data")


def runtime_files():
    """The shipped files: top-level files plus every Lua module in lib/ and data/."""
    files = list(TOP_FILES)
    for folder in MODULE_DIRS:
        files += sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / folder).glob("*.lua"))
    return files


def build():
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    version = manifest["version"]
    folder = "dev" if "-dev" in version else f"v{version}"
    output = ROOT / "dist" / folder
    output.mkdir(parents=True, exist_ok=True)
    unpacked = output / MOD_ID
    unpacked.mkdir(exist_ok=True)
    archive = output / f"{MOD_ID}-{version}.zip"
    # Fixed member timestamps make repeated packages byte-identical.
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for name in runtime_files():
            (unpacked / name).parent.mkdir(parents=True, exist_ok=True)
            (unpacked / name).write_bytes((ROOT / name).read_bytes())
            info = zipfile.ZipInfo(f"{MOD_ID}/{name}", (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, (ROOT / name).read_bytes())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n", encoding="ascii")
    print(archive)
    return archive


if __name__ == "__main__":
    build()
