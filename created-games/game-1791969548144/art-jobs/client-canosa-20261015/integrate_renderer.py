from pathlib import Path
p=Path(__file__).resolve().parents[2]/'canosa.gd'
s=p.read_text(encoding='utf-8')
a=s.index(' draw_set_transform_matrix(Transform2D(ISO_X')
b=s.index(' if not route.is_empty():\n  draw_arc',a)
block=s[a:b]
s=s[:a]+' if client_map!=null:\n  client_map.draw_ground(self,hero)\n else:\n'+''.join(' '+line+'\n' for line in block.splitlines())+s[b:]
a=s.index(' draw_rect(mini,Color')
b=s.index(' if state != "play":',a)
block=s[a:b].replace('/WORLD*mini.size','/map_size()*mini.size')
end=block.index(' for npc in npcs:')
old=block[:end]
block=' if client_map!=null:\n  draw_texture_rect(client_map.overview,mini,false)\n else:\n'+''.join(' '+line+'\n' for line in old.splitlines())+block[end:]
s=s[:a]+block+s[b:]
p.write_text(s,encoding='utf-8')
