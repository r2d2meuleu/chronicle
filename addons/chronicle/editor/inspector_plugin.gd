@tool
extends EditorInspectorPlugin

const ChronicleFactRegistry := preload("res://addons/chronicle/editor/fact_registry.gd")

var _fact_registry: ChronicleFactRegistry = ChronicleFactRegistry.new()
var _ever_rebuilt: bool = false

class _FactKeyProperty extends EditorProperty:
	enum _Mode { FACT_KEY, WATCH_PATTERN }

	var _line_edit: LineEdit
	var _status_label: Label
	var _mode: _Mode
	var _updating: bool = false
	var _registry: ChronicleFactRegistry = null

	func _init(mode: _Mode, registry: ChronicleFactRegistry = null) -> void:
		_mode = mode
		_registry = registry

	func _ready() -> void:
		if _registry:
			_registry.rebuilt.connect(_on_registry_rebuilt)
		var hbox := HBoxContainer.new()
		add_child(hbox)

		_line_edit = LineEdit.new()
		_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_line_edit.text_changed.connect(_on_text_changed)
		hbox.add_child(_line_edit)

		_status_label = Label.new()
		_status_label.custom_minimum_size = Vector2(20, 0)
		_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(_status_label)

		add_focusable(_line_edit)

	func _update_property() -> void:
		if _line_edit == null:
			return
		var value: String = get_edited_object().get(get_edited_property())
		if _updating:
			return
		_updating = true
		_line_edit.text = value
		_update_status(value)
		_updating = false

	func _on_text_changed(new_text: String) -> void:
		_update_status(new_text)
		if _updating:
			return
		_updating = true
		emit_changed(get_edited_property(), new_text)
		_updating = false

	func _exit_tree() -> void:
		if _registry and _registry.rebuilt.is_connected(_on_registry_rebuilt):
			_registry.rebuilt.disconnect(_on_registry_rebuilt)

	func _on_registry_rebuilt() -> void:
		if _line_edit == null:
			return
		_update_status(_line_edit.text)

	func _set_status(color: Color, tooltip: String) -> void:
		_status_label.text = "●"
		_status_label.modulate = color
		_status_label.tooltip_text = tooltip

	func _update_status(text: String) -> void:
		if _status_label == null:
			return
		if _mode == _Mode.FACT_KEY:
			_apply_fact_key_status(text)
		else:
			_apply_watch_pattern_status(text)

	func _apply_fact_key_status(text: String) -> void:
		if text.is_empty():
			_set_status(Color.RED, "fact_key is empty.")
			return

		var err: String = ChronicleKeyCodec.validate_key(text)
		if not err.is_empty():
			_set_status(Color.RED, "fact_key: " + err)
			return

		var known: bool = _registry != null and _registry.is_known(text)

		if known:
			_set_status(Color.GREEN, "fact_key is a known key found in the project.")
		elif "." not in text:
			_set_status(Color.YELLOW, "fact_key has no namespace separator (no dot). Valid, but unusual — consider using 'namespace.key' format.")
		else:
			_set_status(Color(1.0, 0.6, 0.2), "fact_key not found in project sources. It may be set dynamically at runtime.")

	func _apply_watch_pattern_status(text: String) -> void:
		if text.is_empty():
			_set_status(Color.RED, "watch_pattern is empty.")
			return

		var err: String = ChroniclePatternMatcher.validate(text)
		if not err.is_empty():
			_set_status(Color.RED, "Invalid pattern: " + err)
			return

		if "*" not in text:
			_set_status(Color.YELLOW, "watch_pattern is an exact key with no wildcard. Valid, but reactors are usually used with patterns like 'player.*'.")
		else:
			_set_status(Color.GREEN, "watch_pattern is valid.")


class _ConditionHintLabel extends Label:
	var _gate_ref: WeakRef
	var _last_condition: String = ""
	var _timer: Timer

	func _init() -> void:
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func setup(gate: Object) -> void:
		_gate_ref = weakref(gate)
		_last_condition = gate.condition if "condition" in gate else ""
		_update_display(_last_condition)

	func _ready() -> void:
		_timer = Timer.new()
		_timer.wait_time = 0.25
		_timer.autostart = true
		_timer.timeout.connect(_poll)
		add_child(_timer)

	func _exit_tree() -> void:
		if is_instance_valid(_timer):
			_timer.stop()
			_timer.queue_free()
			_timer = null

	func _poll() -> void:
		var gate: Object = _gate_ref.get_ref() if _gate_ref != null else null
		if gate == null:
			_timer.stop()
			return
		var current: String = gate.condition if "condition" in gate else ""
		if current != _last_condition:
			_last_condition = current
			_update_display(current)

	func _update_display(condition: String) -> void:
		if condition.is_empty():
			text = "⚠ condition is empty."
			modulate = Color.YELLOW
			return
		var gate: Object = _gate_ref.get_ref() if _gate_ref != null else null
		var ast: Variant = gate.parse_condition(condition) if gate != null else null
		if ast == null:
			text = "✗ Parse error — check expression syntax."
			modulate = Color(1.0, 0.4, 0.4)
		else:
			text = "✓ Expression OK"
			modulate = Color(0.4, 1.0, 0.4)


func rebuild_registry() -> void:
	_fact_registry.rebuild()


func _can_handle(object: Object) -> bool:
	var handled: bool = object is ChronicleCompanion
	if handled and not _ever_rebuilt:
		_fact_registry.rebuild()
		_ever_rebuilt = true
	return handled


func _parse_property(
		object: Object,
		_type: Variant.Type,
		name: String,
		_hint_type: PropertyHint,
		_hint_string: String,
		_usage_flags: int,
		_wide: bool
) -> bool:
	if object is ChronicleRecorder and name == "fact_key":
		var prop := _FactKeyProperty.new(_FactKeyProperty._Mode.FACT_KEY, _fact_registry)
		add_property_editor("fact_key", prop)
		return true

	if object is ChronicleReactor and name == "watch_pattern":
		var prop := _FactKeyProperty.new(_FactKeyProperty._Mode.WATCH_PATTERN, _fact_registry)
		add_property_editor("watch_pattern", prop)
		return true

	if object is ChronicleGate and name == "condition":
		var hint_label := _ConditionHintLabel.new()
		hint_label.setup(object)
		add_custom_control(hint_label)
		# Return false so the default multiline editor is also shown
		return false

	return false
