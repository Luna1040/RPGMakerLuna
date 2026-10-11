extends Node
## Transient scene handoff only. Durable data belongs to SaveStore, never scene nodes.
var pending: Dictionary = {}
var target_zone := "town"

func take() -> Dictionary:
	var result := pending
	pending = {}
	return result
