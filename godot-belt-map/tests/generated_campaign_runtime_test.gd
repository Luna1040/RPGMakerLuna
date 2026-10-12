extends SceneTree
## B-12: one reviewed data-only package must survive the complete authoring
## boundary and boot as a playable generated campaign.

const SaveStore = preload("res://systems/core/save_store.gd")
var failures: Array[String] = []
var scratch_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func run() -> void:
	var registry = root.get_node_or_null("ContentRegistry")
	var drafts = root.get_node_or_null("ContentDraftService")
	var imports = root.get_node_or_null("CampaignImportService")
	var sessions = root.get_node_or_null("CampaignSessionService")
	var worlds = root.get_node_or_null("WorldBlueprintService")
	check(registry != null and registry.loaded, "ContentRegistry unavailable")
	check(drafts != null and imports != null and sessions != null and worlds != null, "campaign services unavailable")
	if registry == null or drafts == null or imports == null or sessions == null or worlds == null:
		finish()
		return
	registry.load_base_content()
	var original_publish_root: String = drafts.publish_root
	var original_projects_root: String = imports.projects_root
	scratch_root = "user://generated-campaign-runtime-test-" + str(Time.get_ticks_usec())
	drafts.publish_root = scratch_root
	imports.projects_root = scratch_root
	drafts.clear_previews()
	imports.clear_previews()
	sessions.clear_launch_previews()

	var compiled: Dictionary = worlds.compile_blueprint(world_blueprint())
	check(compiled.ok, "generated world fixture did not compile: " + str(compiled.get("errors", [])))
	var draft := full_draft(registry, compiled.get("world_bundle", {}))
	var validation: Array[String] = drafts.validate_draft(draft)
	check(validation.is_empty(), "full generated campaign draft was rejected: " + "; ".join(validation))
	var preview: Dictionary = drafts.preview_draft(draft)
	var published: Dictionary = drafts.publish_draft(draft, str(preview.get("preview_token", "")))
	check(preview.ok and preview.operation_count == 7, "full campaign preview did not include every generated system")
	check(published.ok, "full campaign could not be published: " + str(published.get("errors", [])))

	var request := {"schema_version":"campaign-import-request/1", "request_id":"request.test.generated-runtime",
		"project_id":"project.rpgmakerluna.courtyard", "draft_id":"draft.test.generated-runtime",
		"campaign_id":"campaign.test.generated-runtime", "display_name":"星潮边境", "activation_policy":"new_campaign"}
	var import_preview: Dictionary = imports.preview_import(request)
	var installed: Dictionary = imports.install_campaign(request, str(import_preview.get("preview_token", "")))
	check(installed.ok, "full generated campaign could not be installed: " + str(installed.get("errors", [])))
	var launch: Dictionary = sessions.preview_campaign_launch(request.project_id, request.campaign_id)
	var scheduled: Dictionary = sessions.start_campaign_session(request.project_id, request.campaign_id, str(launch.get("launch_token", "")))
	check(scheduled.ok and scheduled.get("scheduled", false), "generated campaign launch was not scheduled: " + str(scheduled.get("errors", [])))
	var reached_stage := await wait_for_scene("res://stage.tscn")
	check(reached_stage, "generated campaign did not reach the real gameplay scene")
	if not reached_stage:
		cleanup(str(installed.get("campaign_path", "")), str(published.get("artifact_path", "")), request.project_id)
		drafts.publish_root = original_publish_root
		imports.projects_root = original_projects_root
		finish()
		return

	var stage = current_scene
	check(registry.content_context().get("campaign_id") == request.campaign_id, "generated content context was not activated")
	check(registry.world_bundle().get("initial_zone_id") == "zone.starfall_courtyard", "generated world was not activated")
	check(stage.contract.get("zone_id") == "zone.starfall_courtyard", "stage did not boot the generated initial map")
	check(stage.runtime != null and stage.runtime.zone == "zone.starfall_courtyard", "runtime did not enter generated initial map")
	if stage.runtime != null:
		var runtime = stage.runtime
		check(runtime.current_zone_name() == "星落庭院", "generated zone title was not exposed to the runtime UI")
		check(runtime.available_travel().any(func(route): return route.zone_id == "zone.echo_ruins"), "generated exit graph was not playable")
		var transfer: Dictionary = runtime.prepare_transfer("zone.echo_ruins")
		check(transfer.get("zone") == "zone.echo_ruins" and transfer.get("player", {}).get("foot") == [2.0, 5.5], "generated travel did not use the target spawn")
		check(registry.target_exists("npc", "star_sage") and stage.townsfolk.residents.any(func(row): return row.id == "star_sage"), "generated NPC did not appear in the real stage")
		check(runtime.stage.knight.equipment.CATALOG.has("star_blade"), "generated equipment did not enter the character catalog")
		check(runtime.adventure.catalog.get("consumables", {}).has("star_tonic"), "generated item did not enter the adventure catalog")
		check(runtime.adventure.catalog.get("shop", []).any(func(row): return row.id == "star_blade"), "generated shop row did not enter the runtime")
		check(runtime.adventure.accept_quest("starfall_echo"), "generated main quest was not acceptable")
		var clue: Dictionary = runtime.adventure.choose("star_sage", "star_sage_clue")
		check(clue.ok, "generated NPC choice could not advance the quest")
		var claimed: Dictionary = runtime.adventure.claim_quest("starfall_echo")
		check(claimed.ok and runtime.adventure.reputation.get("star_sage", 0) == 3, "quest reward and affinity progression did not close")
		check(runtime.adventure.consumables.get("star_tonic", 0) == 1, "generated consumable reward was not granted")
		var purchase: Dictionary = runtime.adventure.buy("star_blade")
		check(purchase.ok and runtime.stage.knight.equipment.owned.has("star_blade"), "generated shop/equipment purchase did not close")
		var snapshot: Dictionary = runtime.snapshot()
		check(runtime.validate_snapshot(snapshot), "generated campaign snapshot failed its own content/world boundary")
		var isolated = SaveStore.new(str(installed.save_namespace))
		check(isolated.save_slot(1, snapshot), "generated campaign could not save in its isolated namespace")

	var campaign_stage = current_scene
	var official: Dictionary = sessions.start_official_session()
	check(official.ok and official.scheduled, "official restoration was not scheduled")
	check(await wait_for_scene("res://stage.tscn", campaign_stage), "official scene did not replace the generated campaign")
	check(registry.is_official_context() and registry.world_bundle().is_empty(), "generated campaign leaked into official content")

	cleanup(str(installed.get("campaign_path", "")), str(published.get("artifact_path", "")), request.project_id)
	drafts.publish_root = original_publish_root
	imports.projects_root = original_projects_root
	drafts.clear_previews()
	imports.clear_previews()
	sessions.clear_launch_previews()
	# Release both generated and official stage graphs before the scripted
	# SceneTree exits so dynamically-created NPC portrait resources are freed.
	stage = null
	campaign_stage = null
	var final_scene: Node = current_scene
	current_scene = null
	if final_scene != null: final_scene.queue_free()
	await process_frame
	await process_frame
	finish()

