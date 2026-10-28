#!/usr/bin/env python3
"""Run on macOS: python3 tool/macos_resource_signing_test.py."""

import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest

from macos_resource_signing import MACH_O_MAGIC, strip_resource_bundle_signatures


class ResourceSigningTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.resources = Path(self.temporary.name) / "Resources"
        self.resources.mkdir()

    def bundle(self, name="fixture", executable=False):
        bundle = self.resources / f"{name}.bundle"
        (bundle / "Contents/Resources").mkdir(parents=True)
        info = {"CFBundleIdentifier": f"com.example.{name}", "CFBundlePackageType": "BNDL"}
        if executable:
            info["CFBundleExecutable"] = "helper"
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        (bundle / "Contents/Resources/PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))
        return bundle

    def sign(self, bundle):
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(bundle)], check=True, capture_output=True)

    def signed(self, bundle):
        return subprocess.run(["/usr/bin/codesign", "--display", str(bundle)], capture_output=True).returncode == 0

    def test_codeless_signed_and_unsigned_resources_are_preserved_and_repeatable(self):
        signed = self.bundle("signed")
        self.bundle("unsigned")
        self.sign(signed)
        self.assertTrue(self.signed(signed))
        before = {path.relative_to(self.resources): path.read_bytes() for path in self.resources.rglob("*") if path.is_file() and "_CodeSignature" not in path.parts}
        self.assertEqual(strip_resource_bundle_signatures(self.resources), 2)
        self.assertFalse(self.signed(signed))
        self.assertEqual(strip_resource_bundle_signatures(self.resources), 2)
        after = {path.relative_to(self.resources): path.read_bytes() for path in self.resources.rglob("*") if path.is_file()}
        self.assertEqual(after, before)

    def test_executable_bundle_fails_before_any_signature_is_removed(self):
        protected = self.bundle("a-signed")
        self.sign(protected)
        self.bundle("z-executable", executable=True)
        with self.assertRaisesRegex(ValueError, "executable bundle"):
            strip_resource_bundle_signatures(self.resources)
        self.assertTrue(self.signed(protected))

    def test_all_mach_o_formats_are_rejected_even_without_executable_key(self):
        protected = self.bundle()
        binary = protected / "Contents/Resources/hidden-code"
        for magic in MACH_O_MAGIC:
            with self.subTest(magic=magic.hex()):
                binary.write_bytes(magic + b"fixture")
                self.sign(protected)
                with self.assertRaisesRegex(ValueError, "Mach-O code"):
                    strip_resource_bundle_signatures(self.resources)
                self.assertTrue(self.signed(protected))

    def test_symlinks_and_unrecognized_bundles_fail_closed(self):
        bundle = self.bundle()
        link = bundle / "Contents/Resources/link"
        link.symlink_to(Path(self.temporary.name))
        with self.assertRaisesRegex(ValueError, "Unsafe resource bundle entry"):
            strip_resource_bundle_signatures(self.resources)
        link.unlink()
        (bundle / "Contents/Info.plist").unlink()
        with self.assertRaisesRegex(ValueError, "no Info.plist"):
            strip_resource_bundle_signatures(self.resources)


if __name__ == "__main__":
    unittest.main()
