@tool
@icon("res://addons/chronicle/icons/gate.svg")
class_name ChronicleGate
extends ChronicleCompanion

## Enables/disables a target node based on a Chronicle condition expression.

const ExprParser := preload("res://addons/chronicle/core/expression/parser.gd")

## Emitted on transition from closed to open (not on every evaluation).
signal gate_opened
## Emitted on transition from open to closed (not on every evaluation).
signal gate_closed

enum GateMode {
	## Hides and disables the target when the condition is false.
	HIDE_WHEN_FALSE,
	## Inverted: shows the target when the condition is false.
	SHOW_WHEN_FALSE,
	## Permanently queue_free()s the target (and this gate) when the condition becomes true.
	QUEUE_FREE_WHEN_TRUE,
	## Emits signals only; does not modify the target node.
	SIGNAL_ONLY,
}

@export_group("Condition")
## Chronicle expression evaluated to determine gate state (e.g. "quest.started AND NOT quest.done").
@export var condition: String = ""
## When true, missing facts resolve to true instead of null so the condition is not automatically false.
@export var default_when_missing: bool = false

@export_group("Behavior")
## Determines how this gate affects its target node.
@export var gate_mode: GateMode = GateMode.HIDE_WHEN_FALSE
## Node affected by the gate. Defaults to the parent if empty.
@export var target_path: NodePath = ""

var _ast: Variant = null
var _is_open: bool = false
var _resolver: Callable
var _key_warn_dedup: Dictionary[String, bool] = {}
var _original_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _in_transition: bool = false
var _in_apply: bool = false
var _deferred_pending: bool = false
var _deferred_count: int = 0
const _MAX_DEFERRED_RETRIES: int = 3

## Optional override called instead of built-in gate modes. Signature: func(is_open: bool, target: Node) -> void.
var _custom_apply_fn: Callable

static var _editor_engine: ChronicleExpressionEngine


## Sets a custom function called instead of built-in gate modes. Signature: [code]fn(is_open: bool, target: Node) -> void[/code].
## [br][b]Note:[/b] [param target] may be [code]null[/code] if no target node is resolved. [method is_open] still reflects inversion from [member gate_mode].
func set_custom_apply(fn: Callable) -> void:
	_custom_apply_fn = fn


## Parses a condition expression string into an AST. Uses the bound Chronicle instance at runtime, or a standalone engine in the editor. Returns the AST on success, or [code]null[/code] on parse error.
func parse_condition(cond: String) -> Variant:
	if is_instance_valid(_chronicle):
		return _chronicle.parse_expression(cond)
	if not _editor_engine:
		_editor_engine = ChronicleExpressionEngine.new()
	return _editor_engine.parse(cond)


func _warn_unresolved_keys() -> void:
	if _ast == null or not is_instance_valid(_chronicle):
		return
	var keys: Array[String] = _chronicle.extract_expression_keys(_ast)
	for key: String in keys:
		if key in _key_warn_dedup:
			continue
		if not _chronicle.has_fact(key):
			_key_warn_dedup[key] = true
			push_warning("[Chronicle] Gate \"%s\": key '%s' has never been set — condition evaluates as false." % [name, key])


func _build_resolver() -> Callable:
	if default_when_missing:
		return func(key: String) -> Variant:
			if not is_instance_valid(_chronicle):
				return null
			if _chronicle.has_fact(key):
				return _chronicle.get_fact(key)
			return true
	return func(key: String) -> Variant:
		if not is_instance_valid(_chronicle):
			return null
		return _chronicle.get_fact(key)


func _on_chronicle_ready() -> void:
	super._on_chronicle_ready()
	add_to_group(ChronicleNodeUtils.GROUP_GATES)

	if condition.is_empty():
		push_error("[Chronicle] \"%s\": no condition set — Gate will never activate." % name)
		return

	_key_warn_dedup.clear()
	_ast = _chronicle.parse_expression(condition)
	if _ast == null:
		push_error("[Chronicle] Could not parse condition: \"%s\". Check console for parse details." % condition)
		return

	_resolver = _build_resolver()
	_setup_watches()

	var target := _get_target()
	if target != null and target.process_mode != Node.PROCESS_MODE_DISABLED:
		_original_process_mode = target.process_mode

	# Evaluate once for initial state
	var result: bool = _chronicle.evaluate_expression(_ast, _resolver)
	_apply_gate(result)
	if not result:
		_warn_unresolved_keys()


func _rewire_watches() -> void:
	_safe_unwatch()
	_key_warn_dedup.clear()
	_resolver = _build_resolver()
	_setup_watches()
	_reevaluate()


func _on_chronicle_reconnect() -> void:
	super._on_chronicle_reconnect()
	var target := _get_target()
	if target != null and target.process_mode != Node.PROCESS_MODE_DISABLED:
		_original_process_mode = target.process_mode
	if _ast == null:
		return
	_rewire_watches()


## Returns [code]true[/code] if the gate effect is active (target is visible/enabled). In [constant SHOW_WHEN_FALSE] mode, the gate is open when the condition is [code]false[/code].
func is_open() -> bool:
	return _is_open


func _setup_watches() -> void:
	if not is_instance_valid(_chronicle):
		return
	var keys: Array[String] = _chronicle.extract_expression_keys(_ast)
	if keys.size() == 1:
		_watch_id = _chronicle.watch(keys[0], _on_dep_changed)
	elif keys.size() > 1:
		_watch_id = _chronicle.watch_any(keys, _on_dep_changed)


