#!/usr/bin/env python3
"""Audit final ZIPs, not just the source export. Never publish raw CI artifacts."""
from pathlib import Path, PurePosixPath
import hashlib
import re
import sys
import zipfile

FORBIDDEN_SUFFIXES = {".swift", ".cs", ".csproj", ".ps1", ".sh", ".py", ".pdb", ".pfx", ".p12", ".key", ".pem", ".wav", ".mp3", ".keychain-db"}
MARKERS = [b"/Users/jeonmun-gi", b"parrot-prompt", b".local-signing", b"-----BEGIN PRIVATE KEY-----"]
MARKERS += [x.decode().encode("utf-16-le") for x in MARKERS]

def audit(path):
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = PurePosixPath(entry.filename)
            if name.is_absolute() or ".." in name.parts or ".git" in name.parts or "__MACOSX" in name.parts:
                raise ValueError(f"Unsafe archive path: {name}")
            if name.suffix.lower() in FORBIDDEN_SUFFIXES or "VoicePromptData" in name.parts:
                raise ValueError(f"Private/development file in release: {name}")
            if entry.is_dir(): continue
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f"Symlink in release: {name}")
            data = archive.read(entry)
            if any(marker in data for marker in MARKERS) or re.search(rb"gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}", data):
                raise ValueError(f"Private build path or credential marker in {name}")
        print(f"PASS {path.name}: {len(archive.infolist())} entries, {path.stat().st_size:,} bytes")
    return hashlib.sha256(path.read_bytes()).hexdigest()

if __name__ == "__main__":
    if len(sys.argv) < 2: raise SystemExit("Usage: audit-release.py RELEASE.zip [...]")
    for argument in sys.argv[1:]:
        path = Path(argument)
        print(audit(path), path.name)
