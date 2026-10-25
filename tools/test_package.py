"""Check the packaged mod in an isolated, external headless engine fixture.

The temporary fixture is deleted automatically on exit.
"""
import argparse
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
from test import run

FILES = ("manifest.json", "main.lua", "README.md", "LICENSE")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    args = parser.parse_args()
    engine, archive = args.engine.resolve(), args.archive.resolve()
    with tempfile.TemporaryDirectory(prefix="rl-check-") as tmp:
        stage = Path(tmp)
        print(f"External fixture: {stage}", flush=True)
        for name in ("src", "tests", "data"):
            shutil.copytree(engine / name, stage / name)
        with zipfile.ZipFile(archive) as bundle:
            if set(bundle.namelist()) != {f"roguelike_mode/{n}" for n in FILES}:
                raise ValueError("Archive contains missing or unexpected files")
            bundle.extractall(stage / "mods")
        run(stage, stage / "mods" / "roguelike_mode")
