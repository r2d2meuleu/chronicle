@tool
class_name ChronicleCompanion
extends Node

## Base class for companion nodes that bind to a Chronicle instance.

@export_group("Chronicle")
## Path to a Chronicle node. If empty, the Chronicle autoload singleton is used.
@export var chronicle_path: NodePath = NodePath("")

const NO_WATCH: int = -1

var _chronicle_override: Node = null
var _chronicle: ChronicleEngine = null
var _watch_id: int = NO_WATCH
var _state_reset_connected: bool = false
var _ready_done: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var resolved: Node = null
	if is_instance_valid(_chronicle_override) and _chronicle_override is ChronicleEngine:
		resolved = _chronicle_override
	else:
		resolved = _resolve_chronicle()
	if resolved == null:
		push_warning("[Chronicle] %s: no Chronicle instance found. Enable the Chronicle plugin or set chronicle_path." % name)
		return
	if not (resolved is ChronicleEngine):
		push_error("[Chronicle] Resolved node \"%s\" is not a Chronicle instance. Companion disabled." % resolved.name)
		return
	_chronicle = resolved
	_on_chronicle_ready()
	_safe_connect_state_reset()
	_ready_done = true


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	if not _ready_done:
		return
	var resolved: Node = null
	if is_instance_valid(_chronicle_override) and _chronicle_override is ChronicleEngine:
		resolved = _chronicle_override
	else:
		resolved = _resolve_chronicle()
	if resolved != _chronicle:
		_safe_unwatch()
		_safe_disconnect_state_reset()
		if resolved != null and resolved is ChronicleEngine:
			_chronicle = resolved
			_on_chronicle_reconnect()
			_safe_connect_state_reset()
		else:
			_chronicle = null
		return
	if is_instance_valid(_chronicle):
		_on_chronicle_reconnect()
		_safe_connect_state_reset()


func _exit_tree() -> void:
	if not _ready_done:
		return
	_safe_unwatch()
	_safe_disconnect_state_reset()


## Returns the Chronicle instance this companion is bound to, or [code]null[/code] if unresolved.
func get_chronicle() -> ChronicleEngine:
	return _chronicle


## Overrides the Chronicle instance this companion uses. Pass null to revert to ancestor resolution.
func set_chronicle(chronicle: ChronicleEngine) -> void:
	if chronicle != null and not chronicle.is_inside_tree():
		push_warning("[Chronicle] set_chronicle(): Chronicle instance is not in the scene tree. Add it first.")
		return
	_chronicle_override = chronicle
	if not _ready_done:
		return
	var resolved: Node = null
	if is_instance_valid(_chronicle_override) and _chronicle_override is ChronicleEngine:
		resolved = _chronicle_override
	else:
		resolved = _resolve_chronicle()
	if resolved == _chronicle:
		return
	_safe_unwatch()
	_safe_disconnect_state_reset()
	_chronicle = resolved
	if _chronicle != null:
		_safe_connect_state_reset()
		_on_chronicle_reconnect()


## Called once when a Chronicle instance is first resolved during [method _ready]. Set up initial watches and state here.
func _on_chronicle_ready() -> void:
	pass


## Called when the companion re-enters the scene tree or is bound to a new Chronicle via [method set_chronicle]. Re-register watches here.
func _on_chronicle_reconnect() -> void:
	pass


## Called after [method Chronicle.clear], rollback, or deserialization resets all state. [member _watch_id] is automatically reset to [constant NO_WATCH] before this hook fires.
func _on_state_reset() -> void:
	pass


func _on_state_reset_internal() -> void:
	_safe_unwatch()
	if is_queued_for_deletion():
		_safe_disconnect_state_reset()
		return
	_on_state_reset()


func _safe_unwatch() -> void:
	if _watch_id != NO_WATCH and is_instance_valid(_chronicle):
		_chronicle.unwatch(_watch_id)
	_watch_id = NO_WATCH


func _safe_connect_state_reset() -> void:
	if is_instance_valid(_chronicle) and not _state_reset_connected:
		if not _chronicle.state_reset.is_connected(_on_state_reset_internal):
			_chronicle.state_reset.connect(_on_state_reset_internal)
			_state_reset_connected = true


func _safe_disconnect_state_reset() -> void:
	if is_instance_valid(_chronicle) and _state_reset_connected:
		if _chronicle.state_reset.is_connected(_on_state_reset_internal):
			_chronicle.state_reset.disconnect(_on_state_reset_internal)
	_state_reset_connected = false


func _resolve_chronicle() -> Node:
	return ChronicleNodeUtils.resolve(self, chronicle_path)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if get_script() == ChronicleCompanion:
		warnings.append("ChronicleCompanion is a base class — subclass it to create a custom companion.")
	if not chronicle_path.is_empty():
		var resolved := get_node_or_null(chronicle_path)
		if resolved == null:
			warnings.append("chronicle_path '%s' does not resolve to a node." % str(chronicle_path))
		elif not (resolved is ChronicleEngine):
			warnings.append("chronicle_path '%s' points to '%s' which is not a Chronicle node." % [str(chronicle_path), resolved.get_class()])
	return warnings
