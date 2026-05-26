extends RefCounted
class_name ChronicleGameClock

var _time: float = 0.0
var _auto_advancing: bool = true
var _warn_fn: Callable


func _init(warn_fn: Callable = Callable()) -> void:
	if warn_fn.is_valid():
		_warn_fn = warn_fn


func _warn(msg: String) -> void:
	if _warn_fn.is_valid():
		_warn_fn.call(msg)
	else:
		push_warning(msg)


func advance(delta: float) -> void:
	if not ChronicleValueUtils.is_valid_float(delta):
		_warn("advance(): invalid delta — ignored.")
		return
	if delta < 0.0:
		_warn("advance(%.4f): negative delta — ignored." % delta)
		return
	_time += delta


func set_time(time: float) -> void:
	if not ChronicleValueUtils.is_valid_float(time):
		_warn("set_time(): NaN or INF — ignored.")
		return
	if time < 0.0:
		_warn("set_time(%.4f): negative time is not permitted." % time)
		return
	_time = time


func get_time() -> float:
	return _time


func set_auto_advancing(enabled: bool) -> void:
	_auto_advancing = enabled


func is_auto_advancing() -> bool:
	return _auto_advancing


func clear() -> void:
	_time = 0.0
	_auto_advancing = true