func full_draft(registry, world_bundle: Dictionary) -> Dictionary:
	var npc: Dictionary = registry.get_npc("innkeeper")
	npc.id = "star_sage"
	npc.display_name = "弥娅 · 星潮学者"
	npc.position_m = [12.0, 6.0]
	npc.ambient_lines = ["星潮让遗迹的回声越过了旧王道。", "你的选择会改变我们之间的信任。"]
	var dialogue := {"name":"弥娅 · 星潮学者", "greeting":"旅人，愿意追踪庭院外的回声吗？", "variants":[], "choices":[
		{"id":"star_sage_accept", "label":"接受：回声的源头", "action":"accept", "quest":"starfall_echo",
			"when":{"quest":{"id":"starfall_echo", "status":["available"]}}},
		{"id":"star_sage_clue", "label":"记录星潮线索", "action":"effect", "text":"弥娅把星纹拓片交给了你。",
			"when":{"quest":{"id":"starfall_echo", "status":["active"]}},
			"effects":{"flags":{"supply_hint":true}, "reputation":{"star_sage":1}}}]}
	var quest := {"id":"starfall_echo", "title":"回声的源头", "description":"与弥娅核对拓片，准备前往回声遗迹。",
		"npc":"star_sage", "position":[8, 4], "requires":{}, "objectives":[
			{"id":"starfall_clue", "kind":"flag", "flag":"supply_hint", "target":1, "label":"取得星潮拓片"}],
		"rewards":{"xp":10, "consumables":{"star_tonic":1}, "reputation":{"star_sage":2}}}
	var equipment := {"id":"star_blade", "kind":"equipment", "name":"星痕长剑", "slot":"weapon", "quality":"稀有",
		"symbol":"星", "description":"星潮淬炼的轻盈长剑。", "stats":{"attack":9.0, "magic":5.0}}
	var item := {"id":"star_tonic", "name":"星露药剂", "description":"恢复 35 点生命。", "stat":"health", "amount":35, "max_stack":8}
	var shop := {"id":"star_blade", "kind":"equipment", "cost":{"旧铜币":12}}
	return {"schema_version":"content-draft/1", "draft_id":"draft.test.generated-runtime",
		"project_id":"project.rpgmakerluna.courtyard", "base_catalog_hash":registry.catalog_hash,
		"base_content_revision":registry.revision, "author_role":"main", "summary":"完整生成星潮边境战役。",
		"world_bundle":world_bundle.duplicate(true), "operations":[
			{"op":"upsert", "target_type":"npc", "target_id":"star_sage", "definition":npc},
			{"op":"upsert", "target_type":"dialogue", "target_id":"star_sage", "definition":dialogue},
			{"op":"upsert", "target_type":"quest", "target_id":"starfall_echo", "definition":quest},
			{"op":"upsert", "target_type":"equipment", "target_id":"star_blade", "definition":equipment},
			{"op":"upsert", "target_type":"item", "target_id":"star_tonic", "definition":item},
			{"op":"upsert", "target_type":"shop", "target_id":"star_blade", "definition":shop},
			{"op":"upsert", "target_type":"dialogue", "target_id":"innkeeper", "definition":registry.get_dialogue("innkeeper")}]}

