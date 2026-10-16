extends SceneTree
var samples: Array[float]=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var g=load("res://main.tscn").instantiate();g.save_enabled=false;g.save_path="user://perf-no-save.json"
 root.add_child(g);current_scene=g;g.launch();g.hazards.clear();g.combat.muted=true
 g.combat.elapsed=150;g.combat.choices_taken=3;g.combat.rank=4;g.hit_cd=1000
 g.combat.step(.01)
 for i in 160:
  g.combat.add_bullet(Vector2(400+(i%16)*30,220+(i/16)*42),Vector2.ZERO,i%3)
  g.combat.bullets[-1].life=100
 await create_timer(2).timeout
 for phase in ["battle","hidden"]:
  if phase=="hidden":g.hide()
  samples.clear();var start=Time.get_ticks_msec()
  while Time.get_ticks_msec()-start<4000:
   var now=Time.get_ticks_usec();await process_frame;samples.append((Time.get_ticks_usec()-now)/1000.0)
  samples.sort();print("PERF ",phase," fps=",1000.0/(samples.reduce(func(a,b):return a+b,0.0)/samples.size())," p95_ms=",samples[int(samples.size()*.95)]," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," process_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000)
 quit()
