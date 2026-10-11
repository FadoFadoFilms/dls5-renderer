"""Repository policy/packaging checks; not a Windows runtime integration test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'Tools' / 'Ensure-Windows-Dependencies.ps1'
START = ROOT / 'START-FADOEXR-MANAGER.cmd'
SETUP = ROOT / 'Tools' / 'SETUP-DEPENDENCIES.cmd'
CHECK = ROOT / 'Tools' / 'CHECK-DEPENDENCIES.cmd'


class WindowsDependenciesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT.read_text(encoding='utf-8')
        cls.start = START.read_text(encoding='utf-8')

    def test_programs_are_checked_before_launch(self):
        self.assertIn('Find-Python313', self.source)
        self.assertIn('Find-MediaTools', self.source)
        self.assertIn('import tkinter', self.source)
        self.assertIn('Manager\\fadoexr_manager.py', self.source)
        self.assertIn('if (-not $python -or -not $media)', self.source)

    def test_installs_approved_package_ids_only(self):
        self.assertIn("WinGet-Install $winget 'Python.Python.3.13'", self.source)
        self.assertIn("WinGet-Install $winget 'Gyan.FFmpeg'", self.source)
        self.assertIn("'--accept-source-agreements'", self.source)
        self.assertIn("'--source', 'winget'", self.source)
        self.assertNotIn('--ignore-security-hash', self.source)
        self.assertNotIn('--ignore-local-archive-malware-scan', self.source)

    def test_media_filters_and_probe_checked(self):
        for capability in ('ffprobe.exe', 'encoder=ffv1', 'decoder=exr', 'zscale', 'tonemap'):
            with self.subTest(capability=capability):
                self.assertIn(capability, self.source)

    def test_read_only_check_and_managed_ffmpeg_upgrade(self):
        self.assertIn('if ($CheckOnly -and ($InstallMissing -or $UpgradeFFmpeg -or $LaunchManager))', self.source)
        self.assertIn('Has-WingetFFmpeg $winget', self.source)
        self.assertIn('Gyan.FFmpeg', self.source)
        self.assertIn('TotalDays -ge 7', self.source)
        self.assertIn('WinGet-Command $winget', self.source)
        self.assertNotIn('setx', self.source.lower())

    def test_launcher_and_manual_cmds(self):
        self.assertIn('Ensure-Windows-Dependencies.ps1', self.start)
        self.assertIn('-InstallMissing -UpgradeFFmpeg -LaunchManager', self.start)
        self.assertIn('exit /b 1', self.start)
        self.assertIn('-CheckOnly', CHECK.read_text(encoding='utf-8'))
        setup = SETUP.read_text(encoding='utf-8')
        self.assertIn('-InstallMissing -UpgradeFFmpeg -ForceUpgradeCheck', setup)
        self.assertNotIn('-InstallMissing', CHECK.read_text(encoding='utf-8'))

    def test_documented_support_and_no_silent_custom_replacement(self):
        self.assertIn('custom installation intact', self.source)
        text = (ROOT / 'Tools' / 'README-WINDOWS-SETUP.md').read_text(encoding='utf-8')
        self.assertIn('Python **3.13.x**', text)
        self.assertIn('newest stable version', text)
        self.assertIn('dependency-logs', text)


if __name__ == '__main__':
    unittest.main()
