"""Authored selections and local alpha rules after source-frame review."""
raise SystemExit("Historical rejected candidate script. Use canonical export-specs.json; do not rerun.")
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import npc_roster_v1 as n
s=n.read_json(n.SPECS)
def select(k,a,indices,durations,event=None):
    item=s.setdefault(k,{}).setdefault(a,{})
    item.update(indices=indices,durations=durations,review_status='needs_visual_review')
    if event is not None: item['event_ms']=sum(durations[:indices.index(event)])
    return item
def fx(item,index,polygons,rects=None,background=None):
    rule={'mode':'glow_from_source','coverage_rects':rects or [[0,0,768,768]],'protect_polygons':polygons}
    if background: rule['background_reference']=background
    item.setdefault('alpha_cleanup',{})[str(index)]=rule

select('caster','hurt',[8,10,12,14,16,20,24,28,40,80,104,108,112,116,120],[20,20,25,25,30,30,25,25,25,25,35,35,35,35,35])
ca=s['caster']['attack']
# Only the empty space around the open palm is recomposited; costume light remains painted.
for idx in [34,38]:
    fx(ca,idx,[],[[475,200,640,390]])
for idx in [40,42,46]:
    fx(ca,idx,[[(440,252),(480,260),(526,256),(553,244),(570,249),(570,270),(548,285),(505,316),(475,314),(495,283),(447,280)]],[[460,180,670,350]])
fx(ca,38,[[(423,276),(439,272),(450,265),(461,263),(477,276),(486,300),(470,325),(444,343),(444,318),(455,300),(427,298)]],[[425,215,640,375]])
fx(ca,40,[[(435,265),(489,266),(510,258),(532,266),(524,280),(514,289),(491,307),(458,324),(469,303),(484,283),(443,283)]],[[432,200,670,360]])
fx(ca,42,[[(436,260),(481,266),(511,262),(531,248),(535,268),(516,289),(475,312),(494,285),(448,279)]],[[434,200,670,350]])
fx(ca,46,[],[[573,195,670,300]])
for idx in [38,40,42]:
    ca['alpha_cleanup'][str(idx)]['protect_polygons'].append([(350,190),(419,190),(428,251),(434,285),(450,317),(451,366),(350,366)])
fx(ca,46,[],[[548,205,650,295]])
ca['alpha_cleanup']['46']['protect_capsules']=[[551,262,595,261,5]]

ea=select('elite','attack',[12,20,24,28,32,36,40,48,54,58,60,62,64,66,92,108,120],[35,40,35,35,35,35,40,50,60,60,25,20,40,40,40,40,40],64)
fx(ea,24,[[(360,476),(410,480),(478,651),(448,658)],[(388,500),(431,505),(471,624),(388,624)]],[[438,490,768,710]])
fx(ea,28,[[(276,484),(335,488),(327,648),(278,650)],[(393,489),(450,490),(476,628),(394,629)]],[[0,495,768,730]])
fx(ea,32,[[(159,336),(243,276),(333,219),(426,256),(447,495),(476,628),(397,632),(388,506),(343,503),(324,650),(279,650),(288,490),(160,470)],[(60,129),(218,125),(226,226),(148,282),(64,238)]],[[0,0,768,768]])
fx(ea,36,[],[[0,0,239,320],[0,320,154,768]])
fx(ea,40,[],[[0,0,260,185]])
fx(ea,60,[[(413,18),(545,24),(554,161),(476,184),(408,123)]],[[0,0,768,222]])
fx(ea,62,[[(597,254),(665,259),(762,304),(765,342),(704,385),(630,384),(644,353),(627,322),(594,306)]],[[0,0,768,238],[555,238,768,430]])
for idx in [64,66]:
    fx(ea,idx,[[(600,444),(637,443),(665,484),(665,559),(637,605),(590,585),(548,534),(553,512),(597,527),(613,499),(581,486)],[(495,442),(605,478),(601,508),(487,467)]],[[0,0,768,235],[520,235,768,768]])
