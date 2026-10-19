#!/usr/bin/env python3
"""자체 Dart 파일이 250줄을 넘으면 실패함.

빈 줄과 주석을 포함해 추적 중인 Dart 파일과 lib/, test/, tool/의 미추적 파일을 셈.
빌드 결과와 외부 SDK·패키지는 제외함.
"""

import os
import subprocess
import sys

MAX_LINES = 250
EXCLUDED_SEGMENTS = (".dart_tool/", "/build/")
FIRST_PARTY_DIRS = ("lib/", "test/", "tool/")


def _git_lines(*args: str) -> list[str]:
    out = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=True
    ).stdout
    return [line for line in out.splitlines() if line]


def _is_excluded(path: str) -> bool:
    if path.startswith("build/"):
        return True
    return any(segment in f"/{path}" for segment in EXCLUDED_SEGMENTS)


def _collect_dart_files() -> list[str]:
    tracked = _git_lines("ls-files", "--", "*.dart")
    untracked = _git_lines(
        "ls-files",
        "--others",
        "--exclude-standard",
        "--",
        *(f"{d}*.dart" for d in FIRST_PARTY_DIRS),
        *(f"{d}**/*.dart" for d in FIRST_PARTY_DIRS),
    )
    files = sorted(set(tracked) | set(untracked))
    return [path for path in files if not _is_excluded(path)]


def main() -> int:
    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    os.chdir(root)

    violations = []
    for path in _collect_dart_files():
        with open(path, encoding="utf-8") as f:
            line_count = len(f.read().splitlines())
        if line_count > MAX_LINES:
            violations.append((path, line_count))

    if not violations:
        return 0

    for path, line_count in violations:
        print(f"{path}: {line_count} lines (> {MAX_LINES})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
