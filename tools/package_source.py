#!/usr/bin/env python3
"""Create a deterministic source ZIP containing only new portable source files.

This intentionally does not use `git archive` or a recursive workspace archive:
original game data, extracted resources, and decompiler evidence must not enter
the open source distribution. The vendored LGPL decoder source and notices are
explicitly included so native packages can be modified and relinked.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = ("CMakeLists.txt", "README.md", "LICENSE", ".gitignore", ".clang-format")
DIRECTORIES = {
    "src": {".cpp", ".hpp", ".h", ".c"},
    "tests": {".cpp", ".hpp", ".h", ".py"},
    "docs": {".md"},
    "tools": {".py", ".sh", ".ps1"},
    ".github/workflows": {".yml", ".yaml"},
}
SMACKER_FILES = (
    "smacker.c", "smacker.h", "smk_malloc.h", "COPYING", "README", "INSTALL",
    "Makefile.am", "configure.ac", "driver.c", "smk2avi.c", "UPSTREAM.md",
)
VENDORED_FILES = (
    *("third_party/libsmacker/" + name for name in SMACKER_FILES),
    "third_party/liberation/LiberationSerif-Regular.ttf",
    "third_party/liberation/font_data.h",
    "third_party/liberation/LICENSE",
    "third_party/liberation/UPSTREAM.md",
    "third_party/stb/stb_truetype.h",
    "third_party/stb/LICENSE",
    "third_party/stb/UPSTREAM.md",
)
# --miyoo: the Miyoo Mini build and packaging files, so the device binary can be
# rebuilt and relinked too. Packaging/ holds no game data (only scripts, docs
# and the original box art).
MIYOO_ROOT_FILES = ("README-MIYOO.md",)
MIYOO_DIRECTORIES = {
    "Packaging/miyoo_mini": {".sh", ".cmake", ".py", ".txt", ".port", ".png", ""},
    # The CMake-script tests that CMakeLists.txt registers.
    "tests": DIRECTORIES["tests"] | {".cmake"},
}


def source_files(miyoo: bool = False) -> list[Path]:
    root_files = ROOT_FILES + (MIYOO_ROOT_FILES if miyoo else ())
    directories = {**DIRECTORIES, **(MIYOO_DIRECTORIES if miyoo else {})}
    selected = [ROOT / name for name in root_files if (ROOT / name).is_file()]
    selected.extend(ROOT / name for name in VENDORED_FILES)
    missing = [str(path.relative_to(ROOT)) for path in selected if not path.is_file()]
    if missing:
        raise SystemExit("Missing distribution files: " + ", ".join(missing))
    for folder, extensions in directories.items():
        directory = ROOT / folder
        if directory.exists():
            selected.extend(
                path for path in directory.rglob("*")
                if path.is_file() and not path.is_symlink()
                and path.suffix in extensions
                and "__pycache__" not in path.parts
            )
    return sorted(selected, key=lambda path: path.relative_to(ROOT).as_posix())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/OpenA2-0.4.0-source.zip")
    parser.add_argument("--miyoo", action="store_true",
                        help="also include the Miyoo Mini build and packaging files")
    args = parser.parse_args()
    files = source_files(args.miyoo)
    required = {"CMakeLists.txt", "README.md", "LICENSE", "src/assets.hpp", "src/types.hpp"}
    included = {p.relative_to(ROOT).as_posix() for p in files}
    if not required <= included:
        raise SystemExit("Missing required source files: " + ", ".join(sorted(required - included)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo("OpenA2/" + path.relative_to(ROOT).as_posix(), (2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
    print(f"{args.output}: {len(files)} files, SHA-256 {digest}")


if __name__ == "__main__":
    main()
