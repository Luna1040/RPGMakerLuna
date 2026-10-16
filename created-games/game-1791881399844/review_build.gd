extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var g=load("res://main.tscn").instantiate();g.save_enabled=false;g.save_path="user://rogue-review-unused.json"
 root.add_child(g);current_scene=g;g.launch();g.player=Vector2(300,440);g.combat.muted=true
 g.combat.elapsed=150;g.combat.choices_taken=3;g.hit_cd=100
 g.combat.perks={"multishot":2,"colossal":2,"frost":1,"chain":1};g.combat.rank=4;g.combat.run_level=7
 g.combat.step(.01);g.combat.enemies[0].hp=999999;g.combat.enemies[0].max=999999
 await create_timer(3).timeout
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://evolved-projectiles.png")
 g.combat.roll_perks();g.queue_redraw()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://rogue-preview.png")
 quit()
