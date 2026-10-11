from pathlib import Path
try:
    from pygments import lex
    from pygments.lexers import CSharpLexer
    from pygments.token import Comment, String
except ImportError:
    lex = None
import unittest
ROOT=Path(__file__).resolve().parents[1]

class StructuralChecks(unittest.TestCase):
    def test_layout(self):
        for rel in ['1 Unity Export/Assets/FadoEXR/Editor/CapturePasses.cs',
                    '1 Unity Export/Assets/FadoEXR/Runtime/FadoFrameDriver.cs',
                    '3 Import/Assets/FadoEXR/Editor/ReplayPasses.cs',
                    '3 Import/Assets/FadoEXR/Shaders/ReplayImage.shader',
                    'Tools/exr_to_player.py',
                    '2 Player/rtx2060-installer-source/generate_installer.py']:
            self.assertTrue((ROOT/rel).exists(),rel)
    @unittest.skipIf(lex is None, 'optional pygments not installed')
    def test_brackets(self):
        opposites={')':'(',']':'[','}':'{'}
        for folder in ('1 Unity Export', '3 Import'):
          for source in (ROOT/folder/'Assets/FadoEXR').rglob('*.cs'):
            with self.subTest(source=str(source)):
              stack=[]
              for token,value in lex(source.read_text(),CSharpLexer()):
                  if token in Comment or token in String:continue
                  for char in value:
                      if char in '([{':stack.append(char)
                      if char in ')]}':
                          self.assertTrue(stack)
                          self.assertEqual(stack.pop(),opposites[char])
              self.assertFalse(stack)
    def test_progress(self):
        capture=(ROOT/'1 Unity Export/Assets/FadoEXR/Editor/CapturePasses.cs').read_text()
        replay=(ROOT/'3 Import/Assets/FadoEXR/Editor/ReplayPasses.cs').read_text()
        self.assertIn('DirectorUpdateMode.Manual',capture)
        self.assertIn('preparedFrame==time',replay)
        self.assertIn('job.volume.sharedProfile=job.profiles[index]',replay)

if __name__=='__main__':unittest.main()
