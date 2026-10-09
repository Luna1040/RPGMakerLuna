extends "res://actor.gd"

# Each selectable part already contains clothing AND visible skin.
# No neutral body texture is loaded by this actor.
var top_style := "armor"
var arm_style := "armor"
var leg_style := "armor"
var cape_style := "blue"
var wardrobe_ready := false

func _ready() -> void:
	super._ready()
	for look in ["casual","bikini"]:
		make_part(look+"_torso",78,Vector2(.5,.02),5.2)
		for side in ["near","far"]:
			var depth := -6.0 if side == "far" else 2.0
			make_part(look+"_"+side+"_thigh",UPPER_LEG/.78,Vector2(.50,.10),depth)
			make_part(look+"_"+side+"_shin",LOWER_LEG/.91,Vector2(.38,.03),depth+.2)
			make_part(look+"_"+side+"_boot",17.5,Vector2(.38,.17),depth+.3)
			make_part(look+"_"+side+"_upper_arm",UPPER_ARM/.72,Vector2(.5,.15),-5 if side == "far" else 10)
			make_part(look+"_"+side+"_forearm",LOWER_ARM/.82,Vector2(.5,.09),-4 if side == "far" else 13)
			for suffix in ["thigh","shin","boot","upper_arm","forearm"]:
				if side == "far": mats[look+"_"+side+"_"+suffix].set_shader_parameter("tint",Color(.88,.91,.97))
	wardrobe_ready = true
	set_pose("idle",0)

func apply_preset(name_: String) -> void:
	if name_ in ["armor_blue","armor_red"]:
		top_style = "armor"
		arm_style = "armor"
		leg_style = "armor"
		outfit = "red" if name_ == "armor_red" else "blue"
		cape_style = outfit
	else:
		top_style = name_
		arm_style = name_
		leg_style = name_
		cape_style = "none"
	set_pose(current_action,current_frame)

func set_pose(action: String,frame: int,blend := 0.0,time_ := 0.0) -> void:
	super.set_pose(action,frame,blend,time_)
	if not wardrobe_ready: return
	var pose_ := targets(action,frame)
	if blend > 0:
		var count := 4 if action == "walk" else (6 if action == "slash" else 1)
		var next := targets(action,mini(frame+1,count-1) if action == "slash" else (frame+1)%count)
		for key in pose_: pose_[key] = lerp(pose_[key],next[key],blend)
	var body: Vector2 = pose_.body
	for side in ["near","far"]:
		for suffix in ["thigh","shin","boot"]: parts[side+"_"+suffix].visible = leg_style == "armor"
		for suffix in ["upper_arm","forearm","joint"]: parts[side+"_"+suffix].visible = arm_style == "armor"
		for look in ["casual","bikini"]:
			segment(look+"_"+side+"_thigh",joints[side+"_hip"],joints[side+"_knee"])
			segment(look+"_"+side+"_shin",joints[side+"_knee"],joints[side+"_ankle"])
			place(look+"_"+side+"_boot",joints[side+"_ankle"])
			segment(look+"_"+side+"_upper_arm",joints[side+"_shoulder"],joints[side+"_elbow"])
			segment(look+"_"+side+"_forearm",joints[side+"_elbow"],joints[side+"_hand"])
			for suffix in ["thigh","shin","boot"]: parts[look+"_"+side+"_"+suffix].visible = leg_style == look
			for suffix in ["upper_arm","forearm"]: parts[look+"_"+side+"_"+suffix].visible = arm_style == look
	for color in ["blue","red"]:
		parts["torso_"+color].visible = top_style == "armor" and outfit == color
		parts["cape_"+color].visible = show_cape and cape_style == color
	for look in ["casual","bikini"]:
		place(look+"_torso",Vector2(0,-163)+body)
		parts[look+"_torso"].visible = top_style == look

func wardrobe_key() -> String:
	return "%s_%s_%s_%s_%s_%s_view%d" % [top_style,arm_style,leg_style,outfit,cape_style,"hair" if show_hair else "short",int(angle)]
