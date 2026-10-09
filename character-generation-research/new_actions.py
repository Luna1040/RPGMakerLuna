from comfy_trials import *
ref=upload(OUT/'v2-master.png')
base='Draw exactly the SAME adult princess knight in the reference image as a new animation keyframe. Preserve her exact face, eye shape, blonde high ponytail length, blue-jeweled tiara, silver-and-gold armor design, shoulder plates, blue pleated skirt, long embroidered blue cape, boots, sword and body proportions. Same exquisite detailed 2D game illustration and colors. Fixed side/three-quarter camera facing right, no camera rotation. Full body centered on a flat uniform light gray background, ample margin for the entire sword cape hair and boots. One character only, no text, no effects, no motion blur. Change ONLY the pose: '
poses={
'walk-0':'walking contact pose. Camera-near leg strides forward to the RIGHT, straight heel touching ground; far leg stretched back LEFT with toe on ground. Sword held low in near hand pointing right. Torso upright.',
'walk-1':'walking passing pose. Camera-near leg planted vertically directly under the pelvis; far leg bent at knee, foot lifted behind and passing forward. Both knees clearly visible. Sword held low in near hand pointing right. Torso upright.',
'walk-2':'opposite walking contact pose. Camera-near leg stretched back to the LEFT with toe on ground; far leg strides forward RIGHT, straight heel touching ground. This is the opposite leg arrangement to the reference. Sword held low in near hand pointing right. Torso upright.',
'walk-3':'opposite walking passing pose. Far leg planted vertically under pelvis; camera-near leg knee raised forward RIGHT with bent knee and foot lifted. Sword held low in near hand pointing right. Torso upright.',
'slash-0':'sword attack windup. Feet wide apart and planted, near arm lifts the sword above and behind the head with bent elbow. Far hand bent near waist. Body leans slightly back.',
'slash-1':'sword overhead apex. Near arm raised high and nearly straight above head, sword points diagonally up to the right. Feet wide apart, far fist beside waist. Whole sword inside canvas.',
'slash-2':'sword attack strike. Near arm extended forward to the right at shoulder height, straight sword pointing horizontally RIGHT. Body lunges right, front knee bent, rear leg extended left. Far arm bent behind torso. Entire sword inside canvas.',
'slash-3':'sword attack follow through. Near hand low in front of hip, sword points diagonally downward right. Front knee bent, rear leg extended. Far hand close behind waist. Entire sword inside canvas.'}
for name,p in poses.items():run('v2-'+name,base+p,ref,size=(1024,1024))
