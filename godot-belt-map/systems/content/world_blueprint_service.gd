extends Node
## Compiles declarative Agent world plans into existing, prebuilt belt-map
## contracts. It never evaluates generated scripts or accepts asset paths.

const BLUEPRINT_SCHEMA := "world-blueprint/1"
const BUNDLE_SCHEMA := "world-bundle/1"
const MAX_ZONES := 8
const MAX_LANDMARKS := 32
const BIOMES := ["grassland","forest","desert","snow","swamp","mountain","cavern","city","spirit_realm"]
const KINDS := ["building","tree","crate","water","wall","fountain"]
const ASSETS := {"asset.world.inn":"inn","asset.world.tree":"tree","asset.world.crate":"crate","asset.world.fountain":"fountain"}
const KIND_ASSETS := {"building":["asset.world.inn"],"tree":["asset.world.tree"],"crate":["asset.world.crate"],
	"water":["asset.world.fountain"],"fountain":["asset.world.fountain"],"wall":[]}

static func validate_shape(value:Variant)->Array[String]:
	var errors:Array[String]=[]
	if not value is Dictionary: return ["World blueprint must be an object."]
	var blueprint:Dictionary=value
	_unknown(blueprint,["schema_version","blueprint_id","project_id","genre","lore_summary","initial_zone_id","regions","zones"],"blueprint",errors)
	if blueprint.get("schema_version")!=BLUEPRINT_SCHEMA: errors.append("Unsupported world blueprint schema_version.")
	if not _scoped(str(blueprint.get("blueprint_id","")),"blueprint"): errors.append("blueprint.blueprint_id must be canonical.")
	if not _scoped(str(blueprint.get("project_id","")),"project"): errors.append("blueprint.project_id must be canonical.")
	_text(blueprint.get("genre"),64,"blueprint.genre",errors)
	_text(blueprint.get("lore_summary"),2000,"blueprint.lore_summary",errors)
	if not _scoped(str(blueprint.get("initial_zone_id","")),"zone"): errors.append("blueprint.initial_zone_id must be canonical.")
	var regions=blueprint.get("regions")
	var region_ids:Dictionary={}
	if not regions is Array or regions.is_empty() or regions.size()>8:
		errors.append("blueprint.regions must contain 1 to 8 regions.")
	else:
		for index in range(regions.size()):
			var region=regions[index]
			var location:="blueprint.regions[%d]" % index
			if not region is Dictionary:
				errors.append(location+" must be an object.")
				continue
			_unknown(region,["region_id","name","summary"],location,errors)
			var region_id:=str(region.get("region_id",""))
			if not _scoped(region_id,"region") or region_ids.has(region_id): errors.append(location+".region_id must be unique and canonical.")
			region_ids[region_id]=true
			_text(region.get("name"),80,location+".name",errors)
			_text(region.get("summary"),500,location+".summary",errors)
	var zones=blueprint.get("zones")
	var zone_ids:Dictionary={}
	if not zones is Array or zones.is_empty() or zones.size()>MAX_ZONES:
		errors.append("blueprint.zones must contain 1 to %d zones." % MAX_ZONES)
		return errors
	for zone in zones:
		if zone is Dictionary: zone_ids[str(zone.get("zone_id",""))]=true
	if not zone_ids.has(str(blueprint.get("initial_zone_id",""))): errors.append("blueprint.initial_zone_id is not present in zones.")
	var seen_zones:Dictionary={}
	for index in range(zones.size()):
		var zone=zones[index]
		var location:="blueprint.zones[%d]" % index
		if not zone is Dictionary:
			errors.append(location+" must be an object.")
			continue
		_unknown(zone,["zone_id","region_id","name","biome","town_npcs","bounds","spawn","landmarks","exits"],location,errors)
		var zone_id:=str(zone.get("zone_id",""))
		if not _scoped(zone_id,"zone") or seen_zones.has(zone_id): errors.append(location+".zone_id must be unique and canonical.")
		seen_zones[zone_id]=true
		if not region_ids.has(str(zone.get("region_id",""))): errors.append(location+".region_id is unknown.")
		_text(zone.get("name"),80,location+".name",errors)
		if zone.get("biome") not in BIOMES: errors.append(location+".biome is unsupported.")
		if not zone.get("town_npcs") is bool: errors.append(location+".town_npcs must be boolean.")
		_validate_zone_geometry(zone,zone_ids,location,errors)
	if errors.is_empty(): _validate_reachability(blueprint,errors)
	return errors

