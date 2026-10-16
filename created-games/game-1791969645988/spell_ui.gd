extends RefCounted
const S=preload("res://spell_system.gd")
const E=preload("res://estate_system.gd")
var game
var notice:=""
func build(owner_game, content: VBoxContainer) -> void:
	game=owner_game
	game.menu_window.position=Vector2(190,80); game.menu_window.custom_minimum_size=Vector2(900,620); game.menu_window.size=Vector2(900,620)
	content.add_theme_constant_override("separation",8)
	game.label_text(content,"%s · 每境界两种仙法 · 学成后在战斗中自动轮流施展" % game.character.profession,19)
	game.label_text(content,notice if not notice.is_empty() else "野怪每只15%掉落本职业仙法玉简；学习消耗1枚，升级依次消耗2至10枚同名玉简。",15)
	var grid:=GridContainer.new(); grid.columns=2; grid.add_theme_constant_override("h_separation",12); grid.add_theme_constant_override("v_separation",12); content.add_child(grid)
	for id in S.ids(game.character):
		var card:=PanelContainer.new(); card.custom_minimum_size=Vector2(424,215); grid.add_child(card)
		var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",6); card.add_child(column)
		var def: Dictionary=S.DATA[id]; var level:=int(game.character.spells.get(id,0))
		game.label_text(column,str(def.name)+" · "+("筑基期" if int(def.realm)==1 else "练气期"),22)
		game.label_text(column,"等级 %d/10 · 持有同名玉简 %d" % [level,E.count(game.character.inventory,"spell_manual",id)],16)
		game.label_text(column,S.describe(id,maxi(1,level)),15)
		var locked:=not S.permitted(game.character,id)
		var text: String=("需筑基后学习" if int(def.realm)==1 else "需练气后学习") if locked else ("已满级" if level>=10 else ("学习" if level==0 else "升级至%d级" % (level+1))+" · 消耗%d枚" % S.cost(game.character,id))
		var button: Button=game.button(column,text,learn.bind(id,5))
		button.disabled=locked or level>=10 or E.count(game.character.inventory,"spell_manual",id)<S.cost(game.character,id)
func learn(id: String, from_menu: int=5) -> void:
	var before: Dictionary=game.character.duplicate(true)
	if not S.learn(game.character,id): notice="职业、境界、玉简数量不满足条件，或已满十级"
	elif not game.persist(): game.character=before; notice=game.store.last_error+"；玉简与等级已回滚"
	else: notice="%s 已提升至%d级" % [S.DATA[id].name,int(game.character.spells[id])]
	game.gear_notice=notice
	game.refresh_gear_panel(from_menu)
