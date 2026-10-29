import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("release_source", Path(__file__).resolve().parents[1] / "release_source.py")
release_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_source)


class ReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "Sources").mkdir()
        (self.root / "Sources/App.swift").write_text("public struct App {}")
        (self.root / "README.md").write_text("# Example")

    def tearDown(self):
        self.temp.cleanup()

    def test_archive_excludes_private_root_files_and_build_outputs(self):
        (self.root / "private.dmg").write_bytes(b"private payload")
        (self.root / ".env").write_text("secret")
        (self.root / "dist").mkdir()
        (self.root / "dist/old.zip").write_bytes(b"old")
        archive = self.root / "dist/source.zip"
        release_source.archive_source(self.root, archive, "0.14.0")
        with zipfile.ZipFile(archive) as source:
            self.assertEqual(set(source.namelist()), {"Good-Gameble-Games-0.14.0/README.md", "Good-Gameble-Games-0.14.0/Sources/App.swift"})

    def test_unexpected_windows_payload_is_rejected(self):
        (self.root / "Sources/vendor.dll").write_bytes(b"vendor")
        with self.assertRaises(ValueError):
            release_source.source_files(self.root)

    def test_only_named_original_probe_is_allowed(self):
        probe = self.root / release_source.OWN_PROBE
        probe.parent.mkdir(parents=True)
        probe.write_bytes(b"MZ fixture")
        self.assertIn(probe.resolve(), release_source.source_files(self.root))
        (probe.parent / "game.exe").write_bytes(b"MZ game")
        with self.assertRaises(ValueError):
            release_source.source_files(self.root)

    def test_link_cannot_pull_an_external_file_into_sources(self):
        (self.root / "Sources/linked.swift").symlink_to(self.root / ".env")
        with self.assertRaises(ValueError):
            release_source.source_files(self.root)

    def test_personal_home_path_is_rejected(self):
        (self.root / "Sources/private.swift").write_text(str(Path.home()) + "/private")
        with self.assertRaises(ValueError):
            release_source.source_files(self.root)

    def test_extensionless_framework_binary_is_rejected(self):
        (self.root / "Sources/MetalFramework").write_bytes(b"\xcf\xfa\xed\xfe\x00vendor")
        with self.assertRaises(ValueError):
            release_source.source_files(self.root)
