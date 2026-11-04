#!/usr/bin/env python3
"""Build a universal release with Command Line Tools and precompiled UI resources.

The template must have MainMenu.nib and Assets.car matching the repository's
unchanged XIB/assets. Full Xcode is needed to compile those resources from scratch.
XCLog must be the source at the revision pinned in Package.resolved.
"""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--template', type=pathlib.Path, required=True)
parser.add_argument('--xclog', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
project = (root / 'ExSticky.xcodeproj/project.pbxproj').read_text()
version = re.search(r'MARKETING_VERSION = ([^;]+);', project)[1]
build_number = re.search(r'CURRENT_PROJECT_VERSION = ([^;]+);', project)[1]

def run(*command):
    subprocess.run([str(arg) for arg in command], check=True)

app = output / 'ExSticky.app'
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True)
shutil.copytree(args.template / 'Contents/Resources', contents / 'Resources')
resources = contents / 'Resources'
shutil.rmtree(resources / 'Markdown', ignore_errors=True)
shutil.copytree(root / 'ExSticky/Markdown', resources / 'Markdown')
shutil.copy2(root / 'LICENSE', resources / 'LICENSE')
info = plistlib.loads((args.template / 'Contents/Info.plist').read_bytes())
info.update(CFBundleShortVersionString=version, CFBundleVersion=build_number,
            CFBundleExecutable='ExSticky', CFBundleName='ExSticky',
            CFBundleIdentifier='com.yangxijie.exsticky.beta', LSMinimumSystemVersion='12.1')
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
(contents / 'PkgInfo').write_bytes(b'APPL????')
catalog = json.loads((root / 'Localizable.xcstrings').read_text())
for language in ['en', 'zh-Hans']:
    folder = resources / (language + '.lproj')
    folder.mkdir(exist_ok=True)
    strings = {key: entry.get('localizations', {}).get(language, {}).get('stringUnit', {}).get('value', key)
               for key, entry in catalog['strings'].items()}
    (folder / 'Localizable.strings').write_bytes(plistlib.dumps(strings))

with tempfile.TemporaryDirectory(prefix='exsticky-release-build-') as temporary:
    build = pathlib.Path(temporary)
    binaries = []
    for arch in ['arm64', 'x86_64']:
        target = build / arch
        target.mkdir()
        flags = ['-swift-version', '5', '-O', '-target', arch + '-apple-macosx12.1',
                 '-module-cache-path', str(target / 'cache')]
        print('Compiling ' + arch, flush=True)
        run('swiftc', *flags, '-parse-as-library', '-emit-module', '-emit-object',
            '-module-name', 'XCLog', args.xclog, '-emit-module-path', target / 'XCLog.swiftmodule',
            '-o', target / 'XCLog.o')
        binary = target / 'ExSticky'
        run('swiftc', *flags, '-module-name', 'ExSticky', '-I', target,
            *sorted((root / 'ExSticky').rglob('*.swift')), target / 'XCLog.o', '-o', binary)
        binaries.append(binary)
    run('lipo', '-create', *binaries, '-output', contents / 'MacOS/ExSticky')

run('codesign', '--force', '--sign', '-', '--entitlements', root / 'ExSticky/ExSticky.entitlements', app)
run('codesign', '--verify', '--deep', '--strict', app)
run('lipo', '-verify_arch', 'arm64', 'x86_64', contents / 'MacOS/ExSticky')
stem = 'ExSticky-' + version + '-universal'
run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, output / (stem + '.zip'))
metadata = {
    'version': version, 'build': build_number,
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'architectures': ['arm64', 'x86_64'], 'minimum_macos': '12.1',
    'signing': 'ad-hoc', 'notarized': False,
    'resource_build': 'Precompiled NIB/assets from template; Swift and Markdown from this checkout',
    'xclog_sha256': hashlib.sha256(args.xclog.read_bytes()).hexdigest(),
    'swift': subprocess.check_output(['swiftc', '--version'], text=True).strip(),
}
(output / 'BUILD-INFO.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('Release output: ' + str(output), flush=True)
