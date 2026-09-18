class_name Blind
extends Node

@onready var uniq: Node = $%SceneUnique

func keyword_reassign() -> void:
	var remote := {}
	remote = {"a": 1}
	helper_fn()

func col0_comment(a) -> void:
	match a:
		"x":
			helper_fn()
#			a commented-out line at column 0 reads as a dedent to the scanner
		"y":
			helper_fn()

func survives_after_blind_spot() -> void:
	helper_fn()

func helper_fn() -> void:
	pass
