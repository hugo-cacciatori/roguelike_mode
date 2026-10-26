"""Run the headless suites against the engine checkout and the player's imports.

Imports are read, never written: the Lua side gets read-only file access
confined to --imports. No game window is opened. Composite renders go to
tests/out/ (git-ignored: they contain ROM-derived art).
"""
import argparse
import importlib.util
import os
from pathlib import Path
import struct
import sys
import zlib

sys.dont_write_bytecode = True
TOOLS_PY = Path(__file__).resolve().parents[3] / ".tools" / "python"
if TOOLS_PY.is_dir() and str(TOOLS_PY) not in sys.path:
    sys.path.insert(0, str(TOOLS_PY))

from lupa.luajit21 import LuaRuntime

MOD_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMPORTS = Path(os.environ.get("APPDATA", "")) / "pokemon-love2d"
SUITES = ("unit", "integration", "takeover", "wild", "town")
SCENARIOS = {"takeover": ("adventure", "fresh")}


def shipped_files(mod):
    """{relative path: bytes} for exactly the files tools/package.py ships."""
    spec = importlib.util.spec_from_file_location("rl_package", MOD_ROOT / "tools" / "package.py")
    package = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(package)
    package.ROOT = mod
    return {name: (mod / name).read_bytes() for name in package.runtime_files()}


def runtime(engine, mod, imports, out_dir):
    imports = imports.resolve()

    def target(rel):
        path = (imports / rel.decode().replace("\\", "/").lstrip("/")).resolve()
        if not path.is_relative_to(imports):
            raise ValueError("import access outside the imports root")
        return path

    def import_read(rel):
        path = target(rel)
        return path.read_bytes() if path.is_file() else None

    def import_info(rel):
        path = target(rel)
        if path.is_file():
            return b"file", path.stat().st_size
        if path.is_dir():
            return b"directory", None
        return None, None

    def write_png(name, w, h, rgba):
        out_dir.mkdir(parents=True, exist_ok=True)
        dest = (out_dir / name.decode()).resolve()
        if not dest.is_relative_to(out_dir.resolve()):
            raise ValueError("render output outside tests/out")
        data = bytes(rgba[i] for i in range(1, w * h * 4 + 1))
        rows = b"".join(b"\x00" + data[y * w * 4:(y + 1) * w * 4] for y in range(h))

        def chunk(tag, body):
            head = struct.pack(">I", len(body)) + tag + body
            return head + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

        dest.write_bytes(b"\x89PNG\r\n\x1a\n"
                         + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))

    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    g = lua.globals()
    g.MOD_ROOT = mod.as_posix().encode()
    # The loader reads the mod from memory: the shipped files only, and no
    # Windows directory probes (the SDK's rename-self probe fails at random
    # while another process holds the folder).
    g.MOD_FILES = lua.table_from({f"mods/roguelike_mode/{k}".encode(): v
                                  for k, v in shipped_files(mod).items()})
    g.IMPORTS_ROOT = imports.as_posix().encode()
    g.import_read, g.import_info, g.write_png = import_read, import_info, write_png
    g.inflate, g.deflate = zlib.decompress, zlib.compress
    return lua


def run(engine, mod, imports, suites=SUITES):
    previous = Path.cwd()
    try:
        os.chdir(engine)
        for name in suites:
            for scenario in SCENARIOS.get(name, (None,)):
                lua = runtime(engine, mod, imports, MOD_ROOT / "tests" / "out")
                if scenario:
                    lua.globals().SCENARIO = scenario.encode()
                lua.execute((MOD_ROOT / "tests" / f"{name}.lua").read_bytes())
    finally:
        os.chdir(previous)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--mod", type=Path, default=MOD_ROOT)
    parser.add_argument("--imports", type=Path, default=DEFAULT_IMPORTS)
    parser.add_argument("--suite", choices=SUITES, action="append")
    parser.add_argument("--script", type=Path, help="run one exploratory Lua script with the harness globals")
    args = parser.parse_args()
    if args.script:
        script = args.script.resolve()
        engine = args.engine.resolve()
        previous = Path.cwd()
        try:
            os.chdir(engine)
            runtime(engine, args.mod.resolve(), args.imports, script.parent / "out").execute(script.read_bytes())
        finally:
            os.chdir(previous)
    else:
        run(args.engine.resolve(), args.mod.resolve(), args.imports, args.suite or SUITES)
