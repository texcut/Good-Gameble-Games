#!/usr/bin/env python3
"""Preserve the owner's verified test setup; never edits the live library.

This development handoff expects an already tested, private Wine+Apple overlay
and stopped prefix. It does not download, redistribute, or accept Apple terms.
The app validates the handoff and connects the existing game on its next start.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid

RUNTIME_NAME = 'whisky-gptk-4.6.4-beta.1-apple-4.0b3'
ARCHIVE_SHA = 'c8e6a10dfeb54fc16d3dd3382ee2e9d2cec3eb1f5641613cad8b07903818cb12'
DMG_SHA = 'afa311da371f5b6dd970b45378a3d3df567cc9e535818f56f9b3f9d4c9537c1d'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def preserve(args):
    root, runtime, prefix = args.root.resolve(), args.runtime.resolve(), args.prefix.resolve()
    handoff = root / 'prepared-d3dmetal-game.json'
    if handoff.exists():
        raise RuntimeError('A prepared setup already exists and has been preserved; inspect it before preparing another.')
    require(digest(args.archive) == ARCHIVE_SHA, 'Wine archive checksum mismatch')
    require(digest(args.dmg) == DMG_SHA, 'Apple DMG checksum mismatch')
    with (runtime / 'WhiskyWineVersion.plist').open('rb') as f:
        info = plistlib.load(f)
    require(info['gptkCapable'] is True, 'Prepared runtime validation failed')
    require(info['version'] == {'major': 4, 'minor': 6, 'patch': 4}, 'Prepared runtime validation failed')
    framework = runtime / 'Wine/lib/external/D3DMetal.framework'
    with (framework / 'Resources/version.plist').open('rb') as f:
        require(plistlib.load(f)['CFBundleShortVersionString'] == '4.0b3', 'Prepared runtime validation failed')
    for binary in [framework, runtime / 'Wine/lib/external/libd3dshared.dylib']:
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '-R=anchor apple', str(binary)], check=True)
    with (root / 'library.json').open() as f:
        library = json.load(f)
    game = next(g for g in library['games'] if g['id'] == args.game_id)
    require(game['bottleID'] == args.source_bottle_id, 'The source game changed; library preserved')
    source_prefix = root / 'Bottles' / args.source_bottle_id
    from urllib.parse import unquote, urlparse
    original = Path(unquote(urlparse(game['executable']).path))
    relative = original.relative_to(source_prefix)
    require((prefix / relative).is_file(), 'Test copy does not contain this game')
    require(not (prefix / '.gggmac-graphics').exists(), 'DXMT files are still deployed')
    require((prefix / 'drive_c').is_dir() and (prefix / 'system.reg').is_file(), 'Prepared runtime validation failed')
    destination_runtime = root / 'Runtimes' / RUNTIME_NAME
    require(not destination_runtime.exists(), 'Runtime destination exists; preserved')
    bottle_id = str(uuid.uuid4()).upper()
    destination_prefix = root / 'Bottles' / bottle_id
    runtime_stage = destination_runtime.parent / ('.prepare-' + str(uuid.uuid4()))
    prefix_stage = destination_prefix.parent / ('.prepare-' + str(uuid.uuid4()))
    for source, stage in [(runtime, runtime_stage), (prefix, prefix_stage)]:
        stage.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/bin/cp', '-cR', str(source), str(stage)], check=True, timeout=240)
    hashes = {}
    for folder in [runtime_stage / 'Wine/lib/external', runtime_stage / 'Wine/lib/wine/x86_64-windows']:
        paths = folder.rglob('*') if folder.name == 'external' else [folder / n for n in ['d3d10.dll', 'd3d11.dll', 'd3d12.dll', 'd3d12core.dll', 'dxgi.dll', 'nvapi64.dll', 'nvngx-on-metalfx.dll']]
        for file in paths:
            if file.is_file() and not file.is_symlink():
                hashes[str(file.relative_to(runtime_stage))] = digest(file)
    for name in ['Wine/bin/wine', 'Wine/bin/wineserver', 'WhiskyWineVersion.plist']:
        hashes[name] = digest(runtime_stage / name)
    require(len(hashes) <= 100, 'Prepared runtime validation failed')
    receipt = dict(sourceArchiveSHA256=ARCHIVE_SHA, appleDMGSHA256=DMG_SHA,
                   appleVersion='4.0b3', wineVersion='wine-11.16', files=hashes)
    (runtime_stage / 'gggmac-d3dmetal.json').write_text(json.dumps(receipt, indent=2, sort_keys=True))
    runtime_stage.rename(destination_runtime)
    prefix_stage.rename(destination_prefix)
    payload = dict(gameID=args.game_id, sourceBottleID=args.source_bottle_id,
                   bottleID=bottle_id, relativeExecutablePath=str(relative))
    with handoff.open('x') as f:
        json.dump(payload, f, indent=2)
    print('Prepared permanent Wine:', destination_runtime / 'Wine/bin/wine')
    print('Prepared permanent game:', destination_prefix / relative)
    print('Handoff:', handoff)
    print('Live library.json was not modified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['root', 'runtime', 'prefix', 'archive', 'dmg']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--game-id', required=True)
    parser.add_argument('--source-bottle-id', required=True)
    preserve(parser.parse_args())
