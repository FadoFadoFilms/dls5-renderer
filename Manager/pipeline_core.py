"""FadoEXR Pipeline Manager: safe local project sync and render handoff.

No Unity Editor automation happens here. Unity loads handoffs on user action.
All writes to Unity projects are opt-in except capture handoff when the watcher is enabled.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile


APP_NAME = 'FadoEXR Pipeline Manager'
SOURCE_FOLDERS = {
    'export': Path('1 Unity Export/Assets/FadoEXR'),
    'import': Path('3 Import/Assets/FadoEXR'),
}
INBOX_NAME = '.fadoexr-inbox'
FRAME_LIMIT = 240


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def data_root():
    override = os.environ.get('FADOEXR_MANAGER_DATA')
    if override:
        return Path(override).expanduser().resolve()
    if os.name == 'nt':
        return Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'FadoEXR' / 'PipelineManager'
    return Path.home() / '.local' / 'share' / 'FadoEXR' / 'PipelineManager'


def default_capture_root():
    return str(Path.home() / 'Documents' / 'FadoEXR_TestShots')


def project_root(path):
    if not path:
        raise ValueError('Select a Unity project folder first.')
    p = Path(path).expanduser().resolve(strict=True)
    if not p.is_dir() or not all((p / part).is_dir() for part in ('Assets', 'Packages', 'ProjectSettings')):
        raise ValueError('Expected Unity project root with Assets, Packages, and ProjectSettings: ' + str(p))
    if (p / 'Assets').is_symlink():
        raise ValueError('Linked Unity Assets directories are unsupported for safe updates.')
    return p


def repo_root():
    parent = Path(__file__).resolve().parent.parent
    if not all((parent / v).is_dir() for v in SOURCE_FOLDERS.values()):
        raise RuntimeError('Run the manager from the full dls5-renderer checkout; source packages are missing.')
    return parent


def source_files(role):
    if role not in SOURCE_FOLDERS:
        raise ValueError('Unknown Unity component: ' + role)
    folder = repo_root() / SOURCE_FOLDERS[role]
    if folder.is_symlink():
        raise ValueError('Refusing a symbolic-link source package')
    entries = {}
    for p in folder.rglob('*'):
        if p.is_symlink():
            raise ValueError('Refusing linked source file: ' + str(p))
        if p.is_file():
            if p.suffix not in {'.cs', '.shader', '.compute', '.hlsl', '.meta', '.asmdef', '.json', '.md', '.txt'}:
                raise ValueError('Unexpected package file: ' + str(p))
            entries[p.relative_to(folder).as_posix()] = p
    if not entries:
        raise RuntimeError('No source files in ' + str(folder))
    return entries


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for data in iter(lambda: f.read(1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def inspect_project(role, project):
    root = project_root(project)
    target = root / 'Assets' / 'FadoEXR'
    if target.is_symlink():
        raise ValueError('Assets/FadoEXR is a symbolic link; will not overwrite it.')
    files = source_files(role)
    changed, same, added, preserved_meta = [], [], [], []
    for rel, source in files.items():
        dest = target / rel
        if dest.is_symlink():
            raise ValueError('Destination contains symlink: ' + str(dest))
        if dest.exists():
            if not dest.is_file():
                raise ValueError('A file path is occupied by a directory: ' + str(dest))
            # Existing .meta GUIDs must remain stable even if a future source
            # package ships a different .meta for the same script/asset.
            if rel.endswith('.meta') and sha256(source) != sha256(dest):
                preserved_meta.append(rel)
            else:
                (same if sha256(source) == sha256(dest) else changed).append(rel)
        else:
            added.append(rel)
    return {'role': role, 'project': str(root), 'source_count': len(files),
            'changed': changed, 'same': same, 'added': added,
            'preserved_meta': preserved_meta,
            'target_exists': target.is_dir()}


def _reject_links(root):
    for p in root.rglob('*'):
        if p.is_symlink():
            raise ValueError('Target FadoEXR contains a symlink; update canceled: ' + str(p))


def _backup_folder(target, backup_dir):
    backup_dir.mkdir(parents=True, exist_ok=True)
    name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8] + '.zip'
    archive = backup_dir / name
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(target.rglob('*')):
            if p.is_file():
                z.write(p, p.relative_to(target).as_posix())
    return archive


def install_unity(role, project):
    """Update only Assets/FadoEXR. Back up before replacing, preserve .meta and unmanaged files."""
    plan = inspect_project(role, project)
    root = Path(plan['project'])
    target = root / 'Assets' / 'FadoEXR'
    if not plan['changed'] and not plan['added'] and plan['target_exists']:
        return {'status': 'up_to_date', 'backup': None, 'plan': plan}
    if target.exists() and not target.is_dir():
        raise ValueError('Assets/FadoEXR is not a folder')
    if target.exists():
        _reject_links(target)
    folder_id = hashlib.sha256(str(root).casefold().encode('utf-8')).hexdigest()[:16]
    archive = (_backup_folder(target, data_root() / 'backups' / folder_id / role)
               if target.exists() else None)
    # Temp directories are siblings of the target and outside Assets, so Unity never
    # sees half-written scripts. We use only same-filesystem rename for the switch.
    stage = root / ('.fadoexr-stage-' + uuid.uuid4().hex)
    rollback = root / ('.fadoexr-rollback-' + uuid.uuid4().hex)
    moved_old = False
    try:
        if target.exists():
            shutil.copytree(target, stage, symlinks=True)
        else:
            stage.mkdir()
        for rel, src in source_files(role).items():
            dst = stage / rel
            if rel.endswith('.meta') and dst.is_file():
                # Keep existing Unity asset GUIDs, even if source metadata differs.
                continue
            if dst.is_symlink():
                raise ValueError('Refusing to replace a symlink: ' + str(dst))
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        if target.exists():
            target.rename(rollback)
            moved_old = True
        try:
            stage.rename(target)
        except Exception:
            if moved_old:
                rollback.rename(target)
                moved_old = False
            raise
        if moved_old:
            shutil.rmtree(rollback)
        return {'status': 'installed', 'backup': str(archive) if archive else None, 'plan': plan}
    finally:
        if stage.exists():
            shutil.rmtree(stage)
        # If rollback unexpectedly remains after success/failure, NEVER delete it.


@dataclass
class Settings:
    film_project: str = ''
    import_project: str = ''
    capture_root: str = ''
    player_root: str = ''
    selected_shot: str = ''
    auto_handoff: bool = False
    fps: int = 24

    @classmethod
    def load(cls):
        location = data_root() / 'settings.json'
        if not location.is_file():
            return cls(capture_root=default_capture_root(),
                       player_root=str(data_root() / 'player'))
        data = json.loads(location.read_text(encoding='utf-8'))
        fields = cls.__dataclass_fields__
        settings = cls(**{k: data[k] for k in fields if k in data})
        if not settings.capture_root:
            settings.capture_root = default_capture_root()
        if not settings.player_root:
            settings.player_root = str(data_root() / 'player')
        return settings

    def save(self):
        location = data_root() / 'settings.json'
        location.parent.mkdir(parents=True, exist_ok=True)
        tmp = location.with_suffix('.json.tmp')
        tmp.write_text(json.dumps(asdict(self), indent=2) + '\n', encoding='utf-8')
        os.replace(tmp, location)


def _validated_shot(shot):
    supplied = Path(shot).expanduser()
    if supplied.is_symlink():
        raise ValueError('Select a normal captured shot directory, not a symbolic link.')
    folder = supplied.resolve(strict=True)
    if not folder.is_dir():
        raise ValueError('Select a normal captured shot directory.')
    report_file = folder / 'capture-report.txt'
    if not report_file.is_file():
        raise ValueError('Capture not finished: capture-report.txt missing.')
    report = report_file.read_text(encoding='utf-8-sig', errors='replace')
    def field(key):
        m = re.search(r'^' + re.escape(key) + r':\s*(.*)$', report, flags=re.M)
        return m.group(1).strip() if m else None
    if field('Reason') != 'Completed':
        raise ValueError('Capture did not complete successfully. Reason: ' + str(field('Reason')))
    if field('Errors') != '0':
        raise ValueError('Capture report includes errors; fix them before handoff.')
    requested = re.fullmatch(r'(\d+)\s*/\s*(\d+)', field('Requested') or '')
    if not requested or requested.group(1) != requested.group(2):
        raise ValueError('Captured frame count does not match the request.')
    count = int(requested.group(1))
    if not 1 <= count <= FRAME_LIMIT or field('Completed readbacks') != f'{count * 2}/{count * 2}':
        raise ValueError('Capture GPU readbacks incomplete or unsupported frame count.')
    for sub, prefix, ext in [('Clean', 'clean_', '.exr'),
                             ('Reference', 'reference_', '.exr'),
                             ('Grade', 'grade_', '.json')]:
        for i in range(count):
            path = folder / sub / f'{prefix}{i:06d}{ext}'
            if not path.is_file() or path.stat().st_size == 0 or path.is_symlink():
                raise ValueError('Capture missing file: ' + str(path))
    # Avoid walking into huge/corrupted folders or relying on arbitrary report names.
    for sub in ('Clean', 'Reference', 'Grade'):
        if (folder / sub).is_symlink():
            raise ValueError('Linked shot folder refused.')
    return folder, count, report


def _atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp-' + uuid.uuid4().hex)
    try:
        tmp.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def _inbox(import_project):
    project = project_root(import_project)
    inbox = project / INBOX_NAME
    if inbox.is_symlink():
        raise ValueError('Refusing a linked inbox')
    inbox.mkdir(exist_ok=True)
    # Prevent bulky/generated shot transfers from leaking into a separate Unity Git repo.
    ignore = inbox / '.gitignore'
    if not ignore.exists():
        ignore.write_text('*\n!.gitignore\n', encoding='utf-8')
    return inbox


def _job_id(shot):
    # Stable, collision-resistant ID, including shot path so same-named shots do not clash.
    digest = hashlib.sha256(str(shot).casefold().encode('utf-8')).hexdigest()[:12]
    stem = re.sub(r'[^a-zA-Z0-9_-]+', '_', shot.name).strip('_')[:48] or 'Shot'
    return stem + '-' + digest


def handoff_capture(shot, import_project):
    """Copy only grade JSON + report to importer project. Never copy massive raw EXRs."""
    folder, count, report = _validated_shot(shot)
    inbox = _inbox(import_project)
    ident = _job_id(folder)
    entry = inbox / 'jobs' / ident
    if entry.is_symlink():
        raise ValueError('Linked handoff job refused')
    entry.mkdir(parents=True, exist_ok=True)
    grade_dest = entry / 'Grade'
    if grade_dest.is_symlink():
        raise ValueError('Linked handoff grade folder refused')
    grade_dest.mkdir(exist_ok=True)
    for i in range(count):
        src = folder / 'Grade' / f'grade_{i:06d}.json'
        if src.is_symlink():
            raise ValueError('Linked grade JSON refused')
        dest = grade_dest / src.name
        if dest.is_symlink():
            raise ValueError('Linked destination file refused')
        # Keep staged copy consistent: write via temp, never expose half a JSON.
        temp = dest.with_name(dest.name + '.partial-' + uuid.uuid4().hex)
        try:
            shutil.copy2(src, temp)
            os.replace(temp, dest)
        finally:
            if temp.exists():
                temp.unlink()
    # Keep reference EXRs at their original location; Unity can compare on demand.
    # The importer may already have a processed file from an earlier render.
    manifest_file = entry / 'handoff.json'
    previous = json.loads(manifest_file.read_text('utf-8')) if manifest_file.is_file() else {}
    previous_frames = previous.get('processedFrames', '')
    if previous_frames and not (inbox / previous_frames).is_dir():
        previous_frames = ''
    info = {'schemaVersion': 1, 'jobId': ident, 'shotName': folder.name,
            'frameCount': count, 'createdUtc': utc_now(),
            'sourceShot': str(folder), 'gradeFolder': f'jobs/{ident}/Grade',
            'referenceFolder': str(folder / 'Reference'),
            'playerInput': str(folder / 'Player_Input'),
            'processedFrames': previous_frames,
            'note': 'EXRs remain in the source shot. Grade JSON is copied into importer inbox.'}
    _atomic_json(manifest_file, info)
    _atomic_json(inbox / 'latest.json', {'schemaVersion': 1, 'jobId': ident,
                                        'manifest': f'jobs/{ident}/handoff.json'})
    return info


def handoff_processed_frames(shot, import_project, frames_folder):
    """Copy a verified PNG sequence into the inbox; never into Unity Assets automatically."""
    folder, count, _ = _validated_shot(shot)
    source = Path(frames_folder).expanduser().resolve(strict=True)
    if source.is_symlink() or not source.is_dir():
        raise ValueError('Processed frame directory is invalid or linked')
    pngs = sorted(source.glob('frame_*.png'))
    expected = [f'frame_{i:06d}.png' for i in range(count)]
    if [p.name for p in pngs] != expected or any(p.is_symlink() or p.stat().st_size == 0 for p in pngs):
        raise ValueError('Processed PNG sequence must match captured frames exactly (frame_000000.png...).')
    info = handoff_capture(folder, import_project)
    inbox = _inbox(import_project)
    entry = inbox / 'jobs' / info['jobId']
    target = entry / 'ProcessedFrames'
    if target.exists():
        raise FileExistsError('Processed frames already handed off. Existing files are preserved: ' + str(target))
    staging = entry / ('ProcessedFrames.partial-' + uuid.uuid4().hex)
    try:
        staging.mkdir()
        for src in pngs:
            shutil.copy2(src, staging / src.name)
        staging.rename(target)
        info['processedFrames'] = f'jobs/{info["jobId"]}/ProcessedFrames'
        info['processedAtUtc'] = utc_now()
        _atomic_json(entry / 'handoff.json', info)
        _atomic_json(inbox / 'latest.json', {'schemaVersion': 1, 'jobId': info['jobId'],
                                            'manifest': f'jobs/{info["jobId"]}/handoff.json'})
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    return info


def completed_shots(capture_root):
    root = Path(capture_root).expanduser()
    if not root.is_dir():
        return []
    shots = []
    for child in root.iterdir():
        if child.is_dir() and not child.is_symlink() and (child / 'capture-report.txt').is_file():
            try:
                _validated_shot(child)
            except (OSError, ValueError):
                continue
            shots.append(child)
    return sorted(shots, key=lambda p: (p / 'capture-report.txt').stat().st_mtime)


def prepare_player_root(player_root):
    """Keep harness/updater current without modifying neural-runtime binaries."""
    folder = Path(player_root).expanduser().resolve()
    source = repo_root() / '2 Player/rtx2060-installer-source/payload'
    folder.mkdir(parents=True, exist_ok=True)
    for name in ('Download-Latest-Renderer.ps1', 'RTX2060-DLSS5-Offline-Test.ps1',
                 'RUN-DLSS-PLAYER.bat'):
        src = source / name
        if not src.is_file():
            raise FileNotFoundError(str(src))
        target = folder / name
        if target.is_symlink():
            raise ValueError('Linked player harness refused: ' + str(target))
        if target.exists() and sha256(target) == sha256(src):
            continue
        if target.exists():
            backup = data_root() / 'harness-backups'
            backup.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup / (name + '.' + uuid.uuid4().hex[:8] + '.bak'))
        tmp = folder / (name + '.partial-' + uuid.uuid4().hex)
        try:
            shutil.copy2(src, tmp)
            os.replace(tmp, target)
        finally:
            if tmp.exists():
                tmp.unlink()
    return folder


def powershell_exe():
    if os.name != 'nt':
        raise RuntimeError('Installing/running the community DLSS player requires Windows.')
    path = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32' / 'WindowsPowerShell' / 'v1.0' / 'powershell.exe'
    if not path.exists():
        raise RuntimeError('Windows PowerShell 5.1 is required.')
    return str(path)


def player_update_command(player_root):
    root = prepare_player_root(player_root)
    return [powershell_exe(), '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', str(root / 'Download-Latest-Renderer.ps1')]


def player_render_command(player_root, shot, fps=24):
    folder, count, _ = _validated_shot(shot)
    player = prepare_player_root(player_root)
    video = folder / 'Player_Input' / (folder.name + '_clean_FFV1_rec709.mkv')
    if not video.is_file():
        raise FileNotFoundError('Create player video first: ' + str(video))
    if not (player / 'upstream' / 'DLSSVideoPlayer.exe').is_file():
        raise FileNotFoundError('Download the complete player first with Download/Update Renderer.')
    return [powershell_exe(), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            str(player / 'RTX2060-DLSS5-Offline-Test.ps1'), '-InputVideo', str(video),
            '-PlayerRoot', str(player / 'upstream'),
            '-OutputRoot', str(folder / 'Player_Output'), '-SkipFrameProbes']


def video_conversion_command(shot, fps):
    folder, _, _ = _validated_shot(shot)
    if not 1 <= int(fps) <= 240:
        raise ValueError('FPS must be 1-240')
    script = repo_root() / 'Tools' / 'exr_to_player.py'
    return [sys.executable, str(script), str(folder), '--fps', str(int(fps))]


def convert_processed_video(video, shot):
    """Convert display-encoded video to PNG16 outside Unity, without overwrites."""
    folder, count, _ = _validated_shot(shot)
    source = Path(video).expanduser().resolve(strict=True)
    if not source.is_file() or source.suffix.lower() not in ('.mkv', '.mp4', '.mov'):
        raise ValueError('Choose a processed MKV, MP4 or MOV video')
    if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
        raise RuntimeError('Install FFmpeg and FFprobe on PATH to convert the processed video.')
    probe = subprocess.run(['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v:0',
                            '-show_entries', 'stream=nb_read_frames', '-of', 'json', str(source)],
                           check=True, capture_output=True, text=True)
    streams = json.loads(probe.stdout).get('streams', [])
    if len(streams) != 1 or int(streams[0].get('nb_read_frames') or 0) != count:
        raise ValueError('Processed video frame count does not match source (' + str(count) + ')')
    dest = folder / 'ProcessedFrames'
    if dest.exists():
        raise FileExistsError('ProcessedFrames already exists; refusing overwrite: ' + str(dest))
    stage = folder / ('ProcessedFrames.partial-' + uuid.uuid4().hex)
    try:
        stage.mkdir()
        vf = ('format=gbrp16le,zscale=transferin=bt709:primariesin=bt709:matrixin=gbr:'
              'transfer=iec61966-2-1:primaries=bt709:matrix=gbr:range=full,format=rgb48be')
        subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-n',
                        '-i', str(source), '-map', '0:v:0', '-fps_mode', 'passthrough',
                        '-vf', vf, '-start_number', '0', str(stage / 'frame_%06d.png')], check=True)
        actual = sorted(x.name for x in stage.glob('frame_*.png'))
        if actual != [f'frame_{i:06d}.png' for i in range(count)]:
            raise RuntimeError('Converted frame count/sequence mismatch')
        stage.rename(dest)
        return dest
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def latest_render_output(shot):
    """Choose a verified completed harness result; never assume an .mkv means neural success."""
    folder, _, _ = _validated_shot(shot)
    found = []
    for summary in (folder / 'Player_Output').glob('*/summary.json'):
        try:
            info = json.loads(summary.read_text('utf-8-sig'))
            if info.get('Verdict') != 'PASS_FULL_RENDER' or not info.get('OriginalUntouched'):
                continue
            if not (info.get('Signals') or {}).get('Feature18EvidenceSeen'):
                continue
            matches = list(summary.parent.glob('*-dlss5-neural.mkv'))
            if len(matches) == 1 and matches[0].stat().st_size > 0:
                found.append((summary.stat().st_mtime, matches[0]))
        except (OSError, ValueError, KeyError):
            continue
    return max(found)[1] if found else None