func compile_blueprint(value:Variant)->Dictionary:
	var errors:=validate_shape(value)
	if not errors.is_empty(): return {"ok":false,"errors":errors,"world_bundle":{}}
	var blueprint:Dictionary=value
	var contracts:Dictionary={}
	for zone:Dictionary in blueprint.zones:
		var volumes:Array[Dictionary]=[]
		for landmark:Dictionary in zone.landmarks:
			var volume:={"id":str(landmark.landmark_id),"kind":str(landmark.kind),
				"x":float(landmark.x),"depth":float(landmark.depth),"width":float(landmark.width),
				"depth_size":float(landmark.depth_size),"base_z":0.0,"height":float(landmark.height),
				"solid":bool(landmark.solid),"standable":bool(landmark.standable)}
			var asset_id:=str(landmark.get("asset_id",""))
			if not asset_id.is_empty():
				volume.asset=ASSETS[asset_id]
				volume.visualHeight=float(landmark.get("visual_height",landmark.height))
			if landmark.kind in ["water","fountain"]: volume.shape="ellipse"
			volumes.append(volume)
		contracts[str(zone.zone_id)]={"version":1,"projection":"side-facing-belt","worldLocationId":str(zone.region_id),
			"worldMapId":str(zone.zone_id),"biome":str(zone.biome),"name":str(zone.name),"units":"meters",
			"projectionParameters":{"pixelsPerMeter":120,"depthPixelsPerMeter":45,"originY":410},
			"bounds":{"x":0.7,"depth":0.5,"width":float(zone.bounds.width),"depth_size":float(zone.bounds.depth_size)},
			"spawn":{"x":float(zone.spawn.x),"depth":float(zone.spawn.depth),"z":0.0},"volumes":volumes,
			"zone_id":str(zone.zone_id),"town_npcs":bool(zone.town_npcs),"chests":[],"exits":zone.exits.duplicate(true),
			"generated_by":"world-blueprint-compiler/1","aiRequirements":["Use only registered asset IDs","Keep depth separate from jump height","Preserve a walkable spawn and exit route"],
			"limitations":["Generated layout uses the prebuilt courtyard renderer and registered prop library."]}
	var bundle:={"schema_version":BUNDLE_SCHEMA,"blueprint_id":str(blueprint.blueprint_id),"project_id":str(blueprint.project_id),
		"genre":str(blueprint.genre),"lore_summary":str(blueprint.lore_summary),"initial_zone_id":str(blueprint.initial_zone_id),
		"regions":blueprint.regions.duplicate(true),"zones":contracts}
	bundle["world_hash"]=_hash(bundle)
	return {"ok":true,"errors":[],"world_bundle":bundle}

func validate_world_bundle(value:Variant)->Array[String]:
	if not value is Dictionary: return ["Compiled world bundle must be an object."]
	var bundle:Dictionary=value
	var errors:Array[String]=[]
	_unknown(bundle,["schema_version","blueprint_id","project_id","genre","lore_summary","initial_zone_id","regions","zones","world_hash"],"world_bundle",errors)
	if bundle.get("schema_version")!=BUNDLE_SCHEMA: errors.append("Unsupported world bundle schema_version.")
	if not bundle.get("zones") is Dictionary or bundle.zones.is_empty() or bundle.zones.size()>MAX_ZONES: errors.append("world_bundle.zones is invalid.")
	if not bundle.get("world_hash") is String or bundle.world_hash!=_hash(bundle,"world_hash"): errors.append("World bundle checksum does not match its contents.")
	if bundle.get("zones") is Dictionary:
		if not bundle.zones.has(str(bundle.get("initial_zone_id",""))): errors.append("World bundle initial zone is missing.")
		for zone_id in bundle.zones:
			var contract=bundle.zones[zone_id]
			if not contract is Dictionary or contract.get("zone_id")!=zone_id or not contract.get("bounds") is Dictionary or not contract.get("spawn") is Dictionary or not contract.get("volumes") is Array:
				errors.append("World bundle contains an invalid map contract: "+str(zone_id))
	return errors

