"""Verify roguelike_mode ZIP against a copy of an installed .love and imported caches.

No game windows are opened. User saves and options are never loaded or written.
Temporary staging directories are automatically deleted on exit.
"""
import argparse
from contextlib import nullcontext
import os
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile
import zlib

sys.dont_write_bytecode = True
TOOLS_PY = Path(__file__).resolve().parents[3] / ".tools" / "python"
if TOOLS_PY.is_dir() and str(TOOLS_PY) not in sys.path:
    sys.path.insert(0, str(TOOLS_PY))

from lupa.luajit21 import LuaRuntime


def verify(stage, version, suite):
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    root = stage.resolve()

    def path(value):
        target = (root / value.decode()).resolve()
        if not target.is_relative_to(root):
            raise ValueError("Test filesystem cannot escape staging directory")
        return target

    def read(value):
        target = path(value)
        return target.read_bytes() if target.is_file() else None

    def info(value):
        target = path(value)
        if target.is_file():
            return lua.table_from({b"type": b"file"})
        if target.is_dir():
            return lua.table_from({b"type": b"directory"})

    def listing(value):
        target = path(value)
        return lua.table_from(sorted(p.name.encode() for p in target.iterdir())) if target.is_dir() else lua.table()

    g = lua.globals()
    g.TEST_VERSION = version.encode()
    g.CACHE_ROOT = (root / version / "data/generated/gba").as_posix().encode()
    g.fs_read, g.fs_info, g.fs_list = read, info, listing
    g.inflate, g.deflate = zlib.decompress, zlib.compress
    previous = Path.cwd()
    try:
        os.chdir(root)
        lua.execute(suite.read_bytes())
    finally:
        os.chdir(previous)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installation", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--stage", type=Path, help="Reuse an existing test stage")
    args = parser.parse_args()
    ctx = nullcontext(args.stage) if args.stage else tempfile.TemporaryDirectory(prefix="rl-installed-")
    with ctx as tmp_stage:
        stage = Path(tmp_stage).resolve()
        print(f"Installed-game test stage: {stage}", flush=True)
        if not args.stage:
            with zipfile.ZipFile(args.installation / "updates/gen1recomp-0.3.96.love") as packed:
                packed.extractall(stage)
            for version in ("firered", "emerald"):
                shutil.copytree(args.installation / version / "data", stage / version / "data")
        with zipfile.ZipFile(args.archive) as packed:
            expected = {f"roguelike_mode/{name}" for name in ("manifest.json", "main.lua", "README.md", "LICENSE")}
            if set(packed.namelist()) != expected:
                raise ValueError("Unexpected mod archive contents")
            packed.extractall(stage / "mods")
        suite = Path(__file__).resolve().parents[1] / "tests/installed.lua"
        for version in ("firered", "emerald"):
            verify(stage, version, suite)