func world_blueprint() -> Dictionary:
	return {"schema_version":"world-blueprint/1", "blueprint_id":"blueprint.test.generated-runtime", "project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy", "lore_summary":"星潮把边境庭院与古老回声遗迹连接在同一条可逆道路上。", "initial_zone_id":"zone.starfall_courtyard",
		"regions":[{"region_id":"region.starfall_border", "name":"星落边境", "summary":"旧王道与星潮裂隙交汇的边境。"}],
		"zones":[
			{"zone_id":"zone.starfall_courtyard", "region_id":"region.starfall_border", "name":"星落庭院", "biome":"grassland", "town_npcs":true,
				"bounds":{"width":24.2, "depth_size":8.7}, "spawn":{"x":6.5, "depth":5.6}, "landmarks":[
					{"landmark_id":"landmark.starfall_inn", "kind":"building", "x":2.1, "depth":0.7, "width":3.7, "depth_size":0.85, "height":4.5, "solid":true, "standable":false, "asset_id":"asset.world.inn", "visual_height":7.5}],
				"exits":[{"exit_id":"exit.to_echo_ruins", "to_zone_id":"zone.echo_ruins", "x":23.5, "depth":7.5}]},
			{"zone_id":"zone.echo_ruins", "region_id":"region.starfall_border", "name":"回声遗迹", "biome":"cavern", "town_npcs":false,
				"bounds":{"width":20.0, "depth_size":7.0}, "spawn":{"x":2.0, "depth":5.5}, "landmarks":[
					{"landmark_id":"landmark.echo_tree", "kind":"tree", "x":10.0, "depth":3.0, "width":0.72, "depth_size":0.8, "height":5.2, "solid":true, "standable":false, "asset_id":"asset.world.tree", "visual_height":4.3}],
				"exits":[{"exit_id":"exit.to_starfall", "to_zone_id":"zone.starfall_courtyard", "x":1.2, "depth":5.5}]}]}

func wait_for_scene(path: String, previous = null) -> bool:
	for _frame in range(120):
		await process_frame
		if current_scene != null and current_scene != previous and str(current_scene.scene_file_path) == path: return true
	return false

func cleanup(campaign_path: String, artifact_path: String, project_id: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var save_path: String = campaign_path.path_join("saves").path_join("slot_1.json") + suffix
		if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for path in [campaign_path.path_join("saves"), campaign_path.path_join("manifest.json"), campaign_path.path_join("content.json"), artifact_path]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var project_path: String = scratch_root.path_join(project_id)
	for path in [campaign_path, project_path.path_join("campaigns"), project_path.path_join("published"), project_path, scratch_root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	for message in failures: push_error(message)
	print("GENERATED_CAMPAIGN_RUNTIME_TEST %s · world, NPC, quest, affinity, item, equipment, shop, travel, save" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