static func _validate_zone_geometry(zone:Dictionary,zone_ids:Dictionary,location:String,errors:Array[String])->void:
	var bounds=zone.get("bounds")
	if not bounds is Dictionary:
		errors.append(location+".bounds must be an object.")
		return
	_unknown(bounds,["width","depth_size"],location+".bounds",errors)
	_number(bounds.get("width"),12.0,25.0,location+".bounds.width",errors)
	_number(bounds.get("depth_size"),5.0,9.0,location+".bounds.depth_size",errors)
	var spawn=zone.get("spawn")
	if not spawn is Dictionary:
		errors.append(location+".spawn must be an object.")
		return
	_unknown(spawn,["x","depth"],location+".spawn",errors)
	_number(spawn.get("x"),0.95,float(bounds.get("width",0.0))+0.45,location+".spawn.x",errors)
	_number(spawn.get("depth"),0.75,float(bounds.get("depth_size",0.0))+0.25,location+".spawn.depth",errors)
	var landmarks=zone.get("landmarks")
	var seen:Dictionary={}
	if not landmarks is Array or landmarks.size()>MAX_LANDMARKS:
		errors.append(location+".landmarks must contain at most %d entries." % MAX_LANDMARKS)
	else:
		for index in range(landmarks.size()):
			var item=landmarks[index]
			var item_location:="%s.landmarks[%d]" % [location,index]
			if not item is Dictionary:
				errors.append(item_location+" must be an object.")
				continue
			_unknown(item,["landmark_id","kind","x","depth","width","depth_size","height","solid","standable","asset_id","visual_height"],item_location,errors)
			var landmark_id:=str(item.get("landmark_id",""))
			if not _scoped(landmark_id,"landmark") or seen.has(landmark_id): errors.append(item_location+".landmark_id must be unique and canonical.")
			seen[landmark_id]=true
			var kind:=str(item.get("kind",""))
			if kind not in KINDS: errors.append(item_location+".kind is unsupported.")
			for field in ["x","depth","width","depth_size","height"]: _number(item.get(field),0.1,25.0,item_location+"."+field,errors)
			if not item.get("solid") is bool or not item.get("standable") is bool: errors.append(item_location+" collision flags must be boolean.")
			var asset_id:=str(item.get("asset_id",""))
			if not KIND_ASSETS.get(kind,[]).has(asset_id) and not (kind=="wall" and asset_id.is_empty()): errors.append(item_location+".asset_id is not registered for its kind.")
			if item.has("visual_height"): _number(item.visual_height,0.25,8.0,item_location+".visual_height",errors)
			if float(item.get("x",0))+float(item.get("width",0))>float(bounds.get("width",0))+0.7 or float(item.get("depth",0))+float(item.get("depth_size",0))>float(bounds.get("depth_size",0))+0.5:
				errors.append(item_location+" exceeds zone bounds.")
			if bool(item.get("solid",false)) and Rect2(float(item.get("x",0)),float(item.get("depth",0)),float(item.get("width",0)),float(item.get("depth_size",0))).grow(.24).has_point(Vector2(float(spawn.get("x",0)),float(spawn.get("depth",0)))):
				errors.append(item_location+" blocks the player spawn.")
	var exits=zone.get("exits")
	if not exits is Array or exits.size()>12:
		errors.append(location+".exits must contain at most 12 entries.")
	else:
		var exit_ids:Dictionary={}
		for index in range(exits.size()):
			var exit=exits[index]
			var exit_location:="%s.exits[%d]" % [location,index]
			if not exit is Dictionary:
				errors.append(exit_location+" must be an object.")
				continue
			_unknown(exit,["exit_id","to_zone_id","x","depth"],exit_location,errors)
			var exit_id:=str(exit.get("exit_id",""))
			if not _scoped(exit_id,"exit") or exit_ids.has(exit_id): errors.append(exit_location+".exit_id must be unique and canonical.")
			exit_ids[exit_id]=true
			if not zone_ids.has(str(exit.get("to_zone_id",""))) or exit.get("to_zone_id")==zone.get("zone_id"): errors.append(exit_location+".to_zone_id is invalid.")
			_number(exit.get("x"),0.95,float(bounds.get("width",0))+0.45,exit_location+".x",errors)
			_number(exit.get("depth"),0.75,float(bounds.get("depth_size",0))+0.25,exit_location+".depth",errors)
		if errors.is_empty():
			for exit:Dictionary in exits:
				if not _walkable_route(zone,Vector2(float(spawn.x),float(spawn.depth)),Vector2(float(exit.x),float(exit.depth))):
					errors.append(location+" has no walkable route from spawn to "+str(exit.exit_id)+".")

