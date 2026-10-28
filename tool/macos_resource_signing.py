#!/usr/bin/env python3
"""Leave codeless resource bundles covered by the enclosing app's signature."""

import plistlib
from pathlib import Path
import subprocess
import sys


MACH_O_MAGIC = {
    bytes.fromhex(value)
    for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )
}


def strip_resource_bundle_signatures(resources):
    resources = Path(resources)
    if resources.is_symlink() or not resources.is_dir():
        raise ValueError(f"Expected an app Resources directory: {resources}")
    bundles = sorted(resources.glob("*.bundle"))
    # Validate every bundle before changing any: executable code must retain its signature.
    for bundle in bundles:
        if bundle.is_symlink() or not bundle.is_dir():
            raise ValueError(f"Unsafe resource bundle: {bundle}")
        paths = list(bundle.rglob("*"))
        for path in paths:
            if path.is_symlink() or not (path.is_dir() or path.is_file()):
                raise ValueError(f"Unsafe resource bundle entry: {path}")
        info_paths = [path for path in (bundle / "Contents/Info.plist", bundle / "Info.plist") if path.is_file()]
        if not info_paths:
            raise ValueError(f"Resource bundle has no Info.plist: {bundle}")
        for info_path in info_paths:
            with info_path.open("rb") as stream:
                info = plistlib.load(stream)
            if not isinstance(info, dict) or "CFBundleExecutable" in info:
                raise ValueError(f"Refusing to strip an executable bundle: {bundle}")
        for path in paths:
            if path.is_file():
                with path.open("rb") as stream:
                    if stream.read(4) in MACH_O_MAGIC:
                        raise ValueError(f"Refusing to strip a bundle containing Mach-O code: {path}")
    for bundle in bundles:
        # Xcode export does not re-sign these SPM resources; stale development signatures cause 90284.
        subprocess.run(["/usr/bin/codesign", "--remove-signature", str(bundle)], check=True)
    return len(bundles)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: macos_resource_signing.py <app/Contents/Resources>")
    try:
        count = strip_resource_bundle_signatures(sys.argv[1])
        print(f"Prepared {count} codeless resource bundles for enclosing app signing.")
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        sys.exit(f"error: {error}")
