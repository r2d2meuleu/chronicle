## Deduplicating warning emitter. Suppresses repeated messages and caps total unique warnings.
class_name ChronicleWarningBus
extends RefCounted

const _CAP: int = 500
const _SUMMARY_INTERVAL: int = 10

var _dedup: Dictionary[String, bool] = {}
var _suppressed_count: int = 0
var _last_suppressed_msg: String = ""
var _output_fn: Callable


func _init(output_fn: Callable = Callable()) -> void:
	_output_fn = output_fn if output_fn.is_valid() else func(msg: String) -> void: push_warning(msg)


func warn(msg: String) -> void:
	if msg in _dedup:
		return
	if _dedup.size() >= _CAP:
		_suppressed_count += 1
		_last_suppressed_msg = msg
		if _suppressed_count == 1 or _suppressed_count % _SUMMARY_INTERVAL == 0:
			_output_fn.call("[Chronicle] Warning dedup saturated (%d suppressed). Latest: %s. Call clear() to reset." % [_suppressed_count, _last_suppressed_msg])
		return
	_dedup[msg] = true
	_output_fn.call("[Chronicle] " + msg)


func clear() -> void:
	_dedup.clear()
	_suppressed_count = 0
	_last_suppressed_msg = ""
