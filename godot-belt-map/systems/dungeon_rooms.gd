extends RefCounted
const NAMES := ["古塔 · 封印前厅","古塔 · 守卫回廊","古塔 · 陨星王座"]
const CELLS := [Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]
const FOREST_NAMES := ["旧林道 · 灰誓哨站","旧林道 · 守卫回廊","旧林道 · 陨星王座"]
const PACKS := [
	["melee","melee","melee","melee","melee","ranged","ranged"],
	["elite","elite","melee","melee","melee","melee","melee","ranged","ranged"],
	["boss","elite","melee","melee","ranged","ranged"]
]
static func configure(contract: Dictionary, run: Dictionary) -> void:
	var room:=clampi(int(run.get("room",0)),0,2)
	var forest:bool=contract.get("zone_id","")=="forest"
	var names:Array=FOREST_NAMES if forest else NAMES
	contract.name=names[room]
	contract.room=room
	contract.spawn={"x":3.2,"depth":7.6,"z":0}
	contract.bounds.depth=4.0
	contract.bounds.depth_size=5.2
	if forest: contract.bounds.width=12.8
	contract.portals=[{"id":"room_return","label":"返回城镇","x":1.6,"depth":7.6,"target":"return","arrival":[3.0,7.4] if forest else [22.2,4.0]}]
	if room<2:
		contract.portals.append({"id":"next_room","label":"下一间 · "+names[room+1],"x":12.5 if forest else (23.5 if room==0 else 20.0),"depth":7.5 if room==0 else 4.5,"target":"room","room":room+1})
	contract.encounter_roster=PACKS[room].duplicate()
	contract.encounter_points=[[7,5],[8.5,7.5],[9.8,4.5],[6.5,6.4],[10.2,8.5],[9,6],[6,8.2],[10.3,5.3],[7.8,8.6]]
