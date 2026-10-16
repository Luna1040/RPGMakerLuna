extends Node2D

var hero := Vector2(640, 460)
var pet := Vector2(590, 480)
var hp := 180.0
var level := 1
var kills := 0
var wave := 0
var potions := 3
var enemies: Array[Dictionary] = []
var floats: Array[Dictionary] = []
var attack_cd := 0.0
var skill_cd := 0.0
var pet_cd := 0.0
var flash := 0.0
var flash_radius := 110.0
var state := "title"
var hint := "击败三波魔物与深渊魔王"
var font: Font = preload("res://font.ttf")
var arena: Texture2D = preload("res://assets/arena.png")

func new_run() -> void:
 hero = Vector2(640,460)
 pet = hero + Vector2(-50,25)
 hp = 180
 level = 1
 kills = 0
 wave = 0
 potions = 3
 attack_cd = 0
 skill_cd = 0
 pet_cd = 0
 flash = 0
 enemies.clear()
 floats.clear()
 state = "play"
 next_wave()

func next_wave() -> void:
 wave += 1
 hint = "清除魔物；幻兽自动协战，每五次击杀升级"
 if wave == 4:
  enemies.append({"pos":Vector2(640,240),"hp":600.0,"max":600.0,"cd":1.0,"boss":true,"clock":0.0,"warning":0.0,"target":Vector2.ZERO})
  hint = "魔王降临！离开红色蓄力圈，躲避震击"
 else:
  for i in range(4+wave*2):
   var angle := TAU*i/(4+wave*2)
   enemies.append({"pos":Vector2(640,440)+Vector2(cos(angle)*440,sin(angle)*220),"hp":55.0+wave*12,"max":55.0+wave*12,"cd":1.0,"boss":false})

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_ENTER and state == "title": new_run()
  elif event.keycode == KEY_R and state in ["win","lose"]: new_run()
  elif event.keycode == KEY_ESCAPE and state in ["play","pause"]: state = "pause" if state == "play" else "play"
  elif state == "play":
   if event.keycode == KEY_Q: strike(true)
   elif event.keycode == KEY_E and potions > 0 and hp < 180:
    potions -= 1
    hp = minf(180,hp+85)
    hint = "使用药水，恢复 85 生命"
 queue_redraw()

func strike(skill: bool) -> void:
 if (skill and skill_cd > 0) or (not skill and attack_cd > 0): return
 var damage := 55.0+level*8 if skill else 24.0+level*6
 flash_radius = 185 if skill else 110
 flash = 0.2
 if skill: skill_cd = 5
 else: attack_cd = 0.35
 for enemy in enemies:
  if enemy.hp > 0 and hero.distance_to(enemy.pos) < flash_radius:
   enemy.hp -= damage
   popup(enemy.pos,str(int(damage)),Color("ffdf92"))

func popup(pos: Vector2, text: String, color: Color) -> void:
 floats.append({"pos":pos,"text":text,"color":color,"life":0.7})

func _process(dt: float) -> void:
 if state != "play": return
 attack_cd = maxf(0,attack_cd-dt)
 skill_cd = maxf(0,skill_cd-dt)
 pet_cd = maxf(0,pet_cd-dt)
 flash = maxf(0,flash-dt)
 var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
 hero = (hero+direction.normalized()*245*dt).clamp(Vector2(65,200),Vector2(1215,690))
 pet = pet.move_toward(hero+Vector2(-45,25),300*dt)
 if Input.is_physical_key_pressed(KEY_SPACE): strike(false)
 var nearest: Dictionary = {}
 var nearest_distance := 300.0
 for enemy in enemies:
  if enemy.hp <= 0: continue
  var distance: float = pet.distance_to(enemy.pos)
  if distance < nearest_distance:
   nearest = enemy
   nearest_distance = distance
  enemy.cd -= dt
  if not enemy.boss or enemy.warning <= 0:
   if hero.distance_to(enemy.pos) > 38: enemy.pos = enemy.pos.move_toward(hero,(58 if enemy.boss else 75+wave*8)*dt)
  if hero.distance_to(enemy.pos) < 52 and enemy.cd <= 0:
   hp -= 22 if enemy.boss else 8
   enemy.cd = 1.1
   popup(hero,"受击",Color("ff7185"))
  if enemy.boss:
   enemy.clock += dt
   if enemy.clock >= 4 and enemy.warning <= 0:
    enemy.warning = 1.3
    enemy.target = hero
    enemy.clock = 0
   if enemy.warning > 0:
    enemy.warning -= dt
    if enemy.warning <= 0 and hero.distance_to(enemy.target) < 145:
     hp -= 45
     popup(hero,"震击 -45",Color("ff7185"))
 if not nearest.is_empty() and pet_cd <= 0:
  nearest.hp -= 16+level*4
  pet_cd = 0.9
  popup(nearest.pos,"幻兽协击",Color("73e7ff"))
 for i in range(enemies.size()-1,-1,-1):
  if enemies[i].hp <= 0:
   kills += 1
   enemies.remove_at(i)
   if kills % 5 == 0:
    level += 1
    hp = minf(180,hp+35)
    hint = "升级！攻击提升，恢复 35 生命"
 for i in range(floats.size()-1,-1,-1):
  floats[i].life -= dt
  floats[i].pos.y -= dt*35
  if floats[i].life <= 0: floats.remove_at(i)
 if hp <= 0:
  hp = 0
  state = "lose"
 elif enemies.is_empty():
  if wave == 4: state = "win"
  else:
   hp = minf(180,hp+25)
   next_wave()
 queue_redraw()

