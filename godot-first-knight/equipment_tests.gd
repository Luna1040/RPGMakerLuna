extends RefCounted
## Integration checks use a dedicated fixture, never the player's save.
func run(arena: Node2D) -> void:
	var knight = arena.knight
	var ui = arena.equipment_ui
	var tree := arena.get_tree()
	knight.input_enabled = false
	var model = knight.equipment
	assert(not model.persistence_enabled)
	var reach: float = knight.get_attack_reach("attack1")
	assert(not model.equip("unknown") and not model.unequip("unknown"))
	assert(model.equip("edge_sword"))
	assert(knight.get_attack_damage("attack1") == 30)
	assert(knight.get_attack_reach("attack1") == reach)
	assert(not model.equip("edge_sword"))
	assert(model.equip("guardian_armor"))
	assert(knight.max_health == 140 and knight.health == 100 and knight.defense == 6)
	assert(knight.move_speed + knight.equipment_speed_bonus == 185)
	knight.apply_damage(15)
	assert(knight.health == 91)
	knight.reset_character()
	assert(knight.health == 140)
	model.unequip("armor")
	assert(knight.health == 100 and knight.max_health == 100)
	model.equip("steel_boots")
	knight.apply_damage(1)
	assert(knight.health == 99, "Armor must not grant immunity")
	knight.reset_character()
	knight.apply_damage(0.25)
	assert(knight.health == 114.75, "Fractional incoming damage must not increase")
	knight.reset_character()
	model.equip("spring_charm")
	knight.mana = 0
	knight.set_physics_process(false)
	knight._physics_process(0.1)
	assert(is_equal_approx(knight.mana, 1.0), "Equipment regen must apply")
	model.equip("arcane_sword")
	model.equip("storm_charm")
	var spell_events: Array = []
	knight.spell_requested.connect(func(event): spell_events.append(event))
	knight.reset_character()
	knight.request_cast()
	assert(knight.mana == 95 and knight.max_mana == 120 and knight.cast_cooldown == 2.4)
	knight._physics_process(0.37)
	assert(spell_events.size() == 1 and spell_events[0]["damage"] == 66)
	knight._physics_process(0.05)
	assert(spell_events.size() == 1, "Equipment must not repeat spell events")
	knight.reset_character()
	var attacks: Array = []
	knight.attack_hitbox.connect(func(event): attacks.append(event))
	knight.request_attack()
	knight._physics_process(0.31)
	assert(attacks.size() == 1 and attacks[0]["damage"] == 26)
	knight._physics_process(0.05)
	assert(attacks.size() == 1)
	knight.reset_character()
	knight.apply_damage(999)
	model.equip("guardian_armor")
	assert(knight.defeated and knight.health == 0, "Equipping must not revive")
	knight.reset_character()
	# Save/reload and reject forged slot assignments or unknown item IDs.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.test-runtime"))
	var fixture := "res://.test-runtime/equipment-fixture.json"
	model.persistence_enabled = true
	assert(model.save_loadout(fixture))
	var restored = preload("res://equipment.gd").new()
	restored.load_loadout(fixture)
	assert(restored.equipped == model.equipped and restored.owned == model.owned)
	assert(model.save_loadout(fixture), "Replacing an existing save must work")
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"owned":["wind_boots","unknown","wind_boots"],"equipped":{"weapon":"wind_boots","boots":"wind_boots","armor":"unknown"}}))
	file.close()
	restored.load_loadout(fixture)
	assert(restored.owned == ["wind_boots"] and restored.equipped["weapon"] == "" and restored.equipped["boots"] == "wind_boots")
	file = FileAccess.open(fixture, FileAccess.WRITE)
	file.store_string("{broken json")
	file.close()
	var old: Dictionary = restored.equipped.duplicate()
	restored.load_loadout(fixture)
	assert(restored.equipped == old)
	model.persistence_enabled = false
	# Exercise keyboard toggle, UI signals, empty slot, and pause restoration.
	knight.set_physics_process(true)
	await tree.process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await tree.process_frame
	assert(ui.opened and tree.paused and ui.overlay.visible)
	var cooldown: float = knight.cast_cooldown
	var position: Vector2 = knight.position
	var clock: float = arena.effect_clock
	await tree.create_timer(0.12, true).timeout
	assert(knight.cast_cooldown == cooldown and knight.position == position and arena.effect_clock == clock)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = ui.item_buttons["edge_sword"].get_global_rect().get_center()
	click.pressed = true
	arena.get_viewport().push_input(click)
	click = click.duplicate()
	click.pressed = false
	arena.get_viewport().push_input(click)
	await tree.process_frame
	assert(ui.selected == "edge_sword" and ui.comparison.text.contains("→"))
	ui.equip_button.pressed.emit()
	assert(knight.attack_bonus == 8 and ui.equip_button.disabled)
	ui.unequip_button.pressed.emit()
	assert(model.equipped["weapon"] == "" and knight.attack_bonus == 0)
	ui.slot_buttons["weapon"].pressed.emit()
	assert(ui.equip_button.disabled and ui.unequip_button.disabled)
	key.keycode = KEY_TAB
	Input.parse_input_event(key)
	await tree.process_frame
	assert(not arena.gallery_demo, "Tab must navigate UI without changing gallery")
	key.keycode = KEY_ESCAPE
	Input.parse_input_event(key)
	await tree.process_frame
	assert(not ui.opened and not tree.paused)
	tree.paused = true
	ui.toggle()
	ui.toggle()
	assert(tree.paused, "Closing UI must restore prior pause state")
	tree.paused = false
	print("EQUIPMENT PASS: slots, bonuses, damage events, armor, capacity clamping, regen, death/reset, save/reload/validation, mouse selection/equip/unequip, keyboard navigation, world pause")
	tree.quit()
