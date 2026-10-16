extends CanvasLayer
var game: Node
var main_map: RefCounted
var tree_map: RefCounted
var main_npcs: Array=[]
var main_enemies: Array[Dictionary]=[]
var portal_dialog: ConfirmationDialog
var death_dialog: AcceptDialog
var armed:=true
var pending_region:=2000
func setup(host: Node) -> void:
 game=host
 main_map=game.client_map
 layer=110
 portal_dialog=ConfirmationDialog.new()
 portal_dialog.title="区域传送"
 portal_dialog.ok_button_text="确认传送"
 portal_dialog.cancel_button_text="暂时不去"
 portal_dialog.confirmed.connect(confirm_portal)
 portal_dialog.canceled.connect(func(): game.state="play"; armed=false)
 add_child(portal_dialog)
 death_dialog=AcceptDialog.new()
 death_dialog.title="角色倒下"
 death_dialog.dialog_text="你已倒下。确认后回到城内，生命恢复。\n等级、金币、装备、任务与幻兽资料保持不变。"
 death_dialog.ok_button_text="确认回城复活"
 death_dialog.dialog_close_on_escape=false
 death_dialog.confirmed.connect(resurrect)
 death_dialog.close_requested.connect(resurrect)
 add_child(death_dialog)
func confirm_portal() -> void:
 switch_region(pending_region)
 if game.active_slot>=0: game.save_progress()
func portal_position() -> Vector2:
 return game.client_map.PORTAL
func tick() -> void:
 if game.state!="play": return
 var distance: float=game.hero.distance_to(portal_position())
 if distance>170: armed=true
 if not armed or distance>85: return
 armed=false
 pending_region=2000 if game.current_region==1000 else 1000
 game.route.clear()
 game.walking=false
 game.state="travel"
 portal_dialog.dialog_text="前往树心城？" if pending_region==2000 else "返回卡诺萨城？"
 portal_dialog.popup_centered(Vector2i(420,160))
func switch_region(region: int) -> void:
 portal_dialog.hide()
 game.close_dialog()
 if region!=game.current_region:
  if region==2000:
   main_npcs=game.npcs
   main_enemies=game.enemies
   if tree_map==null:
    tree_map=load("res://client_tree_city.gd").new()
    tree_map.setup()
   game.client_map=tree_map
   game.npcs=[]
   var empty_enemies: Array[Dictionary]=[]
   game.enemies=empty_enemies
   for actor in game.enemy_actors: actor.set_active(false)
  else:
   game.client_map=main_map
   game.npcs=main_npcs
   game.enemies=main_enemies
  game.current_region=region
 game.hero=game.map_spawn()
 for companion in game.pets: companion.pos=game.hero+Vector2(-55 if companion.role=="attack" else 55,30)
 game.mouse_enemy=-1
 game.mouse_npc=-1
 game.floats.clear()
 game.walking=false
 game.state="play"
 armed=false
 game.hint="已抵达树心城：沿树叶平台、枝干和阶梯探索；传送阵可返回卡诺萨城。" if region==2000 else "已返回卡诺萨城。"
 game.queue_redraw()
func show_death() -> void:
 if game.state=="dead": return
 game.close_dialog()
 game.state="dead"
 game.walking=false
 if game.player_ui!=null: game.player_ui.close()
 death_dialog.popup_centered(Vector2i(480,190))
func resurrect() -> void:
 if game.state!="dead": return
 death_dialog.hide()
 game.hero=game.map_spawn()
 game.hp=180
 game.route.clear()
 game.mouse_enemy=-1
 game.mouse_npc=-1
 game.walking=false
 for enemy in game.enemies: enemy.aggro=false
 for companion in game.pets: companion.pos=game.hero+Vector2(-55 if companion.role=="attack" else 55,30)
 game.state="play"
 game.hint="已回城复活：生命恢复，角色属性与进度已保留。"
 if game.active_slot>=0: game.save_progress()
 game.queue_redraw()
