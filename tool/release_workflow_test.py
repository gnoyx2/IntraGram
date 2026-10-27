#!/usr/bin/env python3
"""Run the actual Android release shell steps with disposable signing fixtures."""

import itertools
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/release.yml"


def step(name):
    lines = WORKFLOW.read_text().splitlines()
    start = lines.index(f"      - name: {name}")
    start = lines.index("        run: |", start) + 1
    end = start
    while end < len(lines) and (not lines[end] or lines[end].startswith("          ")):
        end += 1
    script = textwrap.dedent("\n".join(lines[start:end]))
    subprocess.run(["bash", "-n"], input=script, text=True, check=True)
    return script


RESTORE = step("Restore release keystore (only if the secrets exist)")
COLLECT = step("Collect artifacts and measure signing")
NAMES = ("KEYSTORE_B64", "STORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD")
VALUES = ("a2V5c3RvcmU=", "store-secret", "upload", "key-secret")


def run(script, root, **env):
    return subprocess.run(
        ["bash", "-e", "-o", "pipefail"], input=script, text=True,
        cwd=root, env={**os.environ, **env}, capture_output=True,
    )


for present in itertools.product((False, True), repeat=4):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "android").mkdir()
        properties = root / "android/key.properties"
        properties.write_text("stale signing configuration")
        keystore = root / "release.jks"
        keystore.write_text("stale key")
        secrets = dict(zip(NAMES, (v if p else "" for p, v in zip(present, VALUES))))
        result = run(RESTORE, root, RUNNER_TEMP=directory, **secrets)
        assert (result.returncode == 0) == (all(present) or not any(present)), present
        assert properties.exists() == all(present), present
        assert keystore.exists() == all(present), present
        assert "store-secret" not in result.stdout + result.stderr
        assert "key-secret" not in result.stdout + result.stderr
        if all(present):
            assert keystore.read_bytes() == b"keystore"
            assert "keyAlias=upload" in properties.read_text()

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "android").mkdir()
    secrets = dict(zip(NAMES, VALUES))
    secrets["KEYSTORE_B64"] = "invalid!"
    assert run(RESTORE, root, RUNNER_TEMP=directory, **secrets).returncode != 0
    assert not (root / "android/key.properties").exists()


cases = ("debug", "release", "bad-signature", "no-signer", "debug-key", "no-apk", "no-aab")
for case in cases:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for folder in ("android", "dist", "build/app/outputs/flutter-apk",
                       "build/app/outputs/bundle/release", "sdk/build-tools/36.0.0", "bin"):
            (root / folder).mkdir(parents=True)
        if case != "debug":
            (root / "android/key.properties").write_text("fixture")
        if case != "no-apk":
            (root / "build/app/outputs/flutter-apk/app-release.apk").write_text("fixture APK")
        if case != "no-aab":
            (root / "build/app/outputs/bundle/release/app-release.aab").write_text("fixture AAB")
        (root / "dist/stale.apk").write_text("old APK")
        (root / "dist/stale.aab").write_text("old AAB")
        (root / "dist/SIGNING-android.txt").write_text("old report")
        signer = root / "sdk/build-tools/36.0.0/apksigner"
        signer.write_text('#!/bin/sh\ncat "$SIGNER_OUTPUT"\nexit "$SIGNER_EXIT"\n')
        signer.chmod(0o700)
        keytool = root / "bin/keytool"
        keytool.write_text("#!/bin/sh\nprintf 'Owner: CN=Release\nSHA256: fixture\n'\n")
        keytool.chmod(0o700)
        identity = "Android Debug" if case in ("debug", "debug-key") else "Release"
        output = root / "signer.txt"
        output.write_text("" if case == "no-signer" else
                          f"Signer #1 certificate DN: CN={identity}\n"
                          "Signer #1 certificate SHA-256 digest: fixture\n")
        result = run(COLLECT, root, ANDROID_HOME=str(root / "sdk"),
                     PATH=f"{root / 'bin'}:{os.environ['PATH']}",
                     GITHUB_SHA="fixture-commit", FLUTTER_VERSION="fixture-version",
                     SIGNER_OUTPUT=str(output), SIGNER_EXIT="1" if case == "bad-signature" else "0")
        assert (result.returncode == 0) == (case in ("debug", "release")), (case, result.stderr)
        assert not (root / "dist/stale.apk").exists()
        assert not (root / "dist/stale.aab").exists()
        if case in ("debug", "release"):
            suffix = "-debugsigned" if case == "debug" else ""
            expected = {f"intragram-android{suffix}.apk", "SIGNING-android.txt"}
            if case == "release":
                expected.add("intragram.aab")
            assert {p.name for p in (root / "dist").iterdir()} == expected
            assert "old report" not in (root / "dist/SIGNING-android.txt").read_text()

print("Android release workflow: 24 signing and packaging cases passed.")
