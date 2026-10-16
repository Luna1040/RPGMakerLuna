extends SceneTree

func _initialize() -> void:
 var game = load("res://game.gd").new()
 game.new_run()
 assert(game.wave == 1 and game.enemies.size() == 6)
 game.enemies.clear()
 game.enemies.append({"pos":game.hero,"hp":100.0,"max":100.0,"cd":1.0,"boss":false})
 game.strike(false)
 assert(game.enemies[0].hp == 70)
 game.strike(false)
 assert(game.enemies[0].hp == 70, "Cooldown must prevent duplicate hit")
 game.strike(true)
 assert(game.enemies[0].hp == 7)
 game.hp = 0
 game._process(0)
 assert(game.state == "lose")
 game.new_run()
 game.wave = 4
 game.enemies.clear()
 game._process(0)
 assert(game.state == "win")
 game.hero = Vector2.ZERO
 game.new_run()
 assert(game.hero == Vector2(640,460) and game.hp == 180 and game.potions == 3)
 assert(game.skill_cd == 0 and game.level == 1 and game.wave == 1)
 game.free()
 print("PASS: damage, cooldown, victory, defeat, full restart")
 quit()