func text(pos: Vector2, value: String, size: int = 22, color: Color = Color("e5e2dc")) -> void:
 draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _draw() -> void:
 draw_rect(Rect2(0,0,1280,800),Color("10151f"))
 draw_rect(Rect2(40,175,1200,540),Color("243039"))
 draw_texture_rect(arena,Rect2(40,175,1200,540),false)
 draw_rect(Rect2(40,175,1200,540),Color("847057"),false,3)
 text(Vector2(40,52),"魔域 · 雷鸣试炼",32,Color("e8c889"))
 text(Vector2(40,88),"单机幻兽协战 / 三波魔物 → 深渊魔王",20)
 text(Vector2(40,127),"生命 %d / 180   等级 %d   击杀 %d" % [int(hp),level,kills])
 draw_rect(Rect2(40,142,360,12),Color("482e3e"))
 draw_rect(Rect2(40,142,hp*2,12),Color("ce5672"))
 text(Vector2(650,127),"试炼 %d / 4   Q 冷却 %.1fs   E 药水 ×%d" % [wave,skill_cd,potions])
 for enemy in enemies:
  var color := Color("a66cca") if enemy.boss else Color("c56e78")
  var radius := 35.0 if enemy.boss else 18.0
  if enemy.boss and enemy.warning > 0:
   draw_circle(enemy.target,145,Color(1,0.15,0.2,0.25))
   draw_arc(enemy.target,145,0,TAU,64,Color("ff526a"),3)
  draw_colored_polygon(PackedVector2Array([enemy.pos+Vector2(0,-radius),enemy.pos+Vector2(radius,0),enemy.pos+Vector2(0,radius),enemy.pos+Vector2(-radius,0)]),color)
  draw_rect(Rect2(enemy.pos+Vector2(-25,-radius-12),Vector2(50,5)),Color("482e3e"))
  draw_rect(Rect2(enemy.pos+Vector2(-25,-radius-12),Vector2(50*maxf(0,enemy.hp)/enemy.max,5)),color)
  if enemy.boss: text(enemy.pos+Vector2(-45,-55),"深渊魔王",18)
 draw_circle(hero,20,Color("e6c47c"))
 draw_line(hero+Vector2(12,-12),hero+Vector2(37,-38),Color("fff0c4"),5)
 text(hero+Vector2(-20,-30),"战士",16)
 draw_circle(pet,13,Color("73e7ff"))
 text(pet+Vector2(-20,30),"幻兽",16)
 if flash > 0: draw_arc(hero,flash_radius,-PI*0.8,PI*0.8,48,Color("ffe29c"),4)
 for item in floats: text(item.pos,item.text,18,item.color)
 text(Vector2(40,753),"WASD / 方向键移动   空格挥剑（可按住）   Q 魔魂爆发   E 药水   Esc 暂停",20)
 text(Vector2(40,786),hint,20,Color("e8c889"))
 if state != "play":
  draw_rect(Rect2(0,175,1280,540),Color(0.02,0.03,0.06,0.92))
  var title := "雷鸣试炼"
  var action := "按 Enter 开始"
  if state == "win":
   title = "试炼成功 · 魔王已被击败"
   action = "按 R 重新挑战"
  elif state == "lose":
   title = "战士倒下了"
   action = "按 R 重新挑战"
  elif state == "pause":
   title = "已暂停"
   action = "按 Esc 继续"
  text(Vector2(300,340),title,34,Color("e8c889"))
  text(Vector2(300,395),"幻兽自动协战，升级与清场恢复生命",22)
  text(Vector2(300,438),"靠近挥剑，Q 清理围攻，及时喝药并躲避红圈",22)
  text(Vector2(300,510),action,28,Color("73e7ff"))
  text(Vector2(300,562),"美术生成尚未完成：当前为临时几何占位",18,Color("9ba9ba"))
