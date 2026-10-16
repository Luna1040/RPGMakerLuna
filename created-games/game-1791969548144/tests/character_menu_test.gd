extends SceneTree

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var path := "res://tests/menu-fixture.json"
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 var game=load("res://canosa.gd").new()
 game.save_store.path=path
 assert(game.save_store.create(0,"确认框测试","战士",1704067200))
 var menu=load("res://character_menu.gd").new()
 root.add_child(menu)
 menu.setup(game)
 # Form has only warrior/mage. Slot-row deletion must open the confirmation popup.
 assert(menu.class_input.item_count==2)
 var row=menu.box.get_child(3)
 row.get_child(2).pressed.emit()
 assert(menu.pending_delete==0 and menu.confirm.visible)
 menu.confirm.canceled.emit()
 menu.confirm.hide()
 assert(game.save_store.slots[0]!=null and menu.pending_delete==-1)
 row.get_child(2).pressed.emit()
 menu.confirm.confirmed.emit()
 assert(game.save_store.slots[0]==null)
 menu.free()
 game.free()
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("PASS: native six-slot menu, two classes, deletion popup, cancel preserves, confirm deletes")
 quit()
