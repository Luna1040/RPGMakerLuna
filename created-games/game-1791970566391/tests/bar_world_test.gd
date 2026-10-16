extends SceneTree

var game
var failed := false

func _init() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("BAR_WORLD_FAIL: " + message)

func walk_segment(target: Vector2) -> void:
	for _step in range(300):
		var delta: Vector2 = target - game.bar_player
		if delta.length() <= 2.0:
			game.bar_player = target
			return
		var before: Vector2 = game.bar_player
		game.move_bar_player(delta.normalized() * minf(4.0, delta.length()))
		if game.bar_player == before:
			require(false, "route blocked before " + str(target) + " at " + str(before))
			return
	require(false, "route iteration limit: " + str(target))

func walk_route(points: Array) -> void:
	game.bar_player = game.BAR_SPAWN
	for point in points: walk_segment(point)

func mouse_move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	game._unhandled_input(event)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.activate_title_menu()

	require(game.BAR_WORLD_SIZE == Vector2(768,432), "world dimensions must be the wide three-zone layout")
	require(game.BAR_VIEW_SIZE == game.BAR_WORLD_SIZE and is_equal_approx(game.BAR_VIEW_SCALE,5.0/12.0), "bar camera must show the full three-zone world")
	require(game.BAR_MIX_HOTSPOT.size.x <= 36 and game.BAR_MIX_HOTSPOT.size.y <= 34, "tool hotspot must stay tightly scoped")
	require(not game.bar_position_walkable(Vector2(280,180)), "counter side footprint must block walking")
	require(game.bar_position_walkable(game.BAR_MIX_POS), "counter approach must remain walkable")
	require(game.bar_position_walkable(Vector2(384,280)), "front counter gap must be a real walkable passage")
	require(game.bartender_texture != null and game.zhou_texture != null, "generated bar character sprites must load")
	require(game.bartender_texture.get_size() == Vector2(80,80) and game.zhou_texture.get_size() == Vector2(80,80), "bar character sprites must share the enlarged fixed 80x80 canvas")
	require(game.BAR_SPRITE_PIVOT == Vector2(40,72), "enlarged sprites must share one fixed foot pivot")
	for action_frames in [game.bartender_walk_frames, game.bartender_interact_frames, game.zhou_walk_frames, game.zhou_interact_frames]:
		require(action_frames.size() == 8, "each H3 walking or interaction action must import eight frames")
		for frame in action_frames:
			require(frame != null and frame.get_size() == Vector2(80,80), "every H3 action frame must keep the shared 80x80 canvas")
	require(game.BAR_ZHOU_ENTRY_START.y > game.BAR_WORLD_SIZE.y + 64.0 and game.zhou_pos == game.BAR_ZHOU_ENTRY_START and not game.zhou_arrived, "Zhou must start fully outside the bottom doorway")
	game.restart_demo()
	require(game.phase == game.Phase.TITLE and game.zhou_pos == game.BAR_ZHOU_ENTRY_START and not game.zhou_arrived, "restarting must reset Zhou outside the bar")
	game.activate_title_menu()
	require(game.phase == game.Phase.BAR and game.zhou_pos == game.BAR_ZHOU_ENTRY_START, "starting again must replay Zhou's entrance")
	game.bar_player = game.BAR_ZHOU_POS
	game.update_bar(0.0)
	require(game.interaction_hint != "E  与周骁交谈" and not game.bar_interaction_in_reach(), "Zhou cannot be addressed at his destination before arriving")
	game.bar_player = game.BAR_SPAWN
	game.update_bar(0.5)
	require(game.zhou_is_walking and game.zhou_pos.x == game.BAR_ZHOU_ENTRY_START.x and game.zhou_pos.y < game.BAR_ZHOU_ENTRY_START.y, "Zhou must walk in from beyond the bottom edge")
	var previous_zhou: Vector2 = game.zhou_pos
	for _step in range(10):
		game.update_bar(0.35)
		require(game.zhou_pos.x <= previous_zhou.x + 0.01 and game.zhou_pos.y <= previous_zhou.y + 0.01, "Zhou's path must progress toward the left lounge without pacing back")
		if game.zhou_pos.y <= game.BAR_WORLD_SIZE.y - 12.0:
			require(game.bar_position_walkable(game.zhou_pos), "Zhou's route inside the bar must remain walkable")
		previous_zhou = game.zhou_pos
	require(game.zhou_arrived and not game.zhou_is_walking and game.zhou_pos == game.BAR_ZHOU_POS, "Zhou must stop at the left lounge after crossing the doorway")
	game.update_bar(0.5)
	require(game.zhou_pos == game.BAR_ZHOU_POS and not game.zhou_is_walking, "Zhou must remain at the dialogue spot")
	game.bar_player = game.BAR_ZHOU_POS
	game.update_bar(0.0)
	require(game.interaction_hint == "E  与周骁交谈" and game.bar_interaction_in_reach(), "Zhou must become interactable once he arrives")
	game.bar_player = game.BAR_SPAWN; game.begin_bar_action("interact")
	require(not game.bar_action_active, "E in empty floor space must not trigger an interaction gesture")
	require(game.BAR_DANCE_NPC_ANCHORS.size() == 2, "dancefloor must reserve two dialogue anchors")
	for anchor in game.BAR_DANCE_NPC_ANCHORS:
		require(game.bar_position_walkable(anchor), "dancefloor dialogue anchor must stay clear: " + str(anchor))

	# Actual movement/collision service reaches every required district from the entrance.
	walk_route([Vector2(384,325), Vector2(384,280), Vector2(384,220), game.BAR_MIX_POS]); require(game.bar_player == game.BAR_MIX_POS, "central bar interior reachable through the front gap")
	walk_route([game.BAR_COMMS_POS]); require(game.bar_player == game.BAR_COMMS_POS, "return communicator reachable")
	walk_route([Vector2(515,350), Vector2(515,100), game.BAR_ARCHIVE_POS]); require(game.bar_player == game.BAR_ARCHIVE_POS, "archive corridor reachable")
	walk_route([Vector2(250,405), Vector2(250,230), game.BAR_ZHOU_POS]); require(game.bar_player == game.BAR_ZHOU_POS, "left lounge patron reachable")
	walk_route([Vector2(250,405), Vector2(250,130), game.BAR_COASTER_POS]); require(game.bar_player == game.BAR_COASTER_POS, "left lounge coaster reachable")
	walk_route([Vector2(250,405), Vector2(250,70), game.BAR_WINDOW_POS]); require(game.bar_player == game.BAR_WINDOW_POS, "rain window reachable")
	walk_route([Vector2(515,350), Vector2(515,145), game.BAR_DANCE_POS]); require(game.bar_player == game.BAR_DANCE_POS, "right dancefloor equipment reachable")
	for anchor in game.BAR_DANCE_NPC_ANCHORS:
		walk_route([Vector2(515,350), anchor]); require(game.bar_player == anchor, "reserved dancefloor anchor reachable")

	game.bar_player = game.BAR_MIX_POS
	var before_collision: Vector2 = game.bar_player
	game.move_bar_player(Vector2(-20,0))
	require(game.bar_player == before_collision, "player inside bar must not cross the solid left counter side")
	game.bar_player = Vector2(500,250)
	game.update_bar(0.0)
	require(game.interaction_hint != "开始调制", "ordinary counter edge must not trigger mixing")

	# The whole-room view keeps the mixing hotspot stable while the player walks.
	game.bar_player = Vector2(150,145)
	var first_camera: Vector2 = game.bar_camera_origin()
	require(first_camera == Vector2.ZERO, "whole-room camera origin must remain fixed")
	var first_screen: Vector2 = game.bar_world_to_screen(game.BAR_MIX_HOTSPOT.get_center())
	require(game.bar_screen_to_world(first_screen).distance_to(game.BAR_MIX_HOTSPOT.get_center()) <= 2.0, "whole-room world/screen conversion must round-trip the hotspot")
	mouse_move(first_screen)
	require(game.mix_hotspot_hovered and game.interaction_hint == "开始调制", "hotspot works at first camera origin")
	game.bar_player = game.BAR_MIX_POS
	game.update_bar(0.0)
	var second_screen: Vector2 = game.bar_world_to_screen(game.BAR_MIX_HOTSPOT.get_center())
	mouse_move(second_screen)
	require(game.mix_hotspot_hovered and first_screen == second_screen, "hotspot stays in place in the whole-room view")

	# Four distributed inspections have distinct feedback and tracked state; window observation persists into return.
	game.bar_mouse_active = false
	game.bar_player = game.BAR_WINDOW_POS; game.interact_bar(); var window_text: String = game.toast_text
	require(game.state.clues.has("rain_window_trace"), "rain window must set one-time tracked clue")
	game.bar_player = game.BAR_COASTER_POS; game.interact_bar(); var coaster_text: String = game.toast_text
	game.bar_player = game.BAR_ARCHIVE_POS; game.interact_bar(); var archive_text: String = game.toast_text
	game.bar_player = game.BAR_DANCE_POS; game.interact_bar(); var dance_text: String = game.toast_text
	require(window_text != coaster_text and coaster_text != archive_text and archive_text != dance_text and window_text != dance_text, "inspection feedback must be unique")
	require(game.dialogue_flags.get("coaster_seen", false) and game.dialogue_flags.get("archive_seen", false) and game.dialogue_flags.get("dancefloor_seen", false), "distributed inspections must record their own state")
	game.update_bar(0.0)
	require(game.interaction_hint == "E  聆听舞池节拍", "dancefloor equipment must expose its own nearby prompt")
	game.phase = game.Phase.RETURN_BAR
	game.bar_player = game.BAR_WINDOW_POS; game.interact_bar()
	require("改写后" in game.toast_text, "tracked window clue must change return-bar feedback")

	if failed:
		quit(1)
		return
	print("BAR_WORLD_PASS full_768x432_three_zones_h3_walk_interact_hotspot_collision_routes_dance_anchors_persistence")
	quit(0)
