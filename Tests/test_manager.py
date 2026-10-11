"""Unit tests of offline/transactional FadoEXR Pipeline Manager operations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'Manager'))
import pipeline_core as core


class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fadoexr-manager-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.patchenv = patch.dict(os.environ, {'FADOEXR_MANAGER_DATA':str(self.base / 'appdata')})
        self.patchenv.start()
        self.addCleanup(self.patchenv.stop)
        self.film = self.new_project('film')
        self.importer = self.new_project('import')

    def new_project(self, name):
        p = self.base / name
        for dirname in ('Assets', 'Packages', 'ProjectSettings'):
            (p / dirname).mkdir(parents=True)
        return p

    def shot(self, name='Shot1', count=2, errors=0, reason='Completed'):
        folder = self.base / 'captures' / name
        for sub in ('Clean', 'Reference', 'Grade'):
            (folder / sub).mkdir(parents=True)
        for i in range(count):
            (folder / 'Clean' / f'clean_{i:06d}.exr').write_bytes(b'exr test')
            (folder / 'Reference' / f'reference_{i:06d}.exr').write_bytes(b'ref exr')
            (folder / 'Grade' / f'grade_{i:06d}.json').write_text(json.dumps({'frameIndex':i}))
        (folder / 'capture-report.txt').write_text(
            f'Reason: {reason}\nShot: {name}\nRequested: {count}/{count}\n'
            f'Timeline start frame: 0\nFPS: 24\nCompleted readbacks: {count*2}/{count*2}\n'
            f'Errors: {errors}\n', encoding='utf-8')
        return folder

    def test_preview_and_safe_update_and_backups(self):
        original = self.film / 'Assets' / 'FadoEXR'
        original.mkdir()
        (original / 'user_notes.txt').write_text('user custom content')
        (original / 'user_notes.txt.meta').write_text('guid: keep-me')
        (original / 'Editor').mkdir()
        (original / 'Editor' / 'FilmCaptureWindow.cs').write_text('old custom script')
        plan = core.inspect_project('export', self.film)
        self.assertIn('Editor/FilmCaptureWindow.cs', plan['changed'])
        first = core.install_unity('export', self.film)
        self.assertEqual(first['status'], 'installed')
        self.assertTrue(Path(first['backup']).exists())
        self.assertEqual((original / 'user_notes.txt').read_text(), 'user custom content')
        self.assertEqual((original / 'user_notes.txt.meta').read_text(), 'guid: keep-me')
        source = REPO / '1 Unity Export' / 'Assets' / 'FadoEXR' / 'Editor' / 'FilmCaptureWindow.cs'
        self.assertEqual((original / 'Editor' / 'FilmCaptureWindow.cs').read_bytes(), source.read_bytes())
        second = core.install_unity('export', self.film)
        self.assertEqual(second['status'], 'up_to_date')
        self.assertEqual(second['backup'], None)
        self.assertEqual(list(self.film.glob('.fadoexr-stage-*')), [])

    def test_export_import_are_separate_and_do_not_change_other_project(self):
        self.assertEqual(core.install_unity('import', self.importer)['status'], 'installed')
        self.assertTrue((self.importer / 'Assets/FadoEXR/Shaders/ReplayImage.shader').exists())
        self.assertFalse((self.film / 'Assets/FadoEXR').exists())
        self.assertFalse((self.importer / 'Assets/FadoEXR/Editor/FilmCaptureWindow.cs').exists())

    def test_incomplete_capture_is_never_handed_off(self):
        shot = self.shot(errors=1)
        with self.assertRaisesRegex(ValueError, 'errors'):
            core.handoff_capture(shot, self.importer)
        (shot / 'capture-report.txt').write_text('Reason: Canceled by user\nErrors: 0\n')
        with self.assertRaisesRegex(ValueError, 'did not complete'):
            core.handoff_capture(shot, self.importer)
        self.assertFalse((self.importer / core.INBOX_NAME / 'latest.json').exists())

    def test_capture_handoff_with_git_ignore_and_no_exr_copy(self):
        shot = self.shot(count=3)
        info = core.handoff_capture(shot, self.importer)
        inbox = self.importer / core.INBOX_NAME
        self.assertEqual(info['frameCount'], 3)
        self.assertEqual(len(list(inbox.glob('jobs/*/Grade/grade_*.json'))), 3)
        self.assertFalse(list(inbox.rglob('*.exr')))
        self.assertIn('*', (inbox / '.gitignore').read_text())
        latest = json.loads((inbox / 'latest.json').read_text())
        self.assertEqual(latest['jobId'], info['jobId'])
        self.assertEqual(len(core.completed_shots(shot.parent)), 1)
        # Idempotent handoff; previous shot is preserved.
        self.assertEqual(core.handoff_capture(shot, self.importer)['jobId'], info['jobId'])

    def test_processed_frames_strict_and_staged_outside_assets(self):
        shot = self.shot(count=2)
        rendered = self.base / 'rendered'
        rendered.mkdir()
        (rendered / 'frame_000000.png').write_bytes(b'PNG sample')
        with self.assertRaisesRegex(ValueError, 'match captured frames'):
            core.handoff_processed_frames(shot, self.importer, rendered)
        (rendered / 'frame_000001.png').write_bytes(b'PNG sample 2')
        result = core.handoff_processed_frames(shot, self.importer, rendered)
        self.assertIn('ProcessedFrames', result['processedFrames'])
        copied = self.importer / core.INBOX_NAME / result['processedFrames']
        self.assertEqual(len(list(copied.glob('*.png'))), 2)
        self.assertFalse((self.importer / 'Assets/FadoEXRImported').exists())
        with self.assertRaises(FileExistsError):
            core.handoff_processed_frames(shot, self.importer, rendered)

    def test_strict_harness_verdict(self):
        shot = self.shot(count=1)
        session = shot / 'Player_Output' / 'session123'
        session.mkdir(parents=True)
        video = session / 'Shot1-dlss5-neural.mkv'
        video.write_bytes(b'video')
        summary = session / 'summary.json'
        summary.write_text(json.dumps({'Verdict':'PASS_FULL_RENDER', 'OriginalUntouched':True,
                                       'Signals':{'Feature18EvidenceSeen':False}}))
        self.assertIsNone(core.latest_render_output(shot))
        summary.write_text(json.dumps({'Verdict':'PASS_FULL_RENDER', 'OriginalUntouched':True,
                                       'Signals':{'Feature18EvidenceSeen':True}}))
        self.assertEqual(core.latest_render_output(shot), video)

    @unittest.skipUnless(hasattr(os, 'symlink'), 'Symlink support required')
    def test_symlinked_existing_source_refused(self):
        dest = self.importer / 'Assets' / 'FadoEXR'
        dest.mkdir()
        (dest / 'Editor').symlink_to(self.film / 'Assets', target_is_directory=True)
        with self.assertRaises(ValueError):
            core.install_unity('import', self.importer)

    def test_unity_guid_meta_preserved_on_source_change(self):
        pkg = self.base / 'package'
        pkg.mkdir()
        (pkg / 'Sample.shader').write_text('shader v2')
        (pkg / 'Sample.shader.meta').write_text('guid: new-guid')
        target = self.importer / 'Assets/FadoEXR'
        target.mkdir()
        (target / 'Sample.shader').write_text('shader v1')
        (target / 'Sample.shader.meta').write_text('guid: existing-guid')
        files = {'Sample.shader': pkg / 'Sample.shader',
                 'Sample.shader.meta': pkg / 'Sample.shader.meta'}
        with patch.object(core, 'source_files', return_value=files):
            plan = core.inspect_project('import', self.importer)
            self.assertEqual(plan['preserved_meta'], ['Sample.shader.meta'])
            core.install_unity('import', self.importer)
        self.assertEqual((target / 'Sample.shader').read_text(), 'shader v2')
        self.assertEqual((target / 'Sample.shader.meta').read_text(), 'guid: existing-guid')

    @unittest.skipUnless(__import__('shutil').which('ffmpeg') and __import__('shutil').which('ffprobe'),
                         'FFmpeg and FFprobe required')
    def test_processed_video_ffmpeg_real_frames(self):
        # Build a short Rec.709 FFV1 video, then use the manager's return filter.
        shot = self.shot(count=2)
        video = self.base / 'source-video.mkv'
        subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
                        '-f', 'lavfi', '-i', 'testsrc2=size=64x64:rate=24:duration=0.0833334',
                        '-frames:v', '2', '-vf', 'format=yuv444p10le',
                        '-c:v', 'ffv1', '-color_trc', 'bt709', '-color_primaries', 'bt709',
                        '-colorspace', 'bt709', str(video)], check=True)
        folder = core.convert_processed_video(video, shot)
        self.assertEqual(len(list(folder.glob('frame_*.png'))), 2)
        info = core.handoff_processed_frames(shot, self.importer, folder)
        self.assertTrue((self.importer / core.INBOX_NAME / info['processedFrames'] / 'frame_000001.png').exists())
        with self.assertRaises(FileExistsError):
            core.convert_processed_video(video, shot)

    def test_source_script_and_handoff_ui(self):
        csharp = (REPO / '3 Import/Assets/FadoEXR/Editor/ReplayWindow.cs').read_text()
        self.assertIn('LoadLatestPipelineHandoff', csharp)
        self.assertIn('ValidatedInboxPath', csharp)
        self.assertIn('ImportFrames(processed);', csharp)
        self.assertIn('frames.Clear()', csharp)
        self.assertIn('ProtectGeneratedAssetsFromGit', csharp)
        self.assertIn('**/.fadoexr-inbox/', (REPO / '.gitignore').read_text())


if __name__ == '__main__':
    unittest.main()
