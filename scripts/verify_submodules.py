#!/usr/bin/env python3
"""Check that research dependencies are real Git submodules, not copies."""
from __future__ import annotations

import configparser
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "third_party/isetcam": "https://github.com/ISET/isetcam.git",
    "third_party/isethdrsensor": "https://github.com/ISET/isethdrsensor.git",
}


def main() -> None:
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(ROOT / ".gitmodules", encoding="utf-8")
    for path, url in EXPECTED.items():
        section = f'submodule "{path}"'
        if not cfg.has_section(section):
            raise AssertionError(f"Missing .gitmodules section: {section}")
        if cfg.get(section, "path") != path or cfg.get(section, "url") != url:
            raise AssertionError(f"Unexpected submodule config for {path}")
        record = subprocess.check_output(
            ["git", "ls-tree", "HEAD", "--", path],
            cwd=ROOT,
            text=True,
        ).strip()
        match = re.fullmatch(r"160000 commit ([a-f0-9]{40})\t(.+)", record)
        if not match or match.group(2) != path:
            raise AssertionError(f"{path} is not a pinned Git submodule: {record!r}")
        print(f"OK {path} -> {match.group(1)}")
    print("PASS: both dependencies are pinned, declared Git submodules")


if __name__ == "__main__":
    main()
