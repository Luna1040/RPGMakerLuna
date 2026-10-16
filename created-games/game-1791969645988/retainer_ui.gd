extends RefCounted
const R=preload("res://retainer_system.gd")
var game
var notice:=""
var cooldown_label: Label
var refresh_button: Button
var dismiss_uid:=""
func build(owner_game, content: VBoxContainer) -> void:
	game=owner_game
	game.menu_window.position=Vector2(170,80); game.menu_window.custom_minimum_size=Vector2(940,630); game.menu_window.size=Vector2(940,630)
	content.add_theme_constant_override("separation",4)
	if int(game.character.level)<10:
		game.label_text(content,"达到10级后可招募散修，青云宗的散修执事会为你介绍。",20); return
	var state: Dictionary=game.character.retainers
	game.label_text(content,notice if not notice.is_empty() else "点击备战散修随行；点击随行散修撤回。悬停查看成长属性。",15)
	group(content,"随行散修 %d/%d" % [state.following.size(),R.follow_limit(game.character)],state.following,4,0)
	group(content,"备战散修 %d/%d（等级每十级增加2位，最多8位）" % [state.reserve.size(),R.reserve_limit(game.character)],state.reserve,8,1)
	var line:=HBoxContainer.new(); content.add_child(line)
	cooldown_label=game.label_text(line,"",16)
	refresh_button=game.button(line,"免费全场刷新",refresh_offers)
	refresh_button.custom_minimum_size.y=30
	var paid: Button=game.button(line,"快速刷新 · 12灵石",refresh_paid)
	paid.custom_minimum_size.y=30
	paid.disabled=int(game.character.stones)<12
	group(content,"可招募散修 · 招募后留空，手动全场刷新",state.offers,12,2)
	update_cooldown()
func group(content: Node, title: String, units: Array, count: int, kind: int) -> void:
	game.label_text(content,title,16)
	var grid:=GridContainer.new(); grid.columns=4; grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",4); content.add_child(grid)
	for i in range(count):
		var cell:=HBoxContainer.new(); cell.custom_minimum_size=Vector2(214,62); grid.add_child(cell)
		if i>=units.size() or units[i].is_empty():
			var blank: Button=game.button(cell,"空缺 · 等待刷新" if kind==2 else "空位",func(): pass); blank.disabled=true; blank.custom_minimum_size=Vector2(214,62); continue
		var unit: Dictionary=units[i]
		var b:=Button.new(); b.custom_minimum_size=Vector2(166 if kind==1 else 214,62); b.add_theme_font_size_override("font_size",13)
		b.text="%s Lv.%d\n%s · %s" % [unit.name,unit.level,R.ROOT_NAMES[int(unit.root)],["撤回备战","设为随行","招募"][kind]]
		b.icon=game.texture_file("res://assets/characters/%d.png" % int(unit.portrait))
		b.expand_icon=true; b.add_theme_constant_override("icon_max_width",24)
		b.add_theme_color_override("font_color",Color(R.COLORS[int(unit.root)])); b.tooltip_text=R.describe(unit)
		b.pressed.connect(manage.bind(kind,i)); cell.add_child(b)
		if kind==1:
			var dismiss_button:=Button.new(); dismiss_button.text="遣散"; dismiss_button.custom_minimum_size=Vector2(44,62); dismiss_button.add_theme_font_size_override("font_size",12)
			dismiss_button.pressed.connect(confirm_dismiss.bind(str(unit.uid))); cell.add_child(dismiss_button)
func apply(operation: Callable, success: String) -> bool:
	var before: Dictionary=game.character.duplicate(true)
	if not operation.call(): game.character=before; notice="操作未完成：请检查等级、境界、人数上限或刷新冷却"; game.refresh_gear_panel(1); return false
	if not game.persist(): game.character=before; notice=game.store.last_error; game.refresh_gear_panel(1); return false
	notice=success; game.refresh_gear_panel(1); return true
func manage(kind: int, index: int) -> void:
	match kind:
		0: apply(func(): return R.withdraw(game.character,index),"已撤回备战")
		1: apply(func(): return R.deploy(game.character,index),"已加入随行，下一场战斗生效")
		2: apply(func(): return R.recruit(game.character,index),"招募成功，已加入备战；点击可设为随行")
func confirm_dismiss(uid: String) -> void:
	dismiss_uid=uid
	var dialog:=ConfirmationDialog.new(); dialog.title="遣散散修"; dialog.dialog_text="遣散后永久失去这位散修，无法找回。确定遣散？"; dialog.ok_button_text="确认遣散"; dialog.cancel_button_text="保留"
	game.menu_layer.add_child(dialog); dialog.confirmed.connect(dismiss_confirmed.bind(uid)); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(450,170))
func dismiss_confirmed(uid: String) -> void:
	for i in range(game.character.retainers.reserve.size()):
		if game.character.retainers.reserve[i].uid==uid:
			apply(func(): return R.dismiss(game.character,i),"已永久遣散散修"); return
func refresh_offers() -> void:
	apply(func(): return R.refresh(game.character,int(Time.get_unix_time_from_system())),"十二位散修已全部刷新")
func update_cooldown() -> void:
	if game==null or not is_instance_valid(game) or game.active_menu!=1 or not is_instance_valid(cooldown_label): return
	var seconds:=maxi(0,int(game.character.retainers.refresh_at)-int(Time.get_unix_time_from_system()))
	cooldown_label.text="免费刷新冷却：%d秒 · 不消耗灵石" % seconds
	refresh_button.disabled=seconds>0


func refresh_paid() -> void:
	apply(func(): return R.refresh_paid(game.character,int(Time.get_unix_time_from_system())),"已花费12灵石刷新，免费刷新倒计时保持不变")
