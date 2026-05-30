class_name CompanionFactory

const ChronicleGateScript := preload("res://addons/chronicle/nodes/gate.gd")
const ChronicleReactorScript := preload("res://addons/chronicle/nodes/reactor.gd")
const ChronicleRecorderScript := preload("res://addons/chronicle/nodes/recorder.gd")

const GateMode := ChronicleGateScript.GateMode
const ReactTo := ChronicleReactorScript.ReactTo
const RecordMode := ChronicleRecorderScript.RecordMode

const _GATE_KEYS: Array = ["condition", "gate_mode", "target_path", "default_when_missing", "chronicle_path"]
const _REACTOR_KEYS: Array = ["watch_pattern", "target_method", "react_to", "one_shot", "chronicle_path"]
const _RECORDER_KEYS: Array = ["trigger_signal", "fact_key", "value", "record_mode", "amount", "chronicle_path"]


static func _validate_keys(config: Dictionary, valid_keys: Array) -> void:
	for key: String in config:
		assert(key in valid_keys,
			"CompanionFactory: unknown key '%s'. Valid: %s" % [key, str(valid_keys)])


static func make_gate(config: Dictionary) -> Node:
	_validate_keys(config, _GATE_KEYS)
	var gate := ChronicleGateScript.new()
	gate.condition = config.get("condition", "")
	gate.gate_mode = config.get("gate_mode", ChronicleGateScript.GateMode.HIDE_WHEN_FALSE)
	gate.target_path = config.get("target_path", NodePath(""))
	if config.has("default_when_missing"):
		gate.default_when_missing = config.default_when_missing
	if config.has("chronicle_path"):
		gate.chronicle_path = config.chronicle_path
	return gate


static func make_reactor(config: Dictionary) -> Node:
	_validate_keys(config, _REACTOR_KEYS)
	var reactor := ChronicleReactorScript.new()
	reactor.watch_pattern = config.get("watch_pattern", "")
	reactor.target_method = config.get("target_method", "")
	reactor.react_to = config.get("react_to", ChronicleReactorScript.ReactTo.ANY)
	reactor.one_shot = config.get("one_shot", false)
	if config.has("chronicle_path"):
		reactor.chronicle_path = config.chronicle_path
	return reactor


static func make_recorder(config: Dictionary) -> Node:
	_validate_keys(config, _RECORDER_KEYS)
	var recorder := ChronicleRecorderScript.new()
	recorder.trigger_signal = config.get("trigger_signal", "")
	recorder.fact_key = config.get("fact_key", "")
	recorder.value = config.get("value", true)
	recorder.record_mode = config.get("record_mode", ChronicleRecorderScript.RecordMode.ONCE)
	recorder.amount = config.get("amount", 1.0)
	if config.has("chronicle_path"):
		recorder.chronicle_path = config.chronicle_path
	return recorder

