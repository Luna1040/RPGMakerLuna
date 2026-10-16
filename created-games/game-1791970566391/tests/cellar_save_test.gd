extends SceneTree

var failed := false

func _init() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("CELLAR_SAVE_FAIL: " + message)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await process_frame
	game.persistence_enabled = true
	var path := ProjectSettings.globalize_path("res://tests/.cellar-roundtrip-%d.cfg" % OS.get_process_id())
	game.state.credits = 250
	require(game.state.buy_drink("reverse_fire"), "test purchase must succeed")
	game.save_cellar(path)
	require(FileAccess.file_exists(path), "cellar file must be written")
	game.state = load("res://run_state.gd").new()
	game.load_cellar(path)
	require(game.state.credits == 130, "remaining credits must survive file reload")
	require(game.state.is_drink_unlocked("reverse_fire"), "purchased variety must survive file reload")
	require(game.state.is_drink_unlocked("still_sea") and game.state.is_drink_unlocked("empathy") and game.state.is_drink_unlocked("stable"), "starter varieties must remain unlocked")
	DirAccess.remove_absolute(path)
	if failed:
		quit(1)
		return
	print("CELLAR_SAVE_PASS credits_unlocks_roundtrip")
	quit(0)
