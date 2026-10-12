extends SceneTree
## B-11: strict world-blueprint validation and deterministic compilation into
## the existing prebuilt 2.5D map contract, without generated code or paths.

var failures:Array[String]=[]

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,message:String)->void:
	if not condition: failures.append(message)

func run()->void:
	var registry=root.get_node_or_null("ContentRegistry")
	var service=root.get_node_or_null("WorldBlueprintService")
	var bridge=root.get_node_or_null("WorkbenchBridge")
	registry.load_base_content()
	var blueprint:=fixture()
	check(service.validate_shape(blueprint).is_empty(),"valid world blueprint was rejected: "+str(service.validate_shape(blueprint)))
	var compiled:Dictionary=service.compile_blueprint(blueprint)
	check(compiled.get("ok",false),"valid world blueprint did not compile")
	var bundle:Dictionary=compiled.get("world_bundle",{})
	check(service.validate_world_bundle(bundle).is_empty(),"compiled world bundle failed read-back validation")
	check(bundle.get("zones",{}).size()==2 and bundle.initial_zone_id=="zone.starfall_courtyard","compiler lost zone graph identity")
	var town:Dictionary=bundle.zones.get("zone.starfall_courtyard",{})
	check(town.get("projection")=="side-facing-belt" and town.get("volumes",[]).size()==2,"compiler did not create the prebuilt belt-map contract")
	check(town.volumes[0].get("asset")=="inn" and "asset_id" not in town.volumes[0],"registered asset ID was not mapped through the prebuilt allowlist")
	check("res://" not in JSON.stringify(bundle) and ".gd" not in JSON.stringify(bundle),"compiled world contains a resource path or script reference")
	var tampered:=bundle.duplicate(true)
	tampered.zones["zone.starfall_courtyard"].name="被篡改"
	check(not service.validate_world_bundle(tampered).is_empty(),"tampered world bundle checksum was accepted")

	var bad_asset:=blueprint.duplicate(true)
	bad_asset.zones[0].landmarks[0].asset_id="res://evil.gd"
	check(not service.validate_shape(bad_asset).is_empty(),"arbitrary resource/script path was accepted as a world asset")
	var blocked_spawn:=blueprint.duplicate(true)
	blocked_spawn.zones[0].spawn={"x":3.0,"depth":1.0}
	check(not service.validate_shape(blocked_spawn).is_empty(),"solid landmark was allowed to block the player spawn")
	var unreachable:=blueprint.duplicate(true)
	unreachable.zones[0].exits=[]
	check(not service.validate_shape(unreachable).is_empty(),"unreachable generated zone graph was accepted")
	var sealed:=blueprint.duplicate(true)
	sealed.zones[0].landmarks.append({"landmark_id":"landmark.sealed_wall","kind":"wall","x":12.0,"depth":0.5,"width":0.6,"depth_size":8.7,"height":3.0,"solid":true,"standable":false,"asset_id":""})
	check(not service.validate_shape(sealed).is_empty(),"map with no physical spawn-to-exit route was accepted")

	var created:Dictionary=bridge.create_authoring_run({"schema_version":"authoring-run-request/1","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","theme":"星落庭院与回声遗迹","tone":"mystery","scope":"chapter","content_policy":"general",
		"requested_systems":["world","map","town"],"constraints":["地图必须由预置编译器生成"]})
	var run_id:=str(created.get("run",{}).get("run_id",""))
	var dispatch:Dictionary=bridge.dispatch_authoring_tasks(run_id)
	var task:Dictionary=dispatch.get("tasks",[])[0].task
	blueprint.blueprint_id="blueprint.authoring."+run_id.trim_prefix("run.authoring.")
	var result:={"schema_version":"agent-result/1","request_id":str(task.request_id),"agent_role":"world","status":"completed",
		"summary":"生成两区可达世界蓝图。","deliverables":[{"deliverable_id":"deliverable.world.blueprint","kind":"world_blueprint","payload":blueprint}],
		"evidence":["仅使用 asset.world.* 白名单。"],"warnings":[]}
	var reviewed:Dictionary=bridge.submit_authoring_result(run_id,result)
	check(reviewed.get("ok",false) and reviewed.get("validator_ready",false),"World Agent blueprint did not pass trusted review")
	var validator:Dictionary=bridge.dispatch_authoring_tasks(run_id)
	var validator_task:Dictionary=validator.get("tasks",[])[0].task
	var final_result:={"schema_version":"agent-result/1","request_id":str(validator_task.request_id),"agent_role":"validator","status":"completed",
		"summary":"世界蓝图 Schema、可达性与资产白名单通过。","deliverables":[],"evidence":["Godot 编译器复检通过。"],"warnings":[]}
	var finished:Dictionary=bridge.submit_authoring_result(run_id,final_result)
	check(finished.get("ok",false) and finished.run.status=="completed_analysis","world-only Run did not close through Validator")
	check(finished.run.get("world_bundle",{}).get("world_hash")==service.compile_blueprint(blueprint).world_bundle.world_hash,"Main Agent did not retain the reviewed compiled world")
	finish()

func fixture()->Dictionary:
	return {"schema_version":"world-blueprint/1","blueprint_id":"blueprint.test.starfall","project_id":"project.rpgmakerluna.courtyard",
		"genre":"western_fantasy","lore_summary":"星潮把边境庭院与古老回声遗迹连接在同一条可逆道路上。","initial_zone_id":"zone.starfall_courtyard",
		"regions":[{"region_id":"region.starfall_border","name":"星落边境","summary":"旧王道与星潮裂隙交汇的边境。"}],
		"zones":[
			{"zone_id":"zone.starfall_courtyard","region_id":"region.starfall_border","name":"星落庭院","biome":"grassland","town_npcs":true,
				"bounds":{"width":24.2,"depth_size":8.7},"spawn":{"x":6.5,"depth":5.6},
				"landmarks":[
					{"landmark_id":"landmark.starfall_inn","kind":"building","x":2.1,"depth":0.7,"width":3.7,"depth_size":0.85,"height":4.5,"solid":true,"standable":false,"asset_id":"asset.world.inn","visual_height":7.5},
					{"landmark_id":"landmark.starfall_crate","kind":"crate","x":8.0,"depth":5.4,"width":1.0,"depth_size":1.0,"height":0.85,"solid":true,"standable":true,"asset_id":"asset.world.crate","visual_height":1.05}],
				"exits":[{"exit_id":"exit.to_echo_ruins","to_zone_id":"zone.echo_ruins","x":23.5,"depth":7.5}]},
			{"zone_id":"zone.echo_ruins","region_id":"region.starfall_border","name":"回声遗迹","biome":"cavern","town_npcs":false,
				"bounds":{"width":20.0,"depth_size":7.0},"spawn":{"x":2.0,"depth":5.5},
				"landmarks":[{"landmark_id":"landmark.echo_tree","kind":"tree","x":10.0,"depth":3.0,"width":0.72,"depth_size":0.8,"height":5.2,"solid":true,"standable":false,"asset_id":"asset.world.tree","visual_height":4.3}],
				"exits":[{"exit_id":"exit.to_starfall","to_zone_id":"zone.starfall_courtyard","x":1.2,"depth":5.5}]}]}

func finish()->void:
	for message in failures: push_error(message)
	print("WORLD_BLUEPRINT_COMPILER_TEST %s · strict schema, reachability, asset allowlist, prebuilt map compile" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
