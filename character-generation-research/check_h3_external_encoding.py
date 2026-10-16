"""Exercise the actual patched shot writer on four tiny CPU frames."""
import ast,sys,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CORE=next((ROOT/'h3-runtime').glob('ComfyUI-*'))
for path in (ROOT/'h3-runtime/deps',ROOT/'h3-comparison-deps',CORE):sys.path.insert(0,str(path))
import torch,folder_paths
folder_paths.set_output_directory(str(ROOT/'h3-comparison/qa'))
source=ROOT/'h3-community-nodes/ComfyUI-H3-Multishot/h3_multishot_utils.py'
tree=ast.parse(source.read_text(encoding='utf-8'))
fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='_write_shot_mp4')
scope={'torch':torch}
exec(compile(ast.Module(body=[fn],type_ignores=[]),str(source),'exec'),scope)
out=scope['_write_shot_mp4'](torch.rand(4,64,64,3),None,24000,'codec-check/ffmpeg','small encode passed','CHECK')
if not out:raise RuntimeError('External encoding failed')
info=json.loads(subprocess.check_output([r'C:\ffmpeg\bin\ffprobe.exe','-v','error','-select_streams','v:0','-show_entries','stream=nb_frames,width,height','-of','json',out]))
assert info['streams'][0]['nb_frames']=='4',info
print('EXTERNAL_ENCODING_VERIFIED',info)
