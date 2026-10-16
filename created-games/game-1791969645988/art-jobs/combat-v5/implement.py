from pathlib import Path
p=Path('main.gd');s=p.read_text(encoding='utf-8')
s=s.replace('const MONSTER_XP := [100,150,150]','const MONSTER_LEVELS := [5,7,9]\nconst MONSTER_XP := [60,84,108]\nconst FIELD_COMPLETION_XP := 248\nconst DUNGEON_REWARD_MULTIPLIER := 5')
s=s.replace('if int(character.field_quest)==4: earned+=100','if int(character.field_quest)==4: earned+=FIELD_COMPLETION_XP')
s=s.replace('历练奖励：100经验，100金币','历练奖励：248经验，100金币')
s=s.replace('add_experience(100)\n\t\tcharacter.gold','add_experience(FIELD_COMPLETION_XP)\n\t\tcharacter.gold')
s=s.replace('\telif mode=="battle":\n\t\tbattle_clock+=delta\n\t\tif battle_clock>=0.8:\n\t\t\tbattle_clock=0\n\t\t\tbattle_turn()','\telif mode=="battle":\n\t\tadvance_battle(delta)')
s=s.replace('MONSTERS[i]+(" · 已击杀" if cleared else " ×3")','MONSTERS[i]+" Lv.%d" % MONSTER_LEVELS[i]+(" · 已击杀" if cleared else " ×3")')
s=s.replace('\tactor(screen,0,Vector2(320,570),character.name,2.4)\n\tfor i in range(3): actor(screen,7,Vector2(850+i*100,500+i*50),"妖狼",1.6)','''\tbattle_player=actor(screen,0,Vector2(320,570),character.name,2.4)
\tbattle_enemies=[]
\tfor i in range(3): battle_enemies.append(actor(screen,7,Vector2(850+i*100,500+i*50),"妖狼 Lv.%d" % MONSTER_LEVELS[group],1.6))
\tbattle_effects=Control.new()
\tbattle_effects.name="BattleEffects"
\tbattle_effects.mouse_filter=Control.MOUSE_FILTER_IGNORE
\tscreen.add_child(battle_effects)
\tphase=0
\tphase_time=0
\tround_active=false
\tquick_mode=false
\tplayer_hit_done=false
\tenemy_hit_done=false
\tbattle_home=[battle_player.position]
\tbattle_static=[]
\tfor holder in [battle_player]+battle_enemies:
\t\tvar portrait: Sprite2D=holder.get_node("Portrait")
\t\tbattle_static.append({"texture":portrait.texture,"position":portrait.position,"scale":portrait.scale})
\tfor enemy in battle_enemies: battle_home.append(enemy.position)
\tactions={"sword":load_battle_action("sword"),"bite":load_battle_action("bite")}
\tquick_button=Button.new()
\tquick_button.name="QuickBattle"
\tquick_button.text="快速战斗"
\tquick_button.position=Vector2(1020,30)
\tquick_button.size=Vector2(220,52)
\tquick_button.pressed.connect(quick_battle)
\tscreen.add_child(quick_button)''')
a=s.index('func battle_turn() -> void:');b=s.index('\nfunc settle_battle()',a)
s=s[:a]+'''# Both presentation and quick combat call these same deterministic hit rules.
func begin_round() -> void:
\tif round_active: return
\tround_number+=1
\tround_active=true
\tplayer_hit_done=false
\tenemy_hit_done=false

func resolve_player_hit(visual: bool) -> void:
\tif player_hit_done or enemy_hp<=0: return
\tplayer_hit_done=true
\tvar damage:=mini(enemy_hp,32+int(character.level)*3+(18 if round_number%3==0 else 0))
\tenemy_hp-=damage
\tif not quick_mode: battle_log.append_text("第%d回合 · 挥剑造成%d伤害。\\n" % [round_number,damage])
\tif visual:
\t\tshow_damage(battle_enemies[target_enemy()].position,damage,false)
\t\tshow_impact(battle_enemies[target_enemy()].position,false)
\tupdate_combat()

func resolve_enemy_hit(visual: bool) -> void:
\tif enemy_hit_done or enemy_hp<=0 or combat_hp<=0: return
\tenemy_hit_done=true
\tvar damage:=mini(combat_hp,12+battle_group*7)
\tcombat_hp-=damage
\tif not quick_mode: battle_log.append_text("妖狼撕咬，造成%d伤害。\\n" % damage)
\tif visual:
\t\tshow_damage(battle_player.position,damage,true)
\t\tshow_impact(battle_player.position,true)
\tupdate_combat()

func battle_turn() -> void:
\tif mode!="battle": return
\tbegin_round()
\tresolve_player_hit(false)
\tresolve_enemy_hit(false)
\tround_active=false
\tif enemy_hp==0 or combat_hp==0: settle_battle()

func quick_battle() -> void:
\tif mode!="battle" or settled: return
\tquick_mode=true
\tquick_button.disabled=true
\tfor child in battle_effects.get_children():
\t\tbattle_effects.remove_child(child)
\t\tchild.queue_free()
\t# Complete any partly presented round without repeating an applied hit.
\twhile mode=="battle": battle_turn()
\tbattle_log.text="快速战斗结束 · 共%d回合\\n%s\\n剩余气血 %d" % [round_number,"战斗胜利" if enemy_hp==0 else "战斗失利",combat_hp]

func encounter_rewards(level: int, count: int, kind: String="wild") -> Dictionary:
\tvar multiplier:=DUNGEON_REWARD_MULTIPLIER if kind=="dungeon" else 1
\treturn {"xp":maxi(1,level)*4*maxi(1,count)*multiplier,"gold":maxi(1,level)*2*maxi(1,count)*multiplier}
'''+s[b:]
s=s.replace('\tmode="result"\n\tvar won', '\tmode="result"\n\tif is_instance_valid(quick_button): quick_button.disabled=true\n\treset_battle_poses()\n\tvar rewards:=encounter_rewards(MONSTER_LEVELS[battle_group],3)\n\tvar won')
s=s.replace('character.gold=int(character.gold)+30\n\t\t\tadd_experience(MONSTER_XP[battle_group])','character.gold=int(character.gold)+int(rewards.gold)\n\t\t\tadd_experience(int(rewards.xp))')
s=s.replace('"获得%d经验、30金币。当前等级%d。确认后返回原位置。" % [MONSTER_XP[battle_group],character.level]','"击杀3只%d级野怪 · 获得%d经验、%d金币。\\n共%d回合，当前等级%d。确认后返回地图。" % [MONSTER_LEVELS[battle_group],rewards.xp,rewards.gold,round_number,character.level]')
s+='''
var battle_player: Control
var battle_enemies: Array=[]
var battle_effects: Control
var battle_home: Array=[]
var battle_static: Array=[]
var quick_button: Button
var phase:=0
var phase_time:=0.0
var round_active:=false
var player_hit_done:=false
var enemy_hit_done:=false
var quick_mode:=false
var actions: Dictionary={}
const DamageNumber=preload("res://damage_number.gd")

func load_battle_action(id: String) -> Dictionary:
\tvar directory: String="res://assets/animations/"+id
\tif not FileAccess.file_exists(directory+"/action.json"): return {}
\tvar spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/action.json"))
\tvar textures: Array=[]
\tfor frame in spec.frames: textures.append(texture_file(directory+"/"+frame.file))
\tspec.textures=textures
\treturn spec

func target_enemy() -> int: return (maxi(round_number,1)-1)%3

func phase_duration() -> float:
\tif phase==6: return 1.35
\tif phase in [1,4]:
\t\tvar action: Dictionary=actions.get("sword" if phase==1 else "bite",{})
\t\treturn float(action.get("duration_ms",640))/1000.0
\treturn 0.22

func advance_battle(delta: float) -> void:
\tvar remaining:=delta
\twhile remaining>0.00001 and mode=="battle":
\t\tif phase==0: begin_round()
\t\tvar duration:=phase_duration()
\t\tvar step:=minf(remaining,duration-phase_time)
\t\tphase_time+=step
\t\tremaining-=step
\t\tshow_battle_phase(clampf(phase_time/duration,0,1))
\t\tif phase_time>=duration-0.00001:
\t\t\tphase_time=0
\t\t\tif phase==6:
\t\t\t\tsettle_battle()
\t\t\t\treturn
\t\t\tif phase==2 and enemy_hp==0: phase=6
\t\t\telif phase==5:
\t\t\t\tround_active=false
\t\t\t\tphase=6 if combat_hp==0 else 0
\t\t\telse: phase+=1

func show_battle_phase(progress: float) -> void:
\tvar target:=target_enemy()
\tvar enemy: Control=battle_enemies[target]
\tvar player_start: Vector2=battle_home[0]
\tvar enemy_start: Vector2=battle_home[target+1]
\tvar player_strike: Vector2=enemy_start+Vector2(-120,25)
\tvar enemy_strike: Vector2=player_start+Vector2(125,-5)
\tmatch phase:
\t\t0: battle_player.position=player_start.lerp(player_strike,1.0-pow(1.0-progress,3))
\t\t1:
\t\t\tplay_attack_pose(battle_player,"sword",phase_time,0)
\t\t\tif phase_time>=float(actions.get("sword",{}).get("event_ms",300))/1000.0: resolve_player_hit(true)
\t\t2:
\t\t\trestore_battle_actor(battle_player,0)
\t\t\tbattle_player.position=player_strike.lerp(player_start,progress)
\t\t3: enemy.position=enemy_start.lerp(enemy_strike,1.0-pow(1.0-progress,3))
\t\t4:
\t\t\tplay_attack_pose(enemy,"bite",phase_time,target+1)
\t\t\tif phase_time>=float(actions.get("bite",{}).get("event_ms",300))/1000.0: resolve_enemy_hit(true)
\t\t5:
\t\t\trestore_battle_actor(enemy,target+1)
\t\t\tenemy.position=enemy_strike.lerp(enemy_start,progress)

func play_attack_pose(holder: Control, action_id: String, elapsed: float, actor_index: int) -> void:
\tvar portrait: Sprite2D=holder.get_node("Portrait")
\tvar action: Dictionary=actions.get(action_id,{})
\tif action.is_empty():
\t\tportrait.rotation=sin(elapsed/0.64*PI)*(-0.18 if action_id=="bite" else 0.18)
\t\treturn
\tvar frame_index:=0
\tvar milliseconds:=elapsed*1000
\tfor i in range(action.frames.size()):
\t\tframe_index=i
\t\tif milliseconds<float(action.frames[i].duration_ms): break
\t\tmilliseconds-=float(action.frames[i].duration_ms)
\tportrait.texture=action.textures[frame_index]
\tportrait.centered=false
\tportrait.scale=Vector2.ONE*float(action.scale)
\tportrait.position=-Vector2(action.pivot[0],action.pivot[1])*float(action.scale)

func restore_battle_actor(holder: Control, index: int) -> void:
\tif not is_instance_valid(holder) or index>=battle_static.size(): return
\tvar portrait: Sprite2D=holder.get_node("Portrait")
\tportrait.texture=battle_static[index].texture
\tportrait.position=battle_static[index].position
\tportrait.scale=battle_static[index].scale
\tportrait.rotation=0
\tportrait.centered=true

func reset_battle_poses() -> void:
\tif not is_instance_valid(battle_player): return
\trestore_battle_actor(battle_player,0)
\tbattle_player.position=battle_home[0]
\tfor i in range(battle_enemies.size()):
\t\trestore_battle_actor(battle_enemies[i],i+1)
\t\tbattle_enemies[i].position=battle_home[i+1]

func show_damage(foot: Vector2, damage: int, against_player: bool) -> void:
\tvar number:=DamageNumber.new()
\tnumber.name="DamageNumber"
\tnumber.text="-%d" % damage
\tnumber.position=foot+Vector2(-80,-155)
\tnumber.size=Vector2(160,50)
\tnumber.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
\tnumber.add_theme_font_size_override("font_size",36)
\tnumber.add_theme_color_override("font_color",Color("ff816c") if against_player else Color("ffe989"))
\tnumber.add_theme_color_override("font_shadow_color",Color.BLACK)
\tnumber.add_theme_constant_override("shadow_offset_x",3)
\tnumber.add_theme_constant_override("shadow_offset_y",3)
\tbattle_effects.add_child(number)

func show_impact(foot: Vector2, bite: bool) -> void:
\tvar effect:=Node2D.new()
\teffect.position=foot+Vector2(0,-65)
\tbattle_effects.add_child(effect)
\tfor i in range(2):
\t\tvar stroke:=Line2D.new()
\t\tstroke.width=4
\t\tstroke.default_color=Color("ffb5a0") if bite else Color("eafcff")
\t\tstroke.points=PackedVector2Array([Vector2(-25,-12+i*24),Vector2(-12,10-i*10),Vector2(0,-6),Vector2(12,10-i*10),Vector2(25,-12+i*24)]) if bite else PackedVector2Array([Vector2(-40,-35+i*65),Vector2(40,35-i*65)])
\t\teffect.add_child(stroke)
\tvar tween:=create_tween()
\ttween.tween_property(effect,"modulate:a",0.0,0.25)
\ttween.tween_callback(effect.queue_free)
'''
p.write_text(s,encoding='utf-8')
