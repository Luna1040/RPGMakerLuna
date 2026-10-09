extends "res://actor.gd"

var top_style := "armor"
var arm_style := "armor"
var leg_style := "armor"
var cape_style := "blue"
var skin_tone := "warm"
var wardrobe_ready := false

func _ready() -> void:
	super._ready()
	make_part("base_torso",78,Vector2(.5,.02),4.7)
	for side in ["near","far"]:
		var depth := -6.0 if side == "far" else 2.0
		make_part("base_"+side+"_thigh",UPPER_LEG/.78,Vector2(.50,.10),depth-.1)
		make_part("base_"+side+"_shin",LOWER_LEG/.91,Vector2(.38,.03),depth+.1)
		make_part("base_"+side+"_boot",17.5,Vector2(.38,.17),depth+.15)
		make_part("base_"+side+"_upper_arm",UPPER_ARM/.72,Vector2(.5,.15),-5.1 if side == "far" else 9.9)
		make_part("base_"+side+"_forearm",LOWER_ARM/.82,Vector2(.5,.09),-4.1 if side == "far" else 12.9)
		make_part("casual_"+side+"_boot",21,Vector2(.38,.30),depth+.5)
		make_part("casual_"+side+"_sleeve",22,Vector2(.5,.15),-4.8 if side == "far" else 10.2)
		make_part("casual_"+side+"_bracer",22,Vector2(.5,.08),-3.8 if side == "far" else 13.2)
	for name_ in ["casual","dress","swim"]:
		make_part(name_+"_torso",74,Vector2(.50,.02),5.2)
	wardrobe_ready = true
	set_pose("idle",0)

func apply_preset(name_: String) -> void:
	match name_:
		"armor_blue", "armor_red":
			top_style = "armor"
			arm_style = "armor"
			leg_style = "armor"
			outfit = "red" if name_ == "armor_red" else "blue"
			cape_style = outfit
		"casual":
			top_style = "casual"
			arm_style = "casual"
			leg_style = "boots"
			cape_style = "none"
		"dress":
			top_style = "dress"
			arm_style = "none"
			leg_style = "boots"
			cape_style = "none"
		"swim", "base":
			top_style = "swim" if name_ == "swim" else "none"
			arm_style = "none"
			leg_style = "none"
			cape_style = "none"
	set_pose(current_action,current_frame)

func set_pose(action: String,frame: int,blend := 0.0,time_ := 0.0) -> void:
	super.set_pose(action,frame,blend,time_)
	if not wardrobe_ready:
		return
	var pose_ := targets(action,frame)
	if blend > 0:
		var count := 4 if action == "walk" else (6 if action == "slash" else 1)
		var next := targets(action,mini(frame+1,count-1) if action == "slash" else (frame+1)%count)
		for key in pose_:
			pose_[key] = lerp(pose_[key],next[key],blend)
	var body: Vector2 = pose_.body
	place("base_torso",Vector2(0,-163)+body)
	for side in ["near","far"]:
		var hip: Vector2 = joints[side+"_hip"]
		var knee: Vector2 = joints[side+"_knee"]
		var ankle: Vector2 = joints[side+"_ankle"]
		var shoulder: Vector2 = joints[side+"_shoulder"]
		var elbow: Vector2 = joints[side+"_elbow"]
		var palm: Vector2 = joints[side+"_hand"]
		segment("base_"+side+"_thigh",hip,knee)
		segment("base_"+side+"_shin",knee,ankle)
		place("base_"+side+"_boot",ankle)
		segment("base_"+side+"_upper_arm",shoulder,elbow)
		segment("base_"+side+"_forearm",elbow,palm)
		segment("casual_"+side+"_sleeve",shoulder,elbow)
		segment("casual_"+side+"_bracer",elbow.lerp(palm,.48),palm)
		place("casual_"+side+"_boot",ankle)
		for suffix in ["thigh","shin","boot"]:
			parts[side+"_"+suffix].visible = leg_style == "armor"
			parts["base_"+side+"_"+suffix].visible = leg_style != "armor" if suffix != "boot" else leg_style == "none"
		for suffix in ["upper_arm","forearm","joint"]:
			parts[side+"_"+suffix].visible = arm_style == "armor"
		for suffix in ["upper_arm","forearm"]:
			parts["base_"+side+"_"+suffix].visible = arm_style != "armor"
		for suffix in ["sleeve","bracer"]:
			parts["casual_"+side+"_"+suffix].visible = arm_style == "casual"
		parts["casual_"+side+"_boot"].visible = leg_style == "boots"
	for color in ["blue","red"]:
		parts["torso_"+color].visible = top_style == "armor" and outfit == color
		parts["cape_"+color].visible = show_cape and cape_style == color
	parts.base_torso.visible = top_style != "armor"
	for name_ in ["casual","dress","swim"]:
		place(name_+"_torso",Vector2(0,-157)+body)
		parts[name_+"_torso"].visible = top_style == name_
	var tint := Color.WHITE
	if skin_tone == "deep":
		tint = Color(.74,.57,.43)
	elif skin_tone == "cool":
		tint = Color(.94,.95,1)
	for key in mats:
		if key.begins_with("base_"):
			mats[key].set_shader_parameter("tint",tint*(Color(.84,.87,.91) if key.begins_with("base_far") else Color.WHITE))

func wardrobe_key() -> String:
	return "%s_%s_%s_%s_%s_%s" % [top_style,arm_style,leg_style,outfit,cape_style,skin_tone]
