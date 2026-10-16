from pathlib import Path
p=Path('equipment_system.gd');s=p.read_text(encoding='utf-8');s=s.replace('"hp":40}}}}','"hp":40}}},"xiaoyao":{"name":"逍遥","pieces":4,"bonuses":{2:{"attack":12,"defense":8,"hp":60},4:{"attack":25,"defense":15,"hp":120}}}}',1)
s=s.replace('\tvar factor: int=QUALITY_FACTORS[quality]','\tif set_id=="xiaoyao":\n\t\tif not slot in [1,3,4,5]: return {}\n\t\tquality=3; level=10\n\tvar factor: int=QUALITY_FACTORS[quality]',1)
s=s.replace('("仙缘" if set_id=="xianyuan" else QUALITY_NAMES[quality])','("仙缘" if set_id=="xianyuan" else ("逍遥" if set_id=="xiaoyao" else QUALITY_NAMES[quality]))')
s=s.replace('\telse: text+="\\n散装备"','\telif item.get("set_id","")=="xiaoyao": text+="\\n逍遥套装（共4件，10级可装备）\\n2件：攻击+12 防御+8 气血+60\\n4件额外：攻击+25 防御+15 气血+120"\n\telse: text+="\\n散装备"')
p.write_text(s,encoding='utf-8')
