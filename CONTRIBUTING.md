# Contributing to Good Gameble Games

Start with `README.md` and run `bash scripts/swift-tool.sh test`. Build the local app using `bash scripts/build-app.sh`. Keep orchestration and data models in GGGMacCore, with UI behavior in GGGMac.

Run `python3 -m unittest discover -s scripts/tests` for release-source selection checks. `bash scripts/prepare-release.sh` builds checked local archives without publishing. Follow `docs/RELEASING.md` for signing and draft preparation.

Before reporting compatibility, include the exact macOS version, chip and GPU configuration, Wine distribution/version, game store and build, graphics backend/version, resolution and settings, steps to reproduce, and a reviewed diagnostic export. Label fake-runtime tests separately from actual Windows-program tests. A successful launch is not a stability or FPS measurement.

Runtime or graphics downloads must have a known source, license, checksum verification, and a reversible installation plan. Avoid silent registry edits, unversioned DLL replacement, shell execution of user input, or modifications to another launcher's environments. Preserve user files when setup fails.

Submit original work under GPL-3.0-or-later. Third-party components retain their own terms and must be documented before inclusion. Never commit game files, store credentials, or personal logs.

Forks and modifications are welcome under GPL-3.0-or-later. Retain the license and attribution notices, and include corresponding source with redistributed versions as required by the license. Only the exact GOG Witcher 3 build documented in the README is claimed as tested for this release; expand that evidence with reproducible reports rather than assuming other titles work.
