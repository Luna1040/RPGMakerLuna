extends Node2D
## A real deterministic platform course rendered directly onto the 3D screen.
const SIZE := Vector2(640,360)
const SPEED := 130.0
const GRAVITY := 950.0
const JUMP := -350.0
const FINISH_X := 4320.0
var player := Vector2(35,290)
var velocity := Vector2.ZERO
var grounded := false
var active := false
var won := false
var dead := false
var checkpoint := Vector2(35,290)
var checkpoints_passed := 0
var deaths := 0
var time_played := 0.0
var camera_x := 0.0
var fixed_remainder:=0.0
var redraw_revision:=0
const FIXED_STEP:=1.0/120
var keys := {}
var mouse_axis := 0.0
var jump_queued := false
var coyote := 0.0
var jump_buffer := 0.0
var platforms: Array[Rect2] = []
var hazards: Array[Rect2] = []
var font: Font

func _ready() -> void:
	font=load("res://font.ttf")
	for i in range(12):
		platforms.append(Rect2(i*360,310,305,50))
		# Accessible elevated bonus ledge; lower path remains physically playable.
		platforms.append(Rect2(i*360+175,236,70,14))
		if i in [1,3,5,7,9,11]:hazards.append(Rect2(i*360+82,292,28,18))
	platforms.append(Rect2(4320,310,320,50))
	queue_redraw()

func set_active(value: bool) -> void:
	if active!=value:redraw_revision+=1;queue_redraw()
	active=value
	if not active:keys.clear();mouse_axis=0; jump_queued=false;jump_buffer=0;fixed_remainder=0

func key_input(event: InputEventKey) -> void:
	if event.keycode in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]:keys[event.keycode]=event.pressed
	if event.pressed and not event.echo:
		if event.keycode==KEY_SPACE:jump_queued=true
		if event.keycode==KEY_R and dead:retry()

func pointer(pos: Vector2, pressed: bool) -> void:
	if not pressed:return
	if dead:retry();return
	if pos.y>285:
		if pos.x<160:mouse_axis=0 if mouse_axis==-1 else -1
		elif pos.x<340:mouse_axis=0 if mouse_axis==1 else 1
		else:jump_queued=true
	else:jump_queued=true

func retry() -> void:
	if not dead:return
	dead=false;player=checkpoint;velocity=Vector2.ZERO;grounded=false;jump_buffer=0;keys.clear();mouse_axis=0
	fixed_remainder=0;redraw_revision+=1;queue_redraw()

func die() -> void:
	if dead:return
	dead=true;deaths+=1;velocity=Vector2.ZERO;mouse_axis=0;keys.clear();redraw_revision+=1;queue_redraw()

func _physics_process(delta: float) -> void:
	if active:advance(delta)
	queue_redraw()

func advance(delta: float) -> void:
	if not active or won or dead:return
	fixed_remainder+=delta
	while fixed_remainder+0.0000001>=FIXED_STEP and not won and not dead:
		fixed_remainder-=FIXED_STEP
		advance_fixed(FIXED_STEP)
	redraw_revision+=1;queue_redraw()

