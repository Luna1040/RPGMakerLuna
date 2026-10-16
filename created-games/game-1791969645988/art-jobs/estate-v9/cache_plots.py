from pathlib import Path
p=Path('estate_ui.gd');s=p.read_text(encoding='utf-8');s=s.replace('var plots: Array=[]','var plots: Array=[]\nvar plot_textures: Array=[]',1);s=s.replace('''			var atlas:=AtlasTexture.new()
			atlas.atlas=game.texture_file("res://assets/estate-plots.png")
			atlas.region=[Rect2(0,0,484,512),Rect2(499,0,500,512),Rect2(1014,0,522,512)][stage]
			plots[i].get_node("PlotArt").texture=atlas''','''			if plot_textures.is_empty():
				var source: Texture2D=game.texture_file("res://assets/estate-plots.png")
				for region in [Rect2(0,0,484,512),Rect2(499,0,500,512),Rect2(1014,0,522,512)]:
					var atlas:=AtlasTexture.new()
					atlas.atlas=source
					atlas.region=region
					plot_textures.append(atlas)
			plots[i].get_node("PlotArt").texture=plot_textures[stage]''');p.write_text(s,encoding='utf-8')
