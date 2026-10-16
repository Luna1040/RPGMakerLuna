extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func run() -> void:
 var g=load("res://main.tscn").instantiate();g.save_enabled=false;g.save_path="user://rogue-unused.json"
 root.add_child(g);g.set_process(false);g.launch();g.hazards.clear()
 var c=g.combat;c.muted=true
 c.roll_perks()
 check(c.offers.size()==3 and c.offers[0].id!=c.offers[1].id and c.offers[1].id!=c.offers[2].id and c.offers[0].id!=c.offers[2].id,"Offers unique")
 var id: String=c.offers[0].id;c.choose(0)
 check(c.stacks(id)==1 and c.run_level==2 and not c.choice,"Selecting upgrade applies exactly once")
 c.choose(0);check(c.stacks(id)==1,"Cannot purchase repeatedly")
 c.perks["power"]=3
 for i in 20:
  c.roll_perks()
  check(not c.offers.any(func(item):return item.id=="power"),"Max stack excluded")
 c.choice=false;c.passive_choice=false;c.perks.clear()
 c.shots.clear();c.shot(Vector2.ZERO,Vector2.RIGHT,0);var damage: float=c.shots[0].damage
 c.perks["power"]=2;c.shot(Vector2.ZERO,Vector2.RIGHT,0)
 check(is_equal_approx(c.shots[-1].damage,damage*1.4),"Damage modifier affects actual projectile")
 var radius: float=g.collect_radius();c.perks["magnet"]=2
 check(g.collect_radius()==radius+44,"Magnet modifies actual collection radius")
 c.offers=[c.PERKS[4]];c.choice=true;c.passive_choice=true;g.hull=2;c.choose(0)
 check(c.max_hull==4 and g.hull==3,"Armor raises max health and repairs")
 g.cargo=g.capacity();g.cargo_cores=9999;g.stars.clear();g.stars.append({"p":g.player,"core":true,"value":0,"phase":0.0})
 g.step_flight(.01,Vector2.ZERO)
 check(g.cargo_cores==10000,"Cores uncapped even when cargo full")
 c.bullets.clear()
 for i in 1000:c.add_bullet(Vector2(500,400),Vector2.ZERO,0)
 check(c.bullets.size()==160,"Enemy projectile budget enforced")
 c.shots.clear()
 for i in 1000:c.shot(Vector2.ZERO,Vector2.ZERO,0)
 check(c.shots.size()==200,"Friendly projectile budget enforced")
 g.bank_cargo();g.launch()
 check(c.perks.is_empty() and c.run_level==1 and c.max_hull==3,"New run resets temporary build")
 var start: float=g.flight_time;g._process(.1)
 check(is_equal_approx(g.flight_time-start,.1),"Slow rendering frame preserves simulation time")
 g.cargo=99999;g.stars.clear();g.stars.append({"p":g.player,"core":false,"value":5,"phase":0.0})
 g.step_flight(.01,Vector2.ZERO)
 check(g.cargo>=100004,"Stardust ignores cargo limits")
 c.shots.clear();c.weapon=0;c.rank=1;c.fire();var base_shots: int=c.shots.size();var base_size: float=c.shots[0].size
 c.shots.clear();c.perks["multishot"]=2;c.perks["colossal"]=2;c.fire()
 check(c.shots.size()==base_shots+4,"Multishot creates four real additional projectiles")
 check(c.shots[0].size>base_size*1.5,"Colossal changes visible projectile size")
 c.reset();c.fire_cd=100;c.step(.99);check(c.enemies.is_empty(),"Short opening grace period")
 c.step(.02);check(c.enemies.size()==6,"First formation arrives within 1.01 seconds")
 c.enemies.clear();c.spawn_cd=3;c.step(.61);check(c.enemies.size()==6,"Cleared formation quickly replenishes")
 for perk in c.PERKS:c.perks[perk.id]=3
 c.roll_perks()
 check(c.offers.size()==3 and c.offers.all(func(item):return str(item.id).begins_with("supply_")),"Maxed builds retain three supply choices")
 var cores_before: int=g.cargo_cores;c.choose(2)
 check(g.cargo_cores==cores_before+2 and not c.choice,"Third supply choice resolves without blocking combat")
 print("ROGUE TEST ","PASS" if failures==0 else "FAIL"," checks=",checks)
 g.free();quit(failures)