func advance_fixed(delta:float) -> void:
	time_played+=delta
	var direction:=mouse_axis
	if keys.get(KEY_A,false) or keys.get(KEY_LEFT,false):direction-=1
	if keys.get(KEY_D,false) or keys.get(KEY_RIGHT,false):direction+=1
	velocity.x=clampf(direction,-1,1)*SPEED
	if grounded:coyote=.09
	else:coyote=maxf(0,coyote-delta)
	if jump_queued:jump_buffer=.12;jump_queued=false
	else:jump_buffer=maxf(0,jump_buffer-delta)
	if jump_buffer>0 and coyote>0:velocity.y=JUMP;grounded=false;coyote=0;jump_buffer=0
	var old_bottom:=player.y+20
	velocity.y+=GRAVITY*delta
	player+=velocity*delta
	player.x=maxf(8,player.x)
	grounded=false
	if velocity.y>=0:
		for p in platforms:
			if player.x+16>p.position.x and player.x<p.end.x and old_bottom<=p.position.y+1 and player.y+20>=p.position.y:
				player.y=p.position.y-20;velocity.y=0;grounded=true;break
	for h in hazards:
		if Rect2(player,Vector2(16,20)).intersects(h):die()
	if player.y>420:die()
	for mark in [1440.0,2880.0]:
		if player.x>=mark and checkpoint.x<mark and grounded:
			checkpoint=Vector2(mark+12,290);checkpoints_passed+=1
	if player.x>=FINISH_X and grounded:won=true;keys.clear();mouse_axis=0
	camera_x=clampf(player.x-180,0,FINISH_X-450)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),Color("17323c"))
	# Original vector illustration with layered coast silhouettes; real moving playfield.
	for i in range(13):
		var x:=i*95-fmod(camera_x*.18,95)
		draw_colored_polygon(PackedVector2Array([Vector2(x-50,270),Vector2(x+30,120+(i%3)*25),Vector2(x+115,270)]),Color("244a50"))
	draw_circle(Vector2(500,85),29,Color("ddbe80"))
	for p in platforms:
		var r:=Rect2(p.position-Vector2(camera_x,0),p.size)
		if r.end.x<0 or r.position.x>640:continue
		draw_rect(r,Color("46796d"));draw_rect(Rect2(r.position,Vector2(r.size.x,5)),Color("9dbb86"))
		for x in range(int(r.position.x)+8,int(r.end.x),22):draw_line(Vector2(x,r.position.y+17),Vector2(x+7,r.position.y+17),Color("315451"),2)
	for h in hazards:
		var x:=h.position.x-camera_x
		for i in range(3):draw_colored_polygon(PackedVector2Array([Vector2(x+i*10,310),Vector2(x+5+i*10,292),Vector2(x+10+i*10,310)]),Color("db8971"))
	for mark in [1440.0,2880.0,FINISH_X]:
		var x:float=mark-camera_x
		draw_line(Vector2(x,255),Vector2(x,310),Color("e9d9a1"),3)
		draw_colored_polygon(PackedVector2Array([Vector2(x,255),Vector2(x+25,266),Vector2(x,278)]),Color("c7aa6c"))
	var pp:=player-Vector2(camera_x,0)
	draw_rect(Rect2(pp+Vector2(2,7),Vector2(12,13)),Color("e6b779"));draw_circle(pp+Vector2(8,5),7,Color("e7d3a6"));draw_rect(Rect2(pp+Vector2(9,3),Vector2(4,3)),Color("213b3d"))
	if font==null:return
	draw_string(font,Vector2(18,25),"海岸快递  ·  到达灯塔",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("ecdfbc"))
	draw_string(font,Vector2(400,25),"%d%%  ·  旗帜 %d/2" % [mini(100,int(player.x/FINISH_X*100)),checkpoints_passed],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("b8cfbd"))
	draw_style_box(button_style(mouse_axis<0),Rect2(10,322,142,32))
	draw_style_box(button_style(mouse_axis>0),Rect2(165,322,166,32))
	draw_style_box(button_style(),Rect2(348,322,278,32))
	draw_string(font,Vector2(26,344),"◀ 左 · 点停" if mouse_axis<0 else "◀ 左 · 点走",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	draw_string(font,Vector2(185,344),"右 ▶ · 点停" if mouse_axis>0 else "右 ▶ · 点走",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	draw_string(font,Vector2(416,344),"跳跃 / 空格",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	if dead or won or not active:
		draw_rect(Rect2(105,103,430,112),Color(0.05,0.12,0.14,.94))
		var title: String="灯塔送达 · 任务二完成" if won else ("掉进海里了 · R / 点击重试" if dead else "已暂停 · 点屏幕继续")
		draw_string(font,Vector2(126,145),title,HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("efcf90"))
	draw_string(font,Vector2(126,180),"方向键移动，空格跳；点方向常走，再点停",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("c7d3bd"))

func button_style(selected: bool=false) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=Color("577d63") if selected else Color(0.08,.20,.23,.90);s.set_corner_radius_all(5);return s
