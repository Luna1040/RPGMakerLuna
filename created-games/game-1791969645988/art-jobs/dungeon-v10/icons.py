from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8');s=s.replace('''		var texture:=texture_file("res://assets/equipment-icons.png")
		var atlas:=AtlasTexture.new()
		atlas.atlas=texture
		var size:=Vector2(texture.get_width()/4.0,texture.get_height()/2.0)
		atlas.region=Rect2(Vector2(slot_id%4,slot_id/4)*size,size)''','''		var xiaoyao: bool=item.get("set_id","")=="xiaoyao" and FileAccess.file_exists("res://assets/xiaoyao-icons.png")
		var texture:=texture_file("res://assets/xiaoyao-icons.png" if xiaoyao else "res://assets/equipment-icons.png")
		var atlas:=AtlasTexture.new()
		atlas.atlas=texture
		var size:=Vector2(texture.get_width()/4.0,texture.get_height()/(1.0 if xiaoyao else 2.0))
		atlas.region=Rect2(Vector2([1,3,4,5].find(slot_id),0)*size,size) if xiaoyao else Rect2(Vector2(slot_id%4,slot_id/4)*size,size)''',1)
s=s.replace('if int(stats.sets.get("xiaoyao",0))>0: set_text+="\\n逍遥','if int(stats.sets.get("xiaoyao",0))>0: set_text=("" if set_text=="套装：未激活" else set_text+"\\n")+"逍遥')
p.write_text(s,encoding='utf-8')
