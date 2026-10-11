import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
SCRIPT=Path(__file__).resolve().parents[1]/'Tools'/'exr_to_player.py'

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'requires ffmpeg')
class FFmpegTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.shot=Path(self.temp.name)/'TestShot'
        (self.shot/'Clean').mkdir(parents=True)
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=96x64:rate=24',
                        '-frames:v','3','-pix_fmt','gbrpf32le','-c:v','exr',
                        str(self.shot/'Clean'/'clean_%06d.exr')],check=True)
    def tearDown(self):self.temp.cleanup()
    def convert(self):
        return subprocess.run([sys.executable,str(SCRIPT),str(self.shot)],capture_output=True,text=True)
    def test_roundtrip(self):
        exrs=sorted((self.shot/'Clean').glob('*.exr'))
        hashes=[hashlib.sha256(p.read_bytes()).hexdigest() for p in exrs]
        result=self.convert()
        self.assertEqual(result.returncode,0,result.stderr)
        receipt=json.loads((self.shot/'Player_Input'/'TestShot_clean_FFV1_rec709.json').read_text())
        self.assertEqual(receipt['inputCount'],3)
        self.assertEqual(receipt['outputProbe']['codec_name'],'ffv1')
        self.assertEqual(receipt['outputProbe']['nb_read_frames'],'3')
        self.assertEqual(receipt['outputProbe']['color_transfer'],'bt709')
        self.assertEqual(hashes,[hashlib.sha256(p.read_bytes()).hexdigest() for p in exrs])
        self.assertNotEqual(self.convert().returncode,0,'must reject overwrite')
    def test_gap(self):
        (self.shot/'Clean'/'clean_000002.exr').unlink()
        failure=self.convert()
        self.assertNotEqual(failure.returncode,0)
        self.assertIn('Missing/duplicate frame',failure.stderr)
        self.assertFalse(list(self.shot.rglob('*.mkv')))

if __name__=='__main__':unittest.main()
