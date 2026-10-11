from pathlib import Path
import re
from hashlib import sha256
base=Path(__file__).parent
src=(base/'installer.c').read_text()
manifest=(base/'payload'/'MANIFEST-SHA256.txt').read_text()
assert 'UPSTREAM-RELEASE.json' not in (base/'payload'/'Download-Latest-Renderer.ps1').read_text()
files=[line.split('  ',1) for line in manifest.strip().splitlines()]
for expected,name in files:
    data=(base/'payload'/name).read_bytes()
    assert sha256(data).hexdigest()==expected,(name,'hash mismatch')
    assert (f'L"{name.replace("/", chr(92)*2)}"' in src),(name,'not embedded')
for name in ['Download-Latest-Renderer.ps1','RUN-UPDATE-RENDERER.bat','RUN-DLSS-PLAYER.bat']:
    assert src.count(name)>0
updater=(base/'payload'/'Download-Latest-Renderer.ps1').read_text()
checks=['https://api.github.com/repos/2600th/dlss5-video-player/releases?per_page=30',
    '[a-fA-F0-9]{64}', '.sha256', 'Get-FileHash', 'verify_package.ps1',
    'upstream-backups','renderer-version.json', 'NeuralWorker.exe', 'ZipFile',
    'SHA-256 MISMATCH', 'Move-Item -LiteralPath $backup -Destination $upstream']
for check in checks:
    assert check in updater,check
assert 'neural-runtime' in updater
assert '.dll' not in '\n'.join(str(p) for p in (base/'payload').rglob('*') if p.is_file())
# Balanced round-trip grammar sanity for first-party PowerShell script (ignoring
# punctuation inside strings and comments): an early check, not a PS compiler.

def stripped(text):
    result=[]; quote=None; comment=False; escape=False
    for c in text:
        if comment:
            if c=='\n': comment=False; result.append(c)
            continue
        if quote:
            if escape: escape=False
            elif c=='`': escape=True
            elif c==quote: quote=None
            continue
        if c=='#': comment=True; continue
        if c in "'\"": quote=c;continue
        result.append(c)
    assert quote is None,'unterminated PowerShell string'
    return ''.join(result)
text=stripped(updater)
for a,b in [('(',')'),('{','}'),('[',']')]:
    assert text.count(a)==text.count(b),f'unbalanced {a}{b}'
print('PASS: 14 payload hashes, presence, download restrictions, basic PS syntax checks.')
