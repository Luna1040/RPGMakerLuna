extends SceneTree
var failures:Array[String]=[]
var checks:=0

func check(ok: bool, why: String) -> void:
	checks+=1
	if not ok:
		failures.append(why)
		push_error(why)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage=load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.testing_motion=true
	var runtime=stage.runtime
	runtime.persistence_enabled=false
	runtime.autosave_armed=false
	var catalog=load("res://systems/roster_catalog.gd")
	check(catalog.ORDER.size()==5,"Five distinct actor identities expected")
	check(catalog.from_kind("melee")=="scout" and catalog.from_kind("ranged")=="caster","Encounter kind mapping drifted")
	for id in catalog.ORDER:
		check(not catalog.entry(id).name.is_empty(),"Missing display name: "+id)
		runtime.panel.roster_id=id
		runtime.panel.open("roster")
		check(stage.interface.is_modal(),"Roster must pause gameplay")
		check(runtime.panel.body.get_child(0).selected_id==id,"Roster selected wrong portrait")
	var roster=runtime.panel.body.get_child(0)
	check(roster.preview_mode=="portrait" and roster.preview==null,"Catalog must default to the full portrait")
	check(not roster.select_action("not_an_action"),"Unknown preview action accepted")
	if roster.action_ready("stand"):
		check(roster.select_action("stand"),"Ready stand clip cannot preview")
		await process_frame
		var preview=roster.preview
		var before:float=preview.clock_ms
		preview._process(.3)
		check(not is_equal_approx(before,preview.clock_ms),"Preview failed to animate while game modal paused")
		check(not preview.selected.is_empty() and not preview.selected.get("portrait",true),"Ready animation silently substituted a portrait")
		var shown_frame:int=preview.selected.frame
		before=preview.clock_ms
		roster.light_background=true
		roster.update_background()
		check(preview.selected.frame==shown_frame and preview.clock_ms==before,"Background switch resets pose instead of allowing edge comparison")
		# Exercise one-shot timing using a local manifest copy, without changing art files.
		preview.animation.manifest.actions.hurt=preview.animation.clip("stand").duplicate(true)
		preview.action="hurt"
		var duration:float=roster.ClipPlayer.duration_ms(preview.animation.clip("hurt"))
		preview.clock_ms=duration+100
		preview.sample_frame()
		check(preview.selected.frame==preview.animation.clip("hurt").frames.size()-1,"One-shot preview does not hold its final frame")
		preview._process(.2)
		check(preview.selected.frame==preview.animation.clip("hurt").frames.size()-1,"One-shot restarted before its pause")
		preview._process(.4)
		check(preview.clock_ms<duration,"One-shot did not replay after pause")
		preview.animation.manifest.actions.hurt.frames[0].file="missing-preview-test-frame.png"
		check(not roster.action_ready("hurt"),"Clip with a missing frame offered as ready")
		preview.clock_ms=0
		preview.sample_frame()
		check(preview.selected.is_empty() and not preview.error_text.is_empty(),"Missing frame fallback pretends portrait is animation")
		runtime.panel.close()
		before=preview.clock_ms
		preview._process(1)
		check(preview.clock_ms==before,"Hidden preview continues advancing after catalog closes")
	else:
		print("ROSTER_PREVIEW_ASSET_CHECKS deferred: serin/stand not imported")
		check(roster.action_buttons.stand.disabled,"Missing stand clip was clickable")
	runtime.panel.close()
	check(runtime.validate_snapshot(runtime.snapshot()),"Fresh companion payload must be valid")
	runtime.companion_recruited=true
	runtime.companion_mode="guard"
	runtime.encounters.set_companion_enabled(true)
	runtime.encounters.set_companion("guard")
	var ally:Dictionary=runtime.encounters.companion_snapshot()
	ally.hp=57.5
	ally.mp=23.25
	check(runtime.encounters.restore_companion(ally),"Fixture companion state invalid")
	var saved:Dictionary=runtime.snapshot()
	check(runtime.validate_snapshot(saved),"Wounded companion snapshot invalid")
	runtime.encounters.rest_companion()
	check(runtime.restore(saved),"Wounded companion save restore failed")
	var state:Dictionary=runtime.encounters.companion_status()
	check(is_equal_approx(state.hp,57.5) and is_equal_approx(state.mp,23.25),"Save restored companion with free healing")
	check(state.enabled and state.mode=="guard","Save lost recruitment or orders")
	check(runtime.restore(saved) and is_equal_approx(runtime.encounters.companion_status().hp,57.5),"Repeated restore changed vitals")
	var decoded:Dictionary=JSON.parse_string(JSON.stringify(saved))
	check(runtime.restore(decoded) and is_equal_approx(runtime.encounters.companion_status().mp,23.25),"JSON roundtrip changed independent companion mana")
	for field in ["hp","mp"]:
		var malformed:Dictionary=saved.duplicate(true)
		malformed.companion.state[field]=NAN
		var before:=JSON.stringify(runtime.snapshot())
		check(not runtime.restore(malformed),"Nonfinite companion stat accepted")
		check(before==JSON.stringify(runtime.snapshot()),"Rejected companion load mutated game")
	var mismatched:Dictionary=saved.duplicate(true)
	mismatched.companion.state.enabled=false
	check(not runtime.validate_snapshot(mismatched),"Contradictory recruited flags accepted")
	mismatched=saved.duplicate(true)
	mismatched.companion.state.mode="passive"
	check(not runtime.validate_snapshot(mismatched),"Contradictory orders accepted")
	mismatched=saved.duplicate(true)
	mismatched.companion.state={}
	check(not runtime.validate_snapshot(mismatched),"Empty modern companion state silently grants full recovery")
	for pair in [["hp",141.0],["hp",-1.0],["mp",81.0],["mp",-1.0],["heal_cooldown",9.0],["shield",39.0],["dead","false"]]:
		mismatched=saved.duplicate(true)
		mismatched.companion.state[pair[0]]=pair[1]
		check(not runtime.restore(mismatched),"Invalid companion upper bound/type restored: "+str(pair[0]))
	var legacy:Dictionary=saved.duplicate(true)
	legacy.companion.erase("state")
	check(runtime.restore(legacy),"Previous release save rejected")
	state=runtime.encounters.companion_status()
	check(state.enabled and state.mode=="guard" and state.hp==state.max_hp and state.mp==state.max_mp,"Legacy migration lost party or failed initial vitals")
	ally=runtime.encounters.companion_snapshot()
	ally.hp=0.0
	ally.mp=0.0
	ally.dead=true
	check(runtime.encounters.restore_companion(ally),"Downed companion fixture invalid")
	var downed_save:Dictionary=runtime.snapshot()
	check(runtime.restore(downed_save) and runtime.encounters.companion_status().dead,"Loading a downed companion resurrects her")
	stage.knight.health=stage.knight.max_health
	stage.knight.mana=stage.knight.max_mana
	stage.loot.materials["旧铜币"]=30
	check(runtime.rest_party(),"Healthy hero cannot rest wounded companion")
	state=runtime.encounters.companion_status()
	check(not state.dead and state.hp==state.max_hp and state.mp==state.max_mp,"Inn did not revive/refill companion")
	check(stage.loot.materials["旧铜币"]==20,"Party rest should charge once")
	check(not runtime.rest_party() and stage.loot.materials["旧铜币"]==20,"Full party was charged for unnecessary rest")
	ally=runtime.encounters.companion_snapshot()
	ally.hp=25.0
	runtime.encounters.restore_companion(ally)
	stage.loot.materials["旧铜币"]=9
	check(not runtime.rest_party() and runtime.encounters.companion_status().hp==25,"Insufficient funds still healed companion")
	stage.loot.materials["旧铜币"]=30
	runtime.zone="ruins"
	check(not runtime.rest_party() and runtime.encounters.companion_status().hp==25,"Inn healing allowed in dungeon")
	runtime.zone="town"
	runtime.panel.close()
	runtime.party_hud.update_status()
	check(runtime.party_hud.visible and runtime.party_hud.hp.value==25,"Companion HUD doesn't reflect live health")
	runtime.panel.open("roster")
	runtime.party_hud.update_status()
	check(not runtime.party_hud.visible,"Companion HUD obscures modal")
	runtime.panel.close()
	runtime.companion_recruited=false
	runtime.party_hud.update_status()
	check(not runtime.party_hud.visible,"Unrecruited companion HUD visible")
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	print("ROSTER_INTEGRATION_TEST ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