func _reevaluate() -> void:
	if _in_apply:
		if not _deferred_pending and _deferred_count < _MAX_DEFERRED_RETRIES:
			_deferred_pending = true
			_deferred_count += 1
			_reevaluate.call_deferred()
		elif _deferred_count >= _MAX_DEFERRED_RETRIES:
			push_warning("[Chronicle] Gate: deferred reevaluate loop detected, stopping after %d retries" % _MAX_DEFERRED_RETRIES)
		return
	_deferred_count = 0
	if _ast == null or not is_instance_valid(_chronicle):
		return
	_deferred_pending = false
	_in_apply = true
	var result: bool = _chronicle.evaluate_expression(_ast, _resolver)
	_apply_gate(result)
	if not result:
		_warn_unresolved_keys()
	_in_apply = false


func _on_dep_changed(_key: String, _value: Variant, _old_value: Variant) -> void:
	_reevaluate()


func _on_state_reset() -> void:
	super._on_state_reset()
	if _ast == null:
		return
	_rewire_watches()


func _get_target() -> Node:
	if not target_path.is_empty():
		return get_node_or_null(target_path)
	return get_parent()


func _transition_to(new_is_open: bool) -> void:
	if new_is_open == _is_open or _in_transition:
		return
	_in_transition = true
	_is_open = new_is_open
	if _is_open:
		gate_opened.emit()
	else:
		gate_closed.emit()
	_in_transition = false


func _apply_gate(result: bool) -> void:
	if _custom_apply_fn.is_valid():
		var is_open: bool = result if gate_mode != GateMode.SHOW_WHEN_FALSE else not result
		_custom_apply_fn.call(is_open, _get_target())
		_transition_to(is_open)
		return
	match gate_mode:
		GateMode.SIGNAL_ONLY:
			_transition_to(result)
		GateMode.HIDE_WHEN_FALSE:
			_apply_hide_when_false(result)
		GateMode.SHOW_WHEN_FALSE:
			_apply_show_when_false(result)
		GateMode.QUEUE_FREE_WHEN_TRUE:
			_apply_queue_free_when_true(result)


func _apply_hide_when_false(result: bool) -> void:
	var target := _get_target()
	if target == null or not is_instance_valid(target):
		return
	if result:
		_show_target(target)
	else:
		_hide_target(target)
	_transition_to(result)


func _apply_show_when_false(result: bool) -> void:
	var target := _get_target()
	if target == null or not is_instance_valid(target):
		return
	if result:
		_hide_target(target)
	else:
		_show_target(target)
	_transition_to(not result)


func _apply_queue_free_when_true(result: bool) -> void:
	var target := _get_target()
	if target == null or not is_instance_valid(target):
		return
	if result:
		target.queue_free()
		_safe_unwatch()
		_safe_disconnect_state_reset()
		_ast = null
		_transition_to(true)
		queue_free()
		return
	_transition_to(false)


func _show_target(target: Node) -> void:
	if "visible" in target:
		target.visible = true
	target.process_mode = _original_process_mode


func _hide_target(target: Node) -> void:
	if target.process_mode != Node.PROCESS_MODE_DISABLED:
		_original_process_mode = target.process_mode
	if "visible" in target:
		target.visible = false
	target.process_mode = Node.PROCESS_MODE_DISABLED


func _validate_property(property: Dictionary) -> void:
	if property.name == "target_path" and gate_mode == GateMode.SIGNAL_ONLY:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()
	if gate_mode == GateMode.QUEUE_FREE_WHEN_TRUE:
		warnings.append("QUEUE_FREE_WHEN_TRUE will permanently destroy both the target node and this Gate when the condition becomes true. Not reversible by rollback.")
	if gate_mode != GateMode.SIGNAL_ONLY and not target_path.is_empty():
		var target := get_node_or_null(target_path)
		if target == null:
			warnings.append("target_path '%s' does not resolve to a node." % str(target_path))
	if condition.is_empty():
		warnings.append("No condition set — this Gate will never activate.")
	else:
		var ast: Variant = parse_condition(condition)
		if ast == null:
			warnings.append("\"condition\" has parse errors: \"%s\"." % condition)
		else:
			var dep_keys: Array[String]
			if is_instance_valid(_chronicle):
				dep_keys = _chronicle.extract_expression_keys(ast)
			else:
				if not _editor_engine:
					_editor_engine = ChronicleExpressionEngine.new()
				dep_keys = _editor_engine.extract_keys(ast)
			if dep_keys.is_empty():
				warnings.append("Condition \"%s\" has no fact key references — gate state is static and will never update." % condition)
			warnings.append_array(_collect_in_key_warnings(ast))
			warnings.append_array(_collect_matches_warnings(ast))
	return warnings


func _collect_in_key_warnings(ast: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	var walk_fn: Callable = func(node: Dictionary) -> void:
		if node.get("node_type") == ExprParser.NODE_IN and node.rhs.get("rhs_type", "") == "key":
			result.append("'%s' is used as an IN collection. Ensure it holds an Array at runtime." % node.rhs.value)
	if is_instance_valid(_chronicle):
		_chronicle.walk_expression_ast(ast, walk_fn)
	else:
		if not _editor_engine:
			_editor_engine = ChronicleExpressionEngine.new()
		_editor_engine.walk_ast(ast, walk_fn)
	return result


func _collect_matches_warnings(ast: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	var walk_fn: Callable = func(node: Dictionary) -> void:
		if node.get("node_type") == ExprParser.NODE_MATCHES and node.get("pattern", "") == "":
			result.append("MATCHES pattern is empty — condition will only match the empty string.")
	if is_instance_valid(_chronicle):
		_chronicle.walk_expression_ast(ast, walk_fn)
	else:
		if not _editor_engine:
			_editor_engine = ChronicleExpressionEngine.new()
		_editor_engine.walk_ast(ast, walk_fn)
	return result
