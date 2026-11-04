#!/usr/bin/env python3
"""Run native WebKit Markdown integration checks with the project's pinned XCLog source.

Usage: python3 Tests/run-markdown-checks.py /path/to/XCLog/Sources/XCLog/XCLog.swift
The dependency revision is recorded in Package.resolved. No production app is launched.
"""
import pathlib
import platform
import subprocess
import sys
import tempfile
import shutil
import plistlib

root = pathlib.Path(__file__).resolve().parent.parent
if len(sys.argv) != 2 or not pathlib.Path(sys.argv[1]).is_file():
    sys.exit(__doc__)
with tempfile.TemporaryDirectory(prefix="exsticky-markdown-") as build:
    build = pathlib.Path(build)
    flags = ["-swift-version", "5", "-target", platform.machine() + "-apple-macosx12.1",
             "-module-cache-path", str(build / "module-cache")]
    subprocess.run(["swiftc", *flags, "-parse-as-library", "-emit-module", "-emit-object",
                    "-module-name", "XCLog", sys.argv[1], "-emit-module-path",
                    str(build / "XCLog.swiftmodule"), "-o", str(build / "XCLog.o")], check=True)
    sources = sorted(str(p) for p in (root / "ExSticky").rglob("*.swift") if p.name != "AppDelegate.swift")
    app = build / "MarkdownChecks.app" / "Contents"
    (app / "MacOS").mkdir(parents=True)
    (app / "Resources").mkdir()
    shutil.copytree(root / "ExSticky/Markdown", app / "Resources/Markdown")
    (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.exsticky.markdownchecks", "CFBundleExecutable": "MarkdownChecks", "CFBundlePackageType": "APPL"}))
    binary = app / "MacOS/MarkdownChecks"
    subprocess.run(["swiftc", *flags, "-module-name", "MarkdownEditorChecks", "-I", str(build),
                    *sources, str(root / "Tests/MarkdownEditorChecks.swift"), str(build / "XCLog.o"),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
