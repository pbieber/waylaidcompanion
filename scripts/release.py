"""Build the archive to upload to CurseForge: dist/PuggerWaylaidCompanion-<version>.zip.

    python scripts/release.py            build the version the toc already has
    python scripts/release.py 0.4.0      set the toc's version to 0.4.0 first, then build

The repository's root is the addon folder, so the archive puts its files under
PuggerWaylaidCompanion/, which is what CurseForge and Interface/AddOns expect. Only what
the game loads goes in, plus the README and the license.
"""
from pathlib import Path
import argparse
import hashlib
import re
import sys
import zipfile

NAME = 'PuggerWaylaidCompanion'
ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / (NAME + '.toc')
SKIP = {'.git', '.claude', 'dist', 'scripts'}
VERSION_LINE = re.compile(r'^(## Version:[ \t]*)(\S+)[ \t]*$', re.MULTILINE)


def read_toc():
    """The toc's text, with its line endings as they are."""
    return TOC.read_bytes().decode('utf-8')


def set_version(version):
    """Write a new version into the toc; False when it already had it."""
    text = read_toc()
    if not VERSION_LINE.search(text):
        sys.exit(TOC.name + ' has no "## Version:" line')
    changed = VERSION_LINE.sub(lambda m: m.group(1) + version, text, count=1)
    if changed == text:
        return False
    TOC.write_bytes(changed.encode('utf-8'))
    return True


def build():
    """Write the archive and return (its path, the version, how many files went in)."""
    text = read_toc()
    found = VERSION_LINE.search(text)
    if not found:
        sys.exit(TOC.name + ' has no "## Version:" line')
    version = found.group(2)

    files = [
        path for path in sorted(ROOT.rglob('*'))
        if path.is_file() and path.suffix in ('.lua', '.toc', '.tga')
        and not SKIP.intersection(path.relative_to(ROOT).parts)
    ]
    files += [ROOT / 'README.md', ROOT / 'LICENSE.txt']

    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    archive = dist / f'{NAME}-{version}.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in files:
            z.write(path, NAME + '/' + path.relative_to(ROOT).as_posix())

    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        names = set(z.namelist())
        # Every file the toc loads has to be in the archive.
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith('#'):
                assert NAME + '/' + line in names, line + ' is missing from the archive'
    return archive, version, len(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('version', nargs='?', help='new version for the toc, such as 0.4.0')
    args = parser.parse_args()

    if args.version:
        if not re.fullmatch(r'\d+(\.\d+)*(-[0-9A-Za-z.]+)?', args.version):
            sys.exit('Not a version: %s (expected something like 0.4.0 or 0.4.0-beta1)' % args.version)
        if set_version(args.version):
            print('%s: version set to %s' % (TOC.name, args.version))

    archive, version, count = build()
    print('%s: version %s, %d files' % (archive, version, count))
    print('SHA256: ' + hashlib.sha256(archive.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
