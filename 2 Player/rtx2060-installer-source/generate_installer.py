#!/usr/bin/env python3
"""Embed audited harness files in the freestanding per-user Win64 installer.

Generate from installer-template.c, using payload files in ./payload/. The
binary never embeds the third-party DLSS neural runtime.
"""
from pathlib import Path
from hashlib import sha256

base = Path(__file__).resolve().parent
folder = base / 'payload'
files = [
    ('LICENSE.txt', False),
    ('MANIFEST-SHA256.txt', False),
    ('README.md', False),
    ('RTX2060-DLSS5-Offline-Test.ps1', False),
    ('RUN-DROP-VIDEO-HERE.bat', False),
    ('RUN-PROBE-ONLY.bat', False),
    ('RUN-UPDATE-RENDERER.bat', False),
    ('RUN-DLSS-PLAYER.bat', False),
    ('Download-Latest-Renderer.ps1', False),
    ('UPDATER-NOTES.md', False),
    ('SOURCE-FORK.md', False),
    ('SOURCE-NOTES.md', False),
    ('patches/0001-rtx2060-native-per-frame-timing.patch', False),
    ('results/README.txt', True),
    ('upstream/PUT-UPSTREAM-HERE.txt', True),
]

for name, _ in files:
    if not (folder / name).is_file():
        raise SystemExit('Missing payload file: ' + name)

manifest = '\n'.join(
    sha256((folder / name).read_bytes()).hexdigest() + '  ' + name
    for name, _ in files if name != 'MANIFEST-SHA256.txt'
) + '\n'
(folder / 'MANIFEST-SHA256.txt').write_text(manifest, encoding='utf-8')

parts = ['/* Auto-generated embedded payload; no 3rd-party binaries. */\n']
for i, (relpath, _) in enumerate(files):
    data = (folder / relpath).read_bytes()
    lines = [', '.join(f'0x{v:02x}' for v in data[n:n + 20]) for n in range(0, len(data), 20)]
    parts.append(f'static const unsigned char file_{i}[] = {{\n  ' + ',\n  '.join(lines) + '\n};\n')
parts.append('typedef struct { const wchar_t* rel; const unsigned char* data; DWORD size; int preserve; } PAYLOAD;\n')
parts.append('static const PAYLOAD payload[] = {\n')
for i, (relpath, preserve) in enumerate(files):
    cpath = relpath.replace('/', '\\').replace('\\', '\\\\')
    parts.append(f'  {{ L"{cpath}", file_{i}, (DWORD)sizeof(file_{i}), {int(preserve)} }},\n')
parts.append('};\nstatic const DWORD payload_count=(DWORD)(sizeof(payload)/sizeof(payload[0]));\n')

template = (base / 'installer-template.c').read_text()
assert template.count('@@PAYLOAD@@') == 1
(base / 'installer.c').write_text(template.replace('@@PAYLOAD@@', '\n'.join(parts)))
print(f'Generated installer.c from {len(files)} payload files.')
