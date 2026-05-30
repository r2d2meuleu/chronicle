extends Node
class_name ChronicleSpyNode

var calls: Array[Dictionary] = []

func on_fact(key: String, value: Variant, old_value: Variant = null) -> void:
	calls.append({key = key, value = value, old_value = old_value})
