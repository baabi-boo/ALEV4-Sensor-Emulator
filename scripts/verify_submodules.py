#!/usr/bin/env python3
"""Verify declared Git pins, optionally requiring clean matching checkouts.

The default check needs no initialized submodules. ``--require-checkout`` is
the numerical-validation gate: each dependency must resolve to its own Git
worktree, use the declared origin, match the committed gitlink, and be clean.
No network access or repository mutation is performed by this script.
"""
from __future__ import annotations

import argparse
import configparser
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "third_party/isetcam": "https://github.com/ISET/isetcam.git",
    "third_party/isethdrsensor": "https://github.com/ISET/isethdrsensor.git",
}


class VerificationError(RuntimeError):
    """A dependency does not satisfy the declared reproducibility contract."""


def _git(root: Path, *arguments: str, label: str) -> str:
    """Run a local Git read without echoing output that may contain a URL secret."""
    environment = os.environ.copy()
    # A caller's alternate Git directory/index must not redirect these reads.
    for variable in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
        environment.pop(variable, None)
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *arguments],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            check=False,
        )
    except OSError as error:
        raise VerificationError(f"Cannot run Git while inspecting {label}.") from error
    if result.returncode != 0:
        # Neither stdout nor stderr is included: config/errors can contain an
        # authenticated origin URL. The operation and exit code are sufficient.
        raise VerificationError(
            f"Cannot inspect {label} (Git exit {result.returncode})."
        )
    return result.stdout


def _verify_checkout(root: Path, path: str, expected_sha: str, expected_url: str) -> None:
    checkout = root / path
    marker = checkout / ".git"
    if not checkout.is_dir() or not (marker.is_file() or marker.is_dir()):
        raise VerificationError(f"Uninitialized dependency checkout: {path}.")
    top_level = _git(
        checkout, "rev-parse", "--show-toplevel", label=f"worktree root for {path}"
    ).strip()
    if Path(top_level).resolve() != checkout.resolve():
        raise VerificationError(f"Dependency inherits another Git worktree: {path}.")
    observed_sha = _git(
        checkout, "rev-parse", "--verify", "HEAD", label=f"checkout HEAD for {path}"
    ).strip()
    if observed_sha != expected_sha:
        raise VerificationError(f"Checkout HEAD differs from the committed gitlink: {path}.")
    origin = _git(
        checkout,
        "config",
        "--local",
        "--get",
        "remote.origin.url",
        label=f"origin URL for {path}",
    ).strip()
    if origin != expected_url:
        raise VerificationError(f"Checkout origin differs from the declared dependency: {path}.")
    status = _git(
        checkout,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        "--ignore-submodules=none",
        label=f"checkout cleanliness for {path}",
    )
    if status:
        raise VerificationError(f"Dependency checkout has tracked or untracked changes: {path}.")


def verify_submodules(root: Path = ROOT, *, require_checkout: bool = False) -> dict[str, str]:
    """Return dependency paths and committed SHAs, or raise VerificationError.

    ``root`` permits offline fixture tests. Ignored files are permitted in the
    checkout gate; tracked modifications and all non-ignored untracked files
    are rejected. Origin mismatches never include the observed URL in errors.
    """
    root = Path(root).resolve()
    cfg = configparser.ConfigParser(interpolation=None)
    try:
        with (root / ".gitmodules").open(encoding="utf-8") as source:
            cfg.read_file(source)
    except (OSError, UnicodeError, configparser.Error) as error:
        raise VerificationError("Cannot read a valid .gitmodules declaration.") from error
    pins: dict[str, str] = {}
    for path, url in EXPECTED.items():
        section = f'submodule "{path}"'
        if not cfg.has_section(section):
            raise VerificationError(f"Missing .gitmodules section: {section}")
        if cfg.get(section, "path", fallback=None) != path or cfg.get(section, "url", fallback=None) != url:
            raise VerificationError(f"Unexpected submodule config for {path}")
        record = _git(root, "ls-tree", "-z", "HEAD", "--", path, label=f"gitlink for {path}")
        match = re.fullmatch(r"160000 commit ([a-f0-9]{40})\t" + re.escape(path) + "\0", record)
        if match is None:
            raise VerificationError(f"{path} is not a pinned Git submodule.")
        pins[path] = match.group(1)
        if require_checkout:
            _verify_checkout(root, path, pins[path], url)
    return pins


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-checkout", action="store_true", help="Require clean initialized checkouts at committed pins.")
    parser.add_argument("--root", type=Path, default=ROOT, help="Repository root (defaults to this script's repository).")
    arguments = parser.parse_args(argv)
    try:
        pins = verify_submodules(arguments.root, require_checkout=arguments.require_checkout)
    except VerificationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    for path, sha in pins.items():
        print(f"OK {path} -> {sha}")
    qualifier = " with clean matching checkouts" if arguments.require_checkout else ""
    print(f"PASS: both dependencies are pinned, declared Git submodules{qualifier}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
