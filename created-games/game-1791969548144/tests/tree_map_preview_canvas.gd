extends Node2D
var map: RefCounted
func _ready() -> void:
 map=load("res://client_tree_city.gd").new()
 map.setup()
 queue_redraw()
func _draw() -> void:
 if map==null: return
 map.draw_ground(self,map.SPAWN)
 draw_circle(Vector2(640,430),6,Color("ffdf7e"))