ea['alpha_cleanup']['24']['protect_polygons']=[[(378,539),(387,560),(426,609),(464,645),(462,625),(444,608),(425,572),(407,552)],[(400,525),(433,536),(432,579),(436,599),(450,613),(440,621),(399,621),(393,595)]]
ea['alpha_cleanup']['24']['protect_capsules']=[[389,487,432,583,8]]
ea['alpha_cleanup']['28']['protect_polygons']=[[(292,486),(335,488),(330,526),(316,579),(321,608),(321,632),(306,646),(286,641),(283,626),(288,604),(290,548)],[(412,501),(444,506),(435,539),(432,580),(445,602),(470,615),(470,622),(428,624),(400,619),(396,600),(405,554)]]
ea['alpha_cleanup']['28']['coverage_rects']=[[0,550,768,730],[0,495,275,550],[470,495,768,550]]
ea['alpha_cleanup']['60']['protect_polygons']=[[(482,33),(514,45),(538,96),(539,151),(516,128),(508,156),(477,170),(469,138),(446,125),(425,139),(418,124),(427,99),(453,94),(470,93),(480,62)]]
ea['alpha_cleanup']['60']['protect_capsules']=[[478,149,519,226,10]]
ea['alpha_cleanup']['62']['protect_capsules']=[[543,370,650,310,9]]
# Remove the inactive opening and long still tail of the recoil.
select('elite','hurt',[16,18,20,22,24,28,34,44,50,56,60,66,74,82],[20,20,25,25,30,30,30,30,30,30,30,30,30,30])
select('boss','stand',list(range(50,113,3)),[125]*21)
select('boss','hurt',[16,18,20,22,24,28,36,48,56,64,70,76,82,94],[20,20,25,25,30,30,30,30,30,30,35,35,35,35])
ba=select('boss','attack',[28,32,36,40,44,48,54,58,60,62,64,65,67,70,80,92,108,120],[40,45,45,45,45,55,65,65,25,20,18,35,35,35,45,45,45,45],65)
# Broad source illumination is background, not a character part. Use the
# pre-swing background in the upper-left corner, and preserve solid steel.
background=n.source_paths('boss','attack')[28].relative_to(n.ROOT/'output').as_posix()
blades={36:[(485,336,744,251,10)],40:[(523,289,615,67,10)],44:[(448,280,400,41,9)],48:[(435,271,240,85,9)],54:[(434,275,214,186,9)],58:[(434,274,258,183,10)],60:[(440,277,347,62,10)],62:[(493,279,482,57,10)],64:[(531,310,714,169,10)],65:[(521,353,759,270,10)],67:[(470,430,744,502,12)],70:[(400,468,439,645,11)]}
for idx in ba['indices']:
    if idx in [28,32,80,92,108,120]:
        ba.setdefault('alpha_cleanup',{})[str(idx)]={'mode':'clear_background_regions','rects':[[0,0,282,270]]}
        continue
    rects=[[0,0,768,218],[510,218,768,768]]
    if idx in [48,54,58,60]: rects=[[0,0,768,205],[0,205,336,288],[510,205,768,768]]
    if idx==36: rects=[[0,0,290,270],[510,218,768,430]]
    if idx==40: rects=[[0,0,290,270],[555,0,768,420]]
    if idx==44: rects=[[0,0,768,210],[470,210,768,300]]
    if idx==62: rects=[[0,0,768,215]]
    if idx==64: rects=[[0,0,768,218],[530,218,768,768]]
    if idx==65: rects=[[0,0,768,215],[552,215,768,768]]
    if idx==67: rects=[[0,0,768,215],[520,215,768,768],[300,650,520,768]]
    if idx==70: rects=[[0,0,768,215],[510,215,768,768],[280,570,510,768]]
    fx(ba,idx,[],rects,background)
    rule=ba['alpha_cleanup'][str(idx)]
    rule['background_rects']=[[0,0,282,270]]
    rule['black_level']=8
    rule['protect_capsules']=blades.get(idx,[])
    if idx==70:
        rule['protect_polygons']=[[(319,568),(358,567),(365,650),(321,654)],[(417,555),(455,555),(473,630),(411,633)]]
for action in ['stand','walk','attack','hurt']:
    item=s['boss'].setdefault(action,{})
    item['pivot']=[232,643] if action=='stand' else [389,643]
    item['scale']=0.6533333333333333 if action=='stand' else 0.6774193548387096
# Continuous coverage outside the solid character avoids rectangle seams in
# broad sword trails. This source's accidental corner light stays below 60.
for idx in ba['indices']:
    if idx in [28,32,80,92,108,120]:
        ba['alpha_cleanup'][str(idx)]={'mode':'clear_background_regions','rects':[[0,0,300,320]]}
        continue
    if idx in [36,40,44]:
        body=[(340,205),(430,203),(455,258),(528,280),(547,326),(478,369),(454,486),(467,600),(476,635),(414,638),(404,553),(371,609),(371,650),(323,653),(329,590),(344,538),(280,555),(178,536),(182,465),(271,348),(320,272)]
    elif idx in [48,54,58,60,62]:
        body=[(344,220),(420,216),(455,256),(472,295),(469,326),(448,380),(451,525),(469,607),(475,636),(414,638),(398,563),(372,612),(371,651),(320,655),(331,571),(347,522),(271,555),(174,509),(92,455),(112,413),(240,356),(312,292)]
    else:
        body=[(350,209),(433,207),(463,264),(489,297),(525,321),(534,363),(476,382),(490,494),(474,538),(458,586),(474,630),(416,634),(408,578),(373,603),(369,650),(319,655),(321,608),(346,549),(276,543),(218,510),(165,437),(171,365),(278,304),(328,269)]
    fx(ba,idx,[body])
    ba['alpha_cleanup'][str(idx)]['black_level']=60
    ba['alpha_cleanup'][str(idx)]['protect_capsules']=[[*line[:4],4] for line in blades.get(idx,[])]
n.write_json(n.SPECS,s)
print('Saved authored candidate selections; visual approval remains pending.')
