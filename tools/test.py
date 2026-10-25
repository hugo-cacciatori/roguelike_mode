"""Run the native-loader integration suite without opening a game window."""
import argparse
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
TOOLS_PY = Path(__file__).resolve().parents[3] / ".tools" / "python"
if TOOLS_PY.is_dir() and str(TOOLS_PY) not in sys.path:
    sys.path.insert(0, str(TOOLS_PY))

from lupa.luajit21 import LuaRuntime


def run(engine, mod):
    suite = Path(__file__).resolve().parents[1] / "tests" / "integration.lua"
    previous = Path.cwd()
    try:
        os.chdir(engine)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().MOD_PATH = os.path.relpath(mod, engine).replace("\\", "/")
        lua.execute(suite.read_text(encoding="utf-8"))
    finally:
        os.chdir(previous)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--mod", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    run(args.engine.resolve(), args.mod.resolve())
