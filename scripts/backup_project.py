#!/usr/bin/env python3
"""
Create a timestamped zip backup of this project and save it to D:\\مشاريع.

Excludes heavy / generated folders such as node_modules, .git, build, and dist.

Usage:
  python scripts/backup_project.py
  python scripts/backup_project.py --source "D:\\almenupro project"
  python scripts/backup_project.py --dest "D:\\مشاريع"
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
import zipfile
from pathlib import Path

DEFAULT_DEST = Path(r"D:\مشاريع")

# Directory / file names skipped anywhere in the tree.
EXCLUDE_NAMES = {
    ".git",
    ".svn",
    ".hg",
    "node_modules",
    "build",
    "dist",
    ".dart_tool",
    ".vercel",
    ".pub-cache",
    ".gradle",
    ".idea",
    ".vscode",
    "coverage",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".tox",
    ".venv",
    "venv",
    "env",
    ".env.local",
    "Pods",
    "DerivedData",
    ".firebase",
    "xcuserdata",
}

# Path suffixes that should never be archived.
EXCLUDE_SUFFIXES = {
    ".tmp",
    ".log",
    ".pyc",
    ".pyo",
    ".DS_Store",
}


def project_root_from_script() -> Path:
    """scripts/backup_project.py -> project root."""
    return Path(__file__).resolve().parent.parent


def should_skip(path: Path, root: Path) -> bool:
    try:
        relative = path.relative_to(root)
    except ValueError:
        return True

    for part in relative.parts:
        if part in EXCLUDE_NAMES:
            return True
        if part.endswith(".egg-info"):
            return True

    name = path.name
    if name in EXCLUDE_NAMES:
        return True
    if any(name.endswith(suffix) for suffix in EXCLUDE_SUFFIXES):
        return True
    return False


def iter_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)

        # Prune excluded directories in-place so os.walk does not descend into them.
        kept = []
        for name in dirnames:
            candidate = current / name
            if should_skip(candidate, root):
                continue
            kept.append(name)
        dirnames[:] = kept

        for name in filenames:
            file_path = current / name
            if should_skip(file_path, root):
                continue
            if not file_path.is_file():
                continue
            yield file_path


def make_archive_name(root: Path, when: dt.datetime) -> str:
    stamp = when.strftime("%Y%m%d_%H%M%S")
    safe_name = "".join(
        ch if ch.isalnum() or ch in ("-", "_") else "_"
        for ch in root.name.strip()
    ).strip("_") or "project"
    return f"{safe_name}_backup_{stamp}.zip"


def create_backup(source: Path, dest_dir: Path) -> Path:
    source = source.resolve()
    if not source.is_dir():
        raise FileNotFoundError(f"Source project not found: {source}")

    dest_dir.mkdir(parents=True, exist_ok=True)
    archive_path = dest_dir / make_archive_name(source, dt.datetime.now())

    file_count = 0
    with zipfile.ZipFile(
        archive_path,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=6,
    ) as zf:
        for file_path in iter_files(source):
            arcname = file_path.relative_to(source).as_posix()
            zf.write(file_path, arcname)
            file_count += 1

    size_mb = archive_path.stat().st_size / (1024 * 1024)
    print(f"Source : {source}")
    print(f"Files  : {file_count}")
    print(f"Output : {archive_path}")
    print(f"Size   : {size_mb:.2f} MB")
    return archive_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Zip the project (excluding heavy folders) into D:\\مشاريع",
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=project_root_from_script(),
        help="Project directory to back up (default: repository root)",
    )
    parser.add_argument(
        "--dest",
        type=Path,
        default=DEFAULT_DEST,
        help=rf"Destination folder (default: {DEFAULT_DEST})",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        create_backup(args.source, args.dest)
    except Exception as exc:  # noqa: BLE001 - surface a clean CLI error
        print(f"Backup failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
