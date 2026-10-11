extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var actor = load("res://characters/first_knight/knight.gd").new()
	actor.equipment.persistence_enabled = false
	actor.use_local_input = false
	root.add_child(actor)
	var ui = load("res://map_interface.gd").new()
	root.add_child(ui)
	ui.setup(actor, null)
	ui.toggle_inventory()
	var panel = ui.inventory_content
	var before: Dictionary = actor.equipment.equipped.duplicate()
	panel.buttons.arcane_sword.mouse_entered.emit()
	check(panel.selected_id == "arcane_sword", "Hover did not select equipment")
	check(actor.equipment.equipped == before, "Hover mutated equipped items")
	check(panel.detail_text.text.contains("魔法攻击力  56"), "Hover spell preview incorrect")
	check(panel.detail_text.text.contains("攻击力  26"), "Hover melee preview incorrect")
	panel.buttons.arcane_sword.pressed.emit()
	check(actor.get_spell_damage() == 56 and actor.get_attack_damage("attack1") == 26, "Equip did not reach actual combat stats")
	check(panel.stat_text.text.contains("魔法攻击力  56"), "Character panel not refreshed after equip")
	panel.buttons.edge_sword.focus_entered.emit()
	check(panel.detail_text.text.contains("(-14)"), "Replacement did not subtract old magic bonus")
	check(panel.detail_text.text.contains("(+4)"), "Replacement added full item instead of net delta")
	panel.buttons.guardian_armor.mouse_entered.emit()
	check(panel.detail_text.text.contains("(-15)"), "Negative movement stat missing")
	actor.health = 63
	actor.stats_changed.emit(actor.health, actor.mana)
	check(panel.stat_text.text.contains("63 / 100"), "Current health does not update")
	ui.close_panels()
	check(not ui.is_modal(), "Inventory did not close")
	for error in failures: push_error(error)
	print("INVENTORY_PANEL_TEST ", "PASS" if failures.is_empty() else "FAIL", " · hover/focus preview, net replacement, actual combat values, live health, close")
	ui.queue_free()
	actor.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
