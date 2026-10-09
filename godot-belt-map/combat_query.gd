extends RefCounted
## Shared logical hit volume for targets and breakable props. Pixel reach comes
## from the character, while ground depth and elevation stay in world meters.
static func overlaps(foot: Vector2, z: float, rectangle: Rect2, target_z: float, target_height: float, event: Dictionary) -> bool:
	if z > target_z+target_height+0.15 or z+1.8 < target_z:
		return false
	var closest := Vector2(clampf(foot.x,rectangle.position.x,rectangle.end.x),clampf(foot.y,rectangle.position.y,rectangle.end.y))
	var delta := closest-foot
	var reach := float(event.get("range",240))/120.0
	var depth := float(event.get("depth_radius", 0.6))
	if event.get("shape", "fan") == "radial":
		depth = float(event.get("depth_radius",1.2))
		return delta.x*delta.x/(reach*reach) + delta.y*delta.y/(depth*depth) <= 1.0
	var forward := delta.x * float(event.get("facing",1))
	return forward >= -0.18 and forward <= reach and absf(delta.y) <= depth
