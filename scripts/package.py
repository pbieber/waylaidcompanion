"""Build an installable archive of the addon: dist/PuggerWaylaidCompanion-<version>.zip.

The repository's root is the addon folder, so the archive puts its files under
PuggerWaylaidCompanion/, ready to unpack into Interface/AddOns. Only what the game loads
goes in, plus the README and the license.

    python scripts/package.py
"""
from pathlib import Path
import hashlib
import zipfile

NAME = 'PuggerWaylaidCompanion'
ROOT = Path(__file__).resolve().parents[1]
SKIP = {'.git', 'dist', 'scripts'}

toc = (ROOT / (NAME + '.toc')).read_text(encoding='utf-8')
version = next(line.split(':', 1)[1].strip() for line in toc.splitlines() if line.startswith('## Version:'))

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
    for line in toc.splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            assert NAME + '/' + line in names, line + ' is missing'

print(f'{archive}: {len(files)} files')
print('SHA256: ' + hashlib.sha256(archive.read_bytes()).hexdigest())
