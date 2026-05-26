@tool
@icon("res://addons/chronicle/icons/recorder.svg")
class_name ChronicleRecorder
extends ChronicleCompanion

## Records a fact into Chronicle when a signal fires on the parent node.

## Emitted after a fact is successfully written. In [constant INCREMENT] mode, [param value] is the new total and [param old_value] is the pre-increment value ([code]0.0[/code] if absent).
signal fact_recorded(key: String, value: Variant, old_value: Variant)

enum RecordMode {
	## Records the fact only on the first trigger; subsequent triggers are ignored. [b]Not reset by [method Chronicle.clear] or rollback.[/b] Call [method reset] to re-arm.
	ONCE,
	## Records the fact every time the trigger signal fires.
	ALWAYS,
	## Increments a numeric fact by amount each time the trigger fires.
	INCREMENT,
}

@export_group("Trigger")
## Signal name on the parent node that triggers recording (e.g. "pressed").
@export var trigger_signal: String = ""

@export_group("Recording")
## Chronicle fact key to write (e.g. [code]"player.jumped"[/code]).
@export var fact_key: String = ""
## Value to record. Use the type dropdown (click the type icon) to change to int, float, String, etc. Ignored in [constant INCREMENT] mode.
@export var value: Variant = true
## How the recorder writes facts on each trigger.
@export var record_mode: RecordMode = RecordMode.ONCE
## Amount to increment per trigger. Only used in [constant INCREMENT] mode.
@export var amount: float = 1.0

@export_group("Options")
## Lifetime in seconds. Positive values auto-mark the fact transient. [code]0.0[/code] clears expiry. [constant ChronicleEngine.KEEP_LIFETIME] preserves the current expiry.
@export var lifetime: float = ChronicleEngine.KEEP_LIFETIME
## If [code]true[/code], the fact is excluded from serialization.
@export var transient: bool = false

var _has_fired: bool = false
var _connected: bool = false
var _bound_callable: Callable
var _connected_signal: String
var _connected_parent: Node = null
var _custom_trigger_fn: Callable


## Sets a custom recording function called instead of built-in [member record_mode] logic.
## Signature: [code]func(chronicle: Chronicle, key: String) -> void[/code]. Receives the Chronicle instance and [member fact_key]; responsible for calling [method Chronicle.set_fact] directly.
func set_custom_trigger(fn: Callable) -> void:
	_custom_trigger_fn = fn


## Returns [code]true[/code] if the recorder has fired at least once (relevant for [constant ONCE] mode).
func has_fired() -> bool:
	return _has_fired


## Resets a [constant ONCE]-mode recorder so it can fire again. Reconnects the trigger signal if it was disconnected after the first fire. No-op for [constant ALWAYS] and [constant INCREMENT] modes.
func reset() -> void:
	if not is_instance_valid(_chronicle):
		push_warning("[Chronicle] ChronicleRecorder \"%s\": reset() called but Chronicle instance is invalid." % name)
		return
	_has_fired = false
	if not _connected:
		_connect_signal()


func _on_chronicle_ready() -> void:
	super._on_chronicle_ready()
	add_to_group(ChronicleNodeUtils.GROUP_RECORDERS)
	_connect_signal()


func _on_chronicle_reconnect() -> void:
	super._on_chronicle_reconnect()
	if trigger_signal.is_empty() or fact_key.is_empty():
		return
	if record_mode == RecordMode.ONCE and _has_fired:
		return
	if _connected and is_instance_valid(_connected_parent):
		if _connected_parent.has_signal(_connected_signal) and _connected_parent.is_connected(_connected_signal, _bound_callable):
			_connected_parent.disconnect(_connected_signal, _bound_callable)
	_connected = false
	_connected_parent = null
	_connect_signal()


func _on_state_reset() -> void:
	super._on_state_reset()
	# ONCE means once per session, not per state — do not reset _has_fired.
	pass


func _connect_signal() -> void:
	if _connected:
		return

	var parent := get_parent()
	if parent == null:
		return

	if trigger_signal.is_empty() or fact_key.is_empty():
		return

	if not parent.has_signal(trigger_signal):
		push_error("[Chronicle] Signal \"%s\" not found on parent node \"%s\" — Recorder will never fire." % [trigger_signal, parent.name])
		return

	var arg_count := _get_signal_arg_count(parent, trigger_signal)
	if arg_count > 0:
		_bound_callable = _on_triggered.unbind(arg_count)
	else:
		_bound_callable = _on_triggered
	parent.connect(trigger_signal, _bound_callable)
	_connected_signal = trigger_signal
	_connected_parent = parent
	_connected = true


func _exit_tree() -> void:
	super._exit_tree()
	if not _ready_done:
		return
	if _connected:
		if _connected_parent != null and is_instance_valid(_connected_parent):
			if _connected_parent.is_connected(_connected_signal, _bound_callable):
				_connected_parent.disconnect(_connected_signal, _bound_callable)
		_connected_parent = null
		_connected = false


func _on_triggered() -> void:
	if not is_instance_valid(_chronicle):
		return
	if record_mode == RecordMode.ONCE and _has_fired:
		return
	if _custom_trigger_fn.is_valid():
		_custom_trigger_fn.call(_chronicle, fact_key)
		if record_mode == RecordMode.ONCE:
			_has_fired = true
		return
	match record_mode:
		RecordMode.ONCE, RecordMode.ALWAYS:
			if not _chronicle.is_valid_type(value):
				push_warning("[Chronicle] ChronicleRecorder \"%s\": value type %s is not storable." % [name, type_string(typeof(value))])
				return
			var old_value: Variant = _chronicle.get_fact(fact_key)
			_chronicle.set_fact(fact_key, value, transient, lifetime)
			if record_mode == RecordMode.ONCE:
				_has_fired = true
			fact_recorded.emit(fact_key, value, old_value)
		RecordMode.INCREMENT:
			var old_value: Variant = _chronicle.get_fact(fact_key, 0.0)
			var result: Variant = _chronicle.increment_fact(fact_key, amount, transient, lifetime)
			if result == null:
				return
			fact_recorded.emit(fact_key, result, old_value)


func _validate_property(property: Dictionary) -> void:
	if property.name == "amount" and record_mode != RecordMode.INCREMENT:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "value" and record_mode == RecordMode.INCREMENT:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()
	if trigger_signal.is_empty():
		warnings.append("No trigger_signal set — this Recorder will never fire.")
	if fact_key.is_empty():
		warnings.append("No fact_key set — this Recorder has nothing to write.")
	if not trigger_signal.is_empty():
		var parent := get_parent()
		if parent != null and not parent.has_signal(trigger_signal):
			warnings.append("Signal \"%s\" not found on parent \"%s\"." % [trigger_signal, parent.name])
	if record_mode == RecordMode.ONCE:
		warnings.append("ONCE mode does not reset on Chronicle.clear() or rollback. Call Recorder.reset() to re-arm.")
	if value != null and record_mode != RecordMode.INCREMENT:
		if is_instance_valid(_chronicle):
			if not _chronicle.is_valid_type(value):
				warnings.append("'value' type %s is not a storable Chronicle type." % type_string(typeof(value)))
		else:
			var t: int = typeof(value)
			if t not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_ARRAY, TYPE_DICTIONARY]:
				warnings.append("Cannot verify 'value' type — no Chronicle resolved at edit time.")
	return warnings


static func _get_signal_arg_count(obj: Object, signal_name: String) -> int:
	for sig: Dictionary in obj.get_signal_list():
		if sig["name"] == signal_name:
			return sig["args"].size()
	return 0
