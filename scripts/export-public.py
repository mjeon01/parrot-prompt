#!/usr/bin/env python3
"""Export only explicitly approved public files, without any source Git history."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "public"
SECRET = re.compile(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:gh[pousr]_[A-Za-z0-9]{30,})|(?:AKIA[0-9A-Z]{16})|/Users/|C:\\\\Users\\\\|parrot-prompt|\.local-signing/")

def inspect():
    allowed = (ROOT / "scripts/public-files.txt").read_text().splitlines()
    if len(allowed) != len(set(allowed)):
        raise ValueError("Duplicate allowlist entry")
    for relative in allowed:
        path = PUBLIC / relative
        if path.is_symlink() or PUBLIC.resolve() not in path.resolve().parents:
            raise ValueError(f"Unsafe path: {relative}")
        data = path.read_bytes()
        if path.suffix not in {".md", ".txt", ".png"}:
            raise ValueError(f"Disallowed public file: {relative}")
        if SECRET.search(data):
            raise ValueError(f"Private information detected in {relative}")
        if path.suffix == ".md":
            for link in re.findall(r"\]\(([^)]+)\)", data.decode()):
                if "://" in link or link.startswith("#"):
                    continue
                target = (path.parent / link.split("#", 1)[0]).resolve()
                if not target.is_file() or str(target.relative_to(PUBLIC.resolve())) not in allowed:
                    raise ValueError(f"Broken or unpublished link in {relative}: {link}")
    extras = {str(p.relative_to(PUBLIC)) for p in PUBLIC.rglob("*") if p.is_file()} - set(allowed)
    if extras:
        raise ValueError(f"Files missing from explicit allowlist: {sorted(extras)}")
    return allowed

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", nargs="?")
    args = parser.parse_args()
    allowed = inspect()
    if args.destination:
        destination = Path(args.destination).resolve()
        if destination.exists() and any(destination.iterdir()):
            raise ValueError("Destination must be empty; existing repository histories are never reused")
        destination.mkdir(parents=True, exist_ok=True)
        for relative in allowed:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(PUBLIC / relative, target)
    for relative in allowed:
        print(hashlib.sha256((PUBLIC / relative).read_bytes()).hexdigest(), relative)
    print(f"Validated {len(allowed)} explicitly allowed public files; no source or Git history exported.")

if __name__ == "__main__":
    main()
