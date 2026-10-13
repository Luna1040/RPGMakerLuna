extends RefCounted
const NAMES := ["古塔 · 封印前厅","古塔 · 守卫回廊","古塔 · 陨星王座"]
const CELLS := [Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]
static func configure(contract: Dictionary, run: Dictionary) -> void:
	var room:=clampi(int(run.get("room",0)),0,2)
	contract.name=NAMES[room]
	contract.room=room
	contract.bounds.depth=4.0
	contract.bounds.depth_size=5.2
	contract.portals=[{"id":"room_return","label":"返回城镇","x":1.6,"depth":7.6,"target":"return","arrival":[22.2,4.0]}]
	if room<2:
		contract.portals.append({"id":"next_room","label":"下一间 · "+NAMES[room+1],"x":23.5 if room==0 else 20.0,"depth":7.5 if room==0 else 4.5,"target":"room","room":room+1})
	contract.encounter_points=[[9,5],[11,7.5],[12,4.5],[14,6.4]]
