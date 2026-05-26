class_name ChronicleNodeUtils
extends RefCounted

const AUTOLOAD_NAME := "Chronicle"
const AUTOLOAD_PATH := "/root/" + AUTOLOAD_NAME

const GROUP_GATES: StringName = &"chronicle_gates"
const GROUP_REACTORS: StringName = &"chronicle_reactors"
const GROUP_RECORDERS: StringName = &"chronicle_recorders"


static func resolve(node: Node, chronicle_path: NodePath) -> Node:
	# Tier 1: Explicit path
	if not chronicle_path.is_empty():
		var found := node.get_node_or_null(chronicle_path)
		if found is ChronicleEngine:
			return found
		push_warning("[Chronicle] chronicle_path '%s' did not resolve to a Chronicle node" % chronicle_path)
		return null
	# Tier 2: Ancestor walk
	var current := node.get_parent()
	while current != null:
		if current is ChronicleEngine:
			return current
		current = current.get_parent()
	# Tier 3: Autoload fallback
	if not node.is_inside_tree():
		return null
	return node.get_node_or_null(AUTOLOAD_PATH)
