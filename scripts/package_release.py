#!/usr/bin/env python3
"""Package the already built app and matching public sources without publishing."""
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from release_source import archive_source


def package(root):
    app = root / "dist/Good Gameble Games.app"
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    with (root / "scripts/Info.plist").open("rb") as source:
        expected_info = plistlib.load(source)
    for key in ["CFBundleShortVersionString", "CFBundleVersion", "CFBundleIconFile"]:
        if info.get(key) != expected_info.get(key):
            raise ValueError("Stale app metadata: " + key + ". Rebuild before packaging.")
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid app version")
    required = {"Contents/MacOS/GGGMac", "Contents/Info.plist", "Contents/Resources/AppIcon.icns",
                "Contents/Resources/GGGMacGraphicsProbe.exe", "Contents/Resources/LICENSE",
                "Contents/Resources/NOTICE", "Contents/Resources/THIRD_PARTY_NOTICES.md",
                "Contents/Resources/licenses/MinGW-w64.txt", "Contents/Resources/licenses/Zig.txt",
                "Contents/_CodeSignature/CodeResources"}
    files = set()
    for file in app.rglob("*"):
        if file.is_symlink():
            raise ValueError("Unexpected app link: " + str(file.relative_to(app)))
        if file.is_file():
            files.add(file.relative_to(app).as_posix())
    if files != required:
        raise ValueError("App contents mismatch; missing: " + str(required - files) + "; unexpected: " + str(files - required))
    resources = {"AppIcon.icns": root / "assets/AppIcon.icns",
                 "GGGMacGraphicsProbe.exe": root / "Sources/GGGMacCore/Resources/GGGMacGraphicsProbe.exe",
                 "LICENSE": root / "LICENSE", "NOTICE": root / "NOTICE", "THIRD_PARTY_NOTICES.md": root / "THIRD_PARTY_NOTICES.md",
                 "licenses/MinGW-w64.txt": root / "licenses/MinGW-w64.txt", "licenses/Zig.txt": root / "licenses/Zig.txt"}
    for name, source in resources.items():
        if (app / "Contents/Resources" / name).read_bytes() != source.read_bytes():
            raise ValueError("Stale app resource: " + name + ". Rebuild before packaging.")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/GGGMac")], text=True).split()
    if not architectures or not set(architectures).issubset({"arm64", "x86_64"}):
        raise ValueError("Unexpected binary architecture")
    arch = "universal" if len(architectures) == 2 else architectures[0]
    dist = root / "dist"
    app_zip = dist / ("Good-Gameble-Games-v" + version + "-macos-" + arch + ".zip")
    source_zip = dist / ("Good-Gameble-Games-v" + version + "-source.zip")
    count = archive_source(root, source_zip, version)
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(app_zip)], check=True)
    sums = "".join(hashlib.sha256(file.read_bytes()).hexdigest() + "  " + file.name + "\n" for file in [app_zip, source_zip])
    (dist / "SHA256SUMS").write_text(sums)
    print("Prepared", app_zip.name, "and", source_zip.name, "(" + str(count) + " source files).")
    print("No upload or release publication was performed.")


if __name__ == "__main__":
    try:
        package(Path(__file__).resolve().parent.parent)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Release packaging failed:", error, file=sys.stderr)
        sys.exit(1)
