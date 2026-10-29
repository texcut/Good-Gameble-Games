#!/usr/bin/env python3
"""Select and audit public source files; never includes local runtime/user data."""
import argparse
from pathlib import Path
import re
import sys
import zipfile

ROOT_FILES = {"Package.swift", "Package.resolved", "README.md", "LICENSE", "NOTICE", "CONTRIBUTING.md",
              "THIRD_PARTY_NOTICES.md", "CHANGELOG.md", ".gitignore"}
ROOT_DIRS = {"Sources", "Tests", "Tools", "assets", "docs", "licenses", "scripts", ".github"}
EXCLUDED = {".build", ".git", "dist", ".swiftpm", "__pycache__", "node_modules"}
PRIVATE_DIRS = {"Runtimes", "Bottles", "Downloads", "Logs"}
FORBIDDEN = {".dmg", ".pkg", ".dll", ".dylib", ".so", ".bin", ".p12", ".pfx", ".pem", ".key",
             ".mobileprovision", ".log", ".zip", ".gz", ".xz", ".tar", ".7z", ".a", ".o", ".exe"}
OWN_PROBE = "Sources/GGGMacCore/Resources/GGGMacGraphicsProbe.exe"
SECRET_PATTERNS = [re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
                   re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
                   re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b")]


def source_files(root):
    root = Path(root).resolve()
    selected = []
    for entry in sorted(root.iterdir()):
        if entry.name in ROOT_FILES:
            candidates = [entry]
        elif entry.name in ROOT_DIRS:
            if entry.is_symlink():
                raise ValueError("Source directory is a link: " + entry.name)
            candidates = sorted(entry.rglob("*"))
        else:
            continue
        for file in candidates:
            rel = file.relative_to(root)
            if any(p in EXCLUDED or p.endswith(".iconset") for p in rel.parts) or file.name == ".DS_Store" or file.suffix == ".pyc":
                continue
            if file.is_symlink():
                raise ValueError("Source selection contains a link: " + str(rel))
            if not file.is_file():
                continue
            if any(p in PRIVATE_DIRS for p in rel.parts) or file.name.startswith(".env"):
                raise ValueError("Private data in source selection: " + str(rel))
            if file.suffix.lower() in FORBIDDEN and rel.as_posix() != OWN_PROBE:
                raise ValueError("Distribution payload in source selection: " + str(rel))
            data = file.read_bytes()
            if rel.as_posix() == OWN_PROBE:
                if not data.startswith(b"MZ"):
                    raise ValueError("Original diagnostic is not a Windows executable")
            elif file.suffix.lower() in {".png", ".icns"} and rel.parts[0] == "assets":
                expected = b"\x89PNG\r\n\x1a\n" if file.suffix.lower() == ".png" else b"icns"
                if not data.startswith(expected):
                    raise ValueError("Unexpected branding asset format: " + str(rel))
            else:
                try:
                    data.decode("utf-8")
                except UnicodeDecodeError:
                    raise ValueError("Unexpected binary in source selection: " + str(rel))
                if b"\x00" in data:
                    raise ValueError("Unexpected binary in source selection: " + str(rel))
            personal_home = str(Path.home()).encode()
            if personal_home not in [b"/", b""] and personal_home in data:
                raise ValueError("Personal home path in source selection: " + str(rel))
            if any(pattern.search(data) for pattern in SECRET_PATTERNS):
                raise ValueError("Credential pattern in source selection: " + str(rel))
            selected.append(file)
    return selected


def archive_source(root, destination, version):
    root = Path(root).resolve()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    files = source_files(root)
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Publish only a complete, audited archive.
    stage = destination.with_suffix(destination.suffix + ".tmp")
    try:
        with zipfile.ZipFile(stage, "w", zipfile.ZIP_DEFLATED) as output:
            for file in files:
                output.write(file, "Good-Gameble-Games-" + version + "/" + file.relative_to(root).as_posix())
        stage.replace(destination)
    finally:
        stage.unlink(missing_ok=True)
    return len(files)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        files = source_files(args.root)
        print("Source selection checked:", len(files), "files; local payloads and build output excluded.")
    except (OSError, ValueError) as error:
        print("Source audit failed:", error, file=sys.stderr)
        sys.exit(1)
