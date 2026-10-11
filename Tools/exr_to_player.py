#!/usr/bin/env python3
"""Explicit scene-linear EXR -> Rec709 SDR FFV1 video (lossless after tone map).
Requires ffmpeg/ffprobe on PATH. Never edits or deletes a source EXR.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def execute(command):
    result = subprocess.run(command, capture_output=True, text=True, errors='replace')
    if result.returncode:
        raise RuntimeError('Command failed:\n' + result.stderr[-6000:])
    return result.stdout


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for data in iter(lambda: f.read(1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def source_frames(clean):
    files = sorted(clean.glob('*.exr'))
    if not files:
        raise ValueError('No EXRs found in ' + str(clean))
    groups = [re.fullmatch(r'(.*?)(\d+)\.exr', f.name, re.I) for f in files]
    if any(g is None for g in groups):
        raise ValueError('All EXRs need numbered names, e.g. clean_000000.exr')
    prefixes = {g.group(1) for g in groups}
    padding = {len(g.group(2)) for g in groups}
    if len(prefixes) != 1 or len(padding) != 1:
        raise ValueError('Mixed EXR numbering/prefixes')
    indices = [int(g.group(2)) for g in groups]
    if indices != list(range(indices[0], indices[0] + len(files))):
        raise ValueError('Missing/duplicate frame numbers: refusing an incomplete clip')
    return files, next(iter(prefixes)), next(iter(padding)), indices[0]


def probe(path, count=False):
    opts = ['-count_frames'] if count else []
    output = execute(['ffprobe','-v','error'] + opts + ['-select_streams','v:0',
        '-show_entries','stream=codec_name,width,height,pix_fmt,color_primaries,color_transfer,color_space,nb_read_frames',
        '-of','json',str(path)])
    return json.loads(output)['streams'][0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('shot', type=Path, help='Shot folder containing Clean, or Clean folder itself')
    ap.add_argument('--fps', type=int, default=24)
    ap.add_argument('--tonemap', choices=['mobius','hable','reinhard','clip'], default='mobius')
    ap.add_argument('--output', type=Path, help='New .mkv output; never overwrites')
    args = ap.parse_args()
    if not 1 <= args.fps <= 240:
        raise ValueError('FPS must be 1-240')
    if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
        raise RuntimeError('Install FFmpeg and put ffmpeg and ffprobe on PATH')
    src = args.shot.resolve()
    clean = src if src.name.lower() == 'clean' else src / 'Clean'
    files, prefix, padding, first_index = source_frames(clean)
    first, last = probe(files[0]), probe(files[-1])
    if (first['width'],first['height']) != (last['width'],last['height']):
        raise ValueError('EXR dimensions differ')
    dest = args.output.resolve() if args.output else clean.parent / 'Player_Input' / (clean.parent.name + '_clean_FFV1_rec709.mkv')
    if dest.suffix.lower() != '.mkv':
        raise ValueError('Output must be .mkv')
    dest.parent.mkdir(parents=True, exist_ok=True)
    sidecar = dest.with_suffix('.json')
    tmp = dest.with_name(dest.stem + '.partial.mkv')
    if any(f.exists() for f in [dest,sidecar,tmp]):
        raise FileExistsError('Output already exists; choose another shot/output')
    # Linear Rec.709/sRGB PRIMARIES ASSUMED. Tone mapping is deliberately not reversible.
    vf = ('format=gbrpf32le,tonemap=tonemap='+args.tonemap+
          ':param=0.3:desat=0,zscale=transferin=linear:primariesin=bt709:matrixin=gbr:'+
          'transfer=bt709:primaries=bt709:matrix=bt709:range=limited,format=yuv444p10le')
    cmd = ['ffmpeg','-nostdin','-hide_banner','-loglevel','warning','-n',
          '-framerate',str(args.fps),'-start_number',str(first_index),
          '-i',str(clean / (prefix+'%0'+str(padding)+'d.exr')),
          '-frames:v',str(len(files)),'-vf',vf,'-an','-c:v','ffv1','-level','3',
          '-pix_fmt','yuv444p10le','-color_primaries','bt709','-color_trc','bt709',
          '-colorspace','bt709','-color_range','tv',str(tmp)]
    try:
        print('Assuming LINEAR Rec.709/sRGB PRIMARIES: verify your Unity working colour space!')
        print('Rendering',len(files),'frames at',args.fps,'fps ...')
        execute(cmd)
        media = probe(tmp,count=True)
        if media['codec_name'] != 'ffv1' or int(media.get('nb_read_frames',-1)) != len(files):
            raise RuntimeError('Export codec/frame count failed verification: '+str(media))
        if media.get('color_primaries') != 'bt709' or media.get('color_transfer') != 'bt709':
            raise RuntimeError('Wrong output colour tags')
        if (first['width'],first['height']) != (media['width'],media['height']):
            raise RuntimeError('Resolution mismatch')
        tmp.rename(dest)
        sidecar.write_text(json.dumps({
            'schema':1,'createdUtc':datetime.now(timezone.utc).isoformat(),
            'fps':args.fps,'inputCount':len(files),'inputFirst':str(files[0]),
            'inputLast':str(files[-1]),'inputProbe':first,'assumedInputPrimaries':'linear Rec.709/sRGB',
            'warning':'Verify HDRP working colour space. SDR tonemap is NOT reversible.',
            'filter':vf,'output':str(dest),'outputProbe':media,'outputSHA256':sha(dest)
        },indent=2)+'\n',encoding='utf-8')
        print('Ready:',dest,'Receipt:',sidecar)
    finally:
        if tmp.exists(): tmp.unlink()


if __name__ == '__main__':
    try: main()
    except (OSError,ValueError,RuntimeError,KeyError) as err:
        print('ERROR:',err,file=sys.stderr)
        sys.exit(2)
