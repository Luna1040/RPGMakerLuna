from pathlib import Path
import re,json,struct
ROOT=Path(r'Z:\Program Files (x86)\NetDragon\魔域')
PROJECT=Path(__file__).resolve().parents[1]
JOB=PROJECT/'art-jobs/client-roles-20261015'
text=(ROOT/'ini/npc.ini').read_text(encoding='gb18030')
positions=(ROOT/'ini/aitalknpc.ini').read_text(encoding='gb18030')
records=[]
for npc_id in [1301,1205,1817,1206,1210]:
 section=re.search(r'\[NpcType'+str(npc_id)+r'\](.*?)(?=\[|$)',text,re.S).group(1)
 fields=dict(re.findall(r'^([^\r\n=]+)=(.*)',section,re.M))
 fields={k:v.strip() for k,v in fields.items()}
 pos=re.search(r'npc='+str(npc_id)+r'\s+map=1000\s+x=(\d+)\s+y=(\d+)',positions)
 x,y=map(int,pos.groups())
 records.append({'id':npc_id,'name':fields['Name'],'note':fields.get('Note',''),'client_model':fields['SimpleObjID'],'client_grid':[x,y],'map':1000,'pos':[(x-y)*10+4200,(x+y)*5-1900],'position_status':'relative isometric placement; origin calibration provisional','dialog_status':'original branching dialogue unavailable; role description only'})
(PROJECT/'assets/client_roles/npcs.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'npc-evidence.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
b=(ROOT/'ini/CreateRole.fdb').read_bytes()
roles=[]
for i in range(4):
 key,offset=struct.unpack_from('<II',b,92+i*8)
 roles.append({'key':key,'values':struct.unpack_from('<12I',b,offset)})
(JOB/'create-role-evidence.json').write_text(json.dumps(roles,indent=2),encoding='utf-8')
for filename in ['NewPlayerTask.ini','aitalknpc.ini']:
 (JOB/filename.replace('.ini','-utf8.txt')).write_text((ROOT/'ini'/filename).read_text(encoding='gb18030'),encoding='utf-8')
print('Catalogued five original NPCs and warrior/mage create-role records')
