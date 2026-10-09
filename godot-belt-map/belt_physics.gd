extends RefCounted
## Logical world coordinates are meters: x, depth and independent height z.
const RADIUS := 0.22
const BODY_HEIGHT := 2.2
const STEP := 0.15
const GRAVITY := 15.0
const JUMP_SPEED := 6.36
const JUMP_RISE := JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY)

static func overlaps(v: Dictionary, p: Vector2) -> bool:
	var r: Rect2 = Rect2(float(v.x),float(v.depth),float(v.width),float(v.depth_size))
	if v.get("shape", "rectangle")=="ellipse":
		var relative := (p-r.get_center())/(r.size/2.0+Vector2.ONE*RADIUS)
		return relative.length_squared()<1.0-0.000001
	var closest := Vector2(clampf(p.x,r.position.x,r.end.x),clampf(p.y,r.position.y,r.end.y))
	return p.distance_squared_to(closest) < RADIUS * RADIUS - 0.000001

static func blocked(volumes: Array, p: Vector2, z: float) -> bool:
	for v: Dictionary in volumes:
		if bool(v.solid) and overlaps(v,p) and z < float(v.base_z)+float(v.height)-0.001 and z+BODY_HEIGHT > float(v.base_z)+0.001:
			return true
	return false

static func support(volumes: Array, p: Vector2, ceiling: float = INF) -> Dictionary:
	var floor_z := 0.0
	var platform := ""
	for v: Dictionary in volumes:
		var top := float(v.base_z)+float(v.height)
		if bool(v.standable) and overlaps(v,p) and top <= ceiling+0.001 and top >= floor_z:
			floor_z=top
			platform=str(v.id)
	if floor_z==0.0:
		for v: Dictionary in volumes:
			if v.kind=="water" and overlaps(v,p):
				return {"valid":false,"z":0.0,"platform":""}
	return {"valid":true,"z":floor_z,"platform":platform}

static func step_position(volumes: Array, bounds: Rect2, from: Vector2, delta: Vector2, z: float, grounded: bool) -> Vector2:
	var p := from
	var n := maxi(1,int(ceil(delta.length()/0.06)))
	for _i in n:
		# Separate axes provide sliding along trunks and walls without diagonal tunnelling.
		for axis in 2:
			var candidate := p
			candidate[axis] += delta[axis]/n
			candidate.x=clampf(candidate.x,bounds.position.x+RADIUS,bounds.end.x-RADIUS)
			candidate.y=clampf(candidate.y,bounds.position.y+RADIUS,bounds.end.y-RADIUS)
			if blocked(volumes,candidate,z):
				continue
			if grounded:
				var s := support(volumes,candidate,z+STEP)
				if not s.valid or float(s.z)>z+STEP:
					continue
			p=candidate
	return p
