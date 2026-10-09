"""Independent side-facing belt-scroller assets using the user's local Flux2."""
import sys,json,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import layered_map_trial as layers
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'comfy-map-trials'/'belt-courtyard-v2'
def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    style='Environment asset only, empty scenery with absolutely NO humans, people, knights or human silhouettes. Beautiful premium hand-painted 2D fantasy action RPG environment. Side-facing horizontal belt-scrolling beat-em-up camera like classic arcade dungeon brawlers. Fine painterly material detail, elegant coherent muted golden sandstone and cool teal palette, soft afternoon light. NOT pixel art, NOT top-down, NOT isometric, no people, no lettering, no interface, no watermark. '
    tasks=[
      dict(id='backdrop',kind='scenery',width=1536,height=768,seed=20261009131,prompt=style+'A continuous distant background panorama: quiet mountain village courtyard, distant dramatic blue mountains and hazy clouds, sandstone ruined arches and medieval stone walls in the lower half, lush ivy, ornamental carved stonework, tall cypress silhouettes and weathered banners. Frontal elevation view, horizon at upper third. The bottom edge has a low straight stone foundation. Architecture is background scenery only; no large foreground objects or overhead roofs.'),
      dict(id='ground-left',kind='scenery',width=1024,height=768,seed=20261009132,prompt=style+'Ground layer ONLY filling the whole frame: richly detailed continuous broad sandstone courtyard paving with worn irregular large rectangular slabs, subtle cracks, tiny grasses in a few joints, warm mellow ochre stone with faint cool shadows. View the floor from a shallow raised side-scroller camera, NOT straight down. Slabs recede subtly toward top edge, no strong vanishing point. No skyline, buildings, trees, boxes, props or dark cast shadows. Floor must stay flat and playable.'),
      dict(id='ground-right',kind='scenery',width=1024,height=768,seed=20261009133,reference='ground-left/raw.png',prompt=style+'Create a closely matching variation of this ground layer: same sandstone courtyard paving, exactly same slab scale, color and light. Continuous paving fills entire frame. No buildings, props, plants, skyline, characters or strong cast shadows. Shallow side-scroller perspective, not overhead.'),
      dict(id='inn',kind='keyed',width=1024,height=1024,seed=20261009134,prompt=style+'Exactly ONE charming stone-and-timber fantasy inn building, entire building isolated, FRONT elevation, small amount of roof visible, beautiful carved open doorway at bottom center, blue fabric awnings, warm windows, climbing ivy, projecting beams and chimney. Building is wide and tall, facade faces viewer directly. No ground, no horizon, no extra loose objects or cast shadows. Complete uncut silhouette, 10 percent clear margin all sides. Uniform flat saturated magenta RGB(255,0,255) background in ALL empty gaps. No magenta on building.'),
      dict(id='tree',kind='keyed',width=768,height=1024,seed=20261009135,prompt=style+'Exactly ONE entire majestic broadleaf tree, frontal elevation seen from ground level, beautifully branching brown trunk with exposed roots and dense rounded green crown, detailed painterly leaves, a little moss. No ground plane, sky, grass patch, rocks or cast shadow. Full silhouette, ample empty margin. Uniform flat saturated magenta RGB(255,0,255) background, including every internal gap between branches. Tree contains no pink or magenta.'),
      dict(id='crate',kind='keyed',width=512,height=512,seed=20261009136,prompt=style+'Exactly ONE isolated closed rectangular wooden supply crate, broad front face with a shallow visible flat top, near frontal camera, brass reinforced corners, believable weathered wood and bevelled edges. Flat unobstructed top surface. No ground, floor, shadow, decoration or extra objects. Full silhouette, ample margins. Uniform flat saturated magenta RGB(255,0,255) background. No magenta on the object.')]
    layers.write(OUT/'layered-workflow.json',dict(version=2,projection='side-facing-belt',worldLocationId='location-4',tasks=tasks,coordinates={'x':'horizontal ground meters','depth':'ground depth meters','z':'height meters','screen':'x * pxPerMeter, originY + depth * depthScale - z * pxPerMeter'},pipeline=['world biome context','separate distant panorama','two ground patches','independent frontal architecture and props','validated chroma matte and enclosed gaps','foot-pivot annotations','x/depth/z collision volumes','foot-depth occlusion; jump changes visual height only'],status='planned'))
    print('PREPARED',len(tasks),flush=True)
def build_assets():
    destination=ROOT.parent/'godot-belt-map'/'assets';destination.mkdir(parents=True,exist_ok=True)
    spec=json.loads((OUT/'layered-workflow.json').read_text(encoding='utf-8'))
    for task in spec['tasks']:
        folder=OUT/task['id']
        if task['kind']=='keyed':
            qa=layers.key_asset(folder)
            shutil.copy2(folder/'rgba.png',destination/(task['id']+'.png'))
            layers.write(destination/(task['id']+'-meta.json'),qa)
            print('MATTE',task['id'],qa['accepted'],flush=True)
        else:shutil.copy2(folder/'raw.png',destination/(task['id']+'.png'))
    # Overlapping floor patches stay independently reproducible; only assembly is deterministic.
    a=np.asarray(Image.open(destination/'ground-left.png').convert('RGB')).astype(float)
    b=np.asarray(Image.open(destination/'ground-right.png').convert('RGB')).astype(float)
    overlap=160
    t=np.linspace(0,1,overlap)[None,:,None]
    combined=a
    for patch in [b,a,b]:
        seam=combined[:,-overlap:]*(1-t)+patch[:,:overlap]*t
        combined=np.concatenate([combined[:,:-overlap],seam,patch[:,overlap:]],axis=1)
    alpha=np.ones(combined.shape[:2])*255
    alpha[:90,:]=np.linspace(0,255,90)[:,None]
    Image.fromarray(np.dstack([combined,alpha]).astype('uint8'),'RGBA').save(destination/'floor.png')
    spec['status']='generated-and-matted';layers.write(OUT/'layered-workflow.json',spec)
if __name__=='__main__':
    layers.OUT=OUT
    {'prepare':prepare,'run':layers.run,'build':build_assets}[sys.argv[1]]()