static func _walkable_route(zone:Dictionary,start:Vector2,target:Vector2)->bool:
	const STEP:=0.5
	var width:=float(zone.bounds.width)
	var depth_size:=float(zone.bounds.depth_size)
	var columns:=floori(width/STEP)+1
	var rows:=floori(depth_size/STEP)+1
	var to_cell:=func(point:Vector2): return Vector2i(clampi(roundi((point.x-0.7)/STEP),0,columns-1),clampi(roundi((point.y-0.5)/STEP),0,rows-1))
	var start_cell:Vector2i=to_cell.call(start)
	var target_cell:Vector2i=to_cell.call(target)
	var queue:Array[Vector2i]=[start_cell]
	var visited:Dictionary={}
	while not queue.is_empty():
		var cell:Vector2i=queue.pop_front()
		if visited.has(cell): continue
		visited[cell]=true
		if cell==target_cell: return true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:Vector2i=cell+offset
			if next.x<0 or next.y<0 or next.x>=columns or next.y>=rows or visited.has(next): continue
			var point:=Vector2(0.7+float(next.x)*STEP,0.5+float(next.y)*STEP)
			if point.x<0.92 or point.y<0.72 or point.x>width+0.48 or point.y>depth_size+0.28: continue
			if not _blueprint_blocked(zone.landmarks,point): queue.append(next)
	return false

static func _blueprint_blocked(landmarks:Array,point:Vector2)->bool:
	for landmark in landmarks:
		if not landmark is Dictionary: continue
		if not bool(landmark.get("solid",false)) and landmark.get("kind")!="water": continue
		var rectangle:=Rect2(float(landmark.get("x",0)),float(landmark.get("depth",0)),float(landmark.get("width",0)),float(landmark.get("depth_size",0))).grow(.22)
		if rectangle.has_point(point): return true
	return false

static func _validate_reachability(blueprint:Dictionary,errors:Array[String])->void:
	var graph:Dictionary={}
	for zone:Dictionary in blueprint.zones:
		graph[str(zone.zone_id)]=[]
		for exit:Dictionary in zone.exits: graph[str(zone.zone_id)].append(str(exit.to_zone_id))
	var visited:Dictionary={}
	var queue:Array=[str(blueprint.initial_zone_id)]
	while not queue.is_empty():
		var current:String=queue.pop_front()
		if visited.has(current): continue
		visited[current]=true
		for neighbor in graph.get(current,[]):
			if not visited.has(neighbor): queue.append(neighbor)
	if visited.size()!=graph.size(): errors.append("Every generated zone must be reachable from initial_zone_id.")

static func _unknown(value:Dictionary,allowed:Array,location:String,errors:Array[String])->void:
	for key in value:
		if key not in allowed: errors.append(location+" contains unsupported field: "+str(key))

static func _text(value:Variant,maximum:int,location:String,errors:Array[String])->void:
	if not value is String or value.strip_edges().is_empty() or value.length()>maximum: errors.append(location+" must be non-empty text of at most %d characters." % maximum)

static func _number(value:Variant,minimum:float,maximum:float,location:String,errors:Array[String])->void:
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)<minimum or float(value)>maximum: errors.append(location+" must be between %.2f and %.2f." % [minimum,maximum])

static func _scoped(value:String,prefix:String)->bool:
	var expression:=RegEx.new()
	return value.length()<=128 and expression.compile("^"+prefix+"\\.[a-z0-9][a-z0-9_.-]+$")==OK and expression.search(value)!=null

static func _hash(value:Dictionary,excluded:String="")->String:
	var content:=value.duplicate(true)
	if not excluded.is_empty(): content.erase(excluded)
	var normalized=JSON.parse_string(JSON.stringify(content,"",true,true))
	return JSON.stringify(normalized,"",true,true).sha256_text()
