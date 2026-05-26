@tool
@icon("res://addons/chronicle/icons/reactor.svg")
class_name ChronicleReactor
extends ChronicleCompanion

## Fires a callback when facts matching a pattern appear in Chronicle.

## Emitted when a fact matches [member watch_pattern] and [member react_to] filter. [param old_value] is [code]null[/code] for CREATION events; [param value] is [code]null[/code] for ERASURE events.
signal fact_matched(key: String, value: Variant, old_value: Variant)

enum ReactTo {
	## Fires on any change (creation, modification, or erasure).
	ANY,
	## Fires only when a fact is created ([param old_value] is [code]null[/code]). Also fires during state-reset replay for facts that already exist — use [method reset] to re-arm a [member one_shot] reactor after load.
	CREATION,
	## Fires only when an existing fact's value changes (excludes creation and erasure).
	CHANGE,
	## Fires only when a fact is erased (value is null).
	ERASURE,
}

@export_group("Pattern")
## Glob pattern for fact keys to watch (e.g. "quest.*").
@export var watch_pattern: String = ""
## Filters which fact events trigger this reactor.
@export var react_to: ReactTo = ReactTo.ANY
## When true, fires once then auto-unwatches. Call [method reset] to re-arm.
@export var one_shot: bool = false

@export_group("Callback")
## Called on parent with (key, value, old_value). Optional if using fact_matched signal.
@export var target_method: String = ""

var _has_fired: bool = false
var _filter_fn: Callable


## Adds an additional filter callable. Signature: fn(key: String, value: Variant, old_value: Variant) -> bool. Return false to suppress.
func set_filter(fn: Callable) -> void:
	_filter_fn = fn


func _reconnect_watch() -> void:
	_safe_unwatch()
	_has_fired = false
	if watch_pattern.is_empty():
		return
	if not is_instance_valid(_chronicle):
		return
	_watch_id = _chronicle.watch(watch_pattern, _on_match)


func _on_chronicle_ready() -> void:
	super._on_chronicle_ready()
	add_to_group(ChronicleNodeUtils.GROUP_REACTORS)

	if watch_pattern.is_empty():
		push_error("[Chronicle] \"%s\": no watch_pattern set — Reactor will never match." % name)
		return

	_watch_id = _chronicle.watch(watch_pattern, _on_match)
	if _watch_id < 0:
		push_error("[Chronicle] \"%s\": invalid watch_pattern \"%s\"." % [name, watch_pattern])


func _on_chronicle_reconnect() -> void:
	super._on_chronicle_reconnect()
	if one_shot and _has_fired:
		return
	_reconnect_watch()


## Re-arms a [member one_shot] reactor so it can fire again. Reconnects the watch if needed.
func reset() -> void:
	_reconnect_watch()


## After state_reset, existing facts are replayed as CREATION events.
## This is intentional — from the reactor's perspective, the world is new.
func _on_state_reset() -> void:
	super._on_state_reset()
	_reconnect_watch()
	if _watch_id < 0:
		return
	if react_to == ReactTo.CHANGE or react_to == ReactTo.ERASURE:
		return
	if not is_instance_valid(_chronicle):
		return
	var keys: Array[String] = _chronicle.get_fact_keys(watch_pattern)
	for key: String in keys:
		if _has_fired:
			break
		var value: Variant = _chronicle.get_fact(key)
		_on_match(key, value, null)


func _on_match(key: String, value: Variant, old_value: Variant) -> void:
	if _has_fired:
		return

	var is_new: bool = old_value == null
	match react_to:
		ReactTo.CREATION:
			if not is_new:
				return
		ReactTo.CHANGE:
			if is_new or value == old_value or value == null:
				return
		ReactTo.ERASURE:
			if value != null:
				return
		ReactTo.ANY:
			pass

	if _filter_fn.is_valid() and not _filter_fn.call(key, value, old_value):
		return

	if one_shot:
		_has_fired = true
		_safe_unwatch()

	fact_matched.emit(key, value, old_value)

	var parent := get_parent()
	if not target_method.is_empty() and parent != null and parent.has_method(target_method):
		parent.call(target_method, key, value, old_value)
	elif not target_method.is_empty() and parent != null:
		push_warning("[Chronicle] ChronicleReactor: method \"%s\" not found on parent \"%s\"." % [target_method, parent.name])


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()
	if watch_pattern.is_empty():
		warnings.append("No watch_pattern set — this Reactor will never match.")
	else:
		var err: String = _chronicle.validate_pattern(watch_pattern) if is_instance_valid(_chronicle) else ChroniclePatternMatcher.validate(watch_pattern)
		if not err.is_empty():
			warnings.append("\"watch_pattern\" is invalid: %s" % err)
	if not target_method.is_empty():
		var parent := get_parent()
		if parent != null and not parent.has_method(target_method):
			warnings.append("Method \"%s\" not found on parent \"%s\"." % [target_method, parent.name])
	return warnings
