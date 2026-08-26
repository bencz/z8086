#!/usr/bin/env python3
"""Fail closed if the original z8086 microcode image changes."""

from __future__ import annotations

import hashlib
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
IMAGE = ROOT / "src" / "z8086" / "ucode.hex"
EXPECTED_SHA256 = "953db83ee7683d84d2ea6a63191d38c75aaf152090de81cc4a9e12053e4bed9d"
EXPECTED_WORDS = 512
WORD_RE = re.compile(r"[0-9A-Fa-f]{6}")


def fail(message: str) -> None:
    print(f"ERROR: microcode integrity check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    raw = IMAGE.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA256:
        fail(f"SHA-256 is {digest}, expected {EXPECTED_SHA256}")

    lines = raw.decode("ascii").splitlines()
    if len(lines) != EXPECTED_WORDS:
        fail(f"image contains {len(lines)} words, expected {EXPECTED_WORDS}")

    for address, token in enumerate(lines):
        if WORD_RE.fullmatch(token) is None:
            fail(f"word 0x{address:03x} is not exactly six hexadecimal digits")
        if int(token, 16) >> 21:
            fail(f"word 0x{address:03x} has non-zero bits above bit 20")

    nonzero = sum(int(token, 16) != 0 for token in lines)
    print(
        "PASS: original microcode locked "
        f"({EXPECTED_WORDS}x21 bits, {nonzero} non-zero words, SHA-256 {digest})"
    )


if __name__ == "__main__":
    main()
