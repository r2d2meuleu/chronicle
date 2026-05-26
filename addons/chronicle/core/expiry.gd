class_name ChronicleExpiry
extends RefCounted

const NO_EXPIRY: float = -1.0

var _expiring_facts: Dictionary[String, float] = {}
var _min_expiry_time: float = INF
var _min_dirty: bool = false
var _get_time_fn: Callable


func _init(get_time_fn: Callable) -> void:
	_get_time_fn = get_time_fn


func schedule(norm_key: String, lifetime: float) -> void:
	if not (lifetime > 0.0 and is_finite(lifetime)):
		push_error("[Chronicle] ChronicleExpiry.schedule: lifetime must be finite and > 0.0, got %.4f" % lifetime)
		return
	schedule_at(norm_key, _get_time_fn.call() + lifetime)


func cancel(norm_key: String) -> void:
	if norm_key in _expiring_facts:
		_expiring_facts.erase(norm_key)
		_min_dirty = true


func has(norm_key: String) -> bool:
	return norm_key in _expiring_facts


func flush_expired() -> Array[String]:
	if _min_dirty:
		_min_expiry_time = _recompute_min()
		_min_dirty = false
	var now: float = _get_time_fn.call()
	if _expiring_facts.is_empty() or now < _min_expiry_time:
		return []
	var expired_keys: Array[String] = []
	var new_min: float = INF
	for norm_key: String in _expiring_facts:
		if _expiring_facts[norm_key] <= now:
			expired_keys.append(norm_key)
		else:
			new_min = minf(new_min, _expiring_facts[norm_key])
	if expired_keys.is_empty():
		return []
	for norm_key: String in expired_keys:
		_expiring_facts.erase(norm_key)
	_min_expiry_time = new_min
	_min_dirty = false
	return expired_keys


func _recompute_min() -> float:
	var min_time: float = INF
	for norm_key: String in _expiring_facts:
		if _expiring_facts[norm_key] < min_time:
			min_time = _expiring_facts[norm_key]
	return min_time


func size() -> int:
	return _expiring_facts.size()


func get_remaining(norm_key: String) -> float:
	if norm_key not in _expiring_facts:
		return NO_EXPIRY
	return maxf(0.0, _expiring_facts[norm_key] - _get_time_fn.call())


func schedule_at(norm_key: String, expire_at: float) -> void:
	if not (expire_at > 0.0 and is_finite(expire_at)):
		push_error("[Chronicle] ChronicleExpiry.schedule_at: expire_at must be finite and > 0.0, got %.4f" % expire_at)
		return
	var old: float = _expiring_facts.get(norm_key, INF)
	_expiring_facts[norm_key] = expire_at
	if expire_at < _min_expiry_time:
		_min_expiry_time = expire_at
		_min_dirty = false
	elif old != expire_at and old == _min_expiry_time:
		_min_dirty = true


func get_expire_at(norm_key: String) -> float:
	return _expiring_facts.get(norm_key, NO_EXPIRY)


func get_entries() -> Dictionary[String, float]:
	return _expiring_facts.duplicate()


func set_entries(entries: Dictionary[String, float]) -> void:
	var copy: Dictionary[String, float] = {}
	for k: String in entries:
		var v: float = entries[k]
		if v > 0.0 and is_finite(v):
			copy[k] = v
	_expiring_facts = copy
	_min_expiry_time = _recompute_min()
	_min_dirty = false


func get_keys() -> Array[String]:
	return Array(_expiring_facts.keys(), TYPE_STRING, &"", null)


func clear() -> void:
	_expiring_facts.clear()
	_min_expiry_time = INF
	_min_dirty = false
