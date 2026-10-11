extends SceneTree
const TalentTree = preload("res://systems/core/talent_tree.gd")
const Progression = preload("res://systems/core/progression.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var tree := TalentTree.new()
	var progression := Progression.new()
	verify(tree.spent_points() == 0 and tree.bonuses().attack == 0, "New character has free talents")
	verify(not tree.spend("blade_training", progression) and not tree.spend("unknown", progression), "Unfunded/unknown talent accepted")
	verify(not tree.spend("blade_training", null), "Null progression accepted")
	progression.add_xp(1000000000)
	verify(progression.skill_points == 49, "Test progression not at cap")
	verify(not tree.can_spend("execution", progression), "Tier 2 available without prerequisites")
	var before := progression.skill_points
	verify(not tree.spend("execution", progression) and progression.skill_points == before and tree.spent_points() == 0, "Rejected talent transaction consumed points")
	verify(tree.spend("blade_training", progression), "Tier 1 could not be learned")
	verify(not tree.spend("execution", progression), "One prerequisite rank unlocks tier 2")
	verify(tree.spend("blade_training", progression) and tree.spend("execution", progression), "Tier 2 did not unlock at required rank")
	verify(tree.rank("blade_training") == 2 and tree.rank("execution") == 1 and tree.bonuses().attack == 10 and tree.bonuses().speed == 5, "Talent bonuses do not reflect ranks")
	verify(tree.spent_points() + progression.skill_points == progression.level - 1, "Skill point balance drifted after learning")
	for id in TalentTree.CATALOG:
		for _rank in range(0, 3):
			if tree.rank(id) < 3:
				verify(tree.spend(id, progression), "Could not fill talent rank: " + id)
		verify(not tree.spend(id, progression), "Talent exceeds rank cap: " + id)
	var bonus := tree.bonuses()
	verify(tree.spent_points() == 18 and progression.skill_points == 31, "Six capped talents cost the wrong number of points")
	verify(bonus.attack == 21 and bonus.magic == 21 and bonus.health == 54 and bonus.mana == 15 and bonus.defense == 9 and bonus.speed == 15 and bonus.regen == 1.5, "Fully trained stats incorrect")
	var saved := tree.snapshot()
	var copy := TalentTree.new()
	verify(copy.restore(JSON.parse_string(JSON.stringify(saved))) and copy.snapshot() == saved, "Talent JSON round-trip lost ranks")
	var previous := copy.snapshot()
	for bad in [
		{"version": 99, "ranks": {}},
		{"version": 1, "ranks": {"blade_training": -1}},
		{"version": 1, "ranks": {"blade_training": 4}},
		{"version": 1, "ranks": {"blade_training": 0.5}},
		{"version": 1, "ranks": {"blade_training": "2"}},
		{"version": 1, "ranks": {"blade_training": INF}},
		{"version": 1, "ranks": {"execution": 1}},
		{"version": 1, "ranks": {"unknown": 1}},
		{"version": 1, "ranks": []}
	]:
		verify(not copy.restore(bad) and copy.snapshot() == previous, "Invalid talent restore changed live ranks: " + str(bad))
	verify(copy.restore({"version": 1, "ranks": {}}) and copy.spent_points() == 0, "Sparse initial talent save did not fill zero ranks")
	verify(tree.refund(progression) == 18 and tree.spent_points() == 0 and progression.skill_points == 49, "Refund did not restore points and reset talents together")
	verify(tree.refund(progression) == 0 and progression.skill_points == 49, "Repeated refund creates skill points")
	progression.skill_points = 99
	verify(not tree.spend("vitality", progression), "Over-awarded progression creates talents")
	progression.skill_points = 49
	tree.spend("vitality", progression)
	progression.skill_points = 49
	verify(tree.refund(progression) == 0 and tree.rank("vitality") == 1, "Inconsistent refund creates points or destroys ranks")
	progression.skill_points = 48
	var captured: Array = []
	progression.changed.connect(func(): captured.append(tree.spent_points() + progression.skill_points))
	verify(tree.spend("vitality", progression), "Signal consistency setup failed")
	verify(captured == [49], "Progression observer saw partially committed talent spend")
	captured.clear()
	verify(tree.refund(progression) == 2 and captured == [49], "Progression observer saw partially committed refund")
	# A progression signal cannot recursively spend/refund the same in-flight transaction.
	var reentered: Array = []
	progression.changed.connect(func(): reentered.append(tree.spend("blade_training", progression)))
	verify(tree.spend("blade_training", progression) and reentered == [false] and tree.rank("blade_training") == 1, "Signal reentrancy double-spent a talent")
	verify(tree.last_error.is_empty(), "Successful transaction retained a rejected reentrant operation's error")
	# RefCounted signal closures reference the fixtures; disconnect before releasing them.
	for connection in progression.get_signal_connection_list("changed"):
		progression.disconnect("changed", connection.callable)
	print("CORE_TALENTS_TEST %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
