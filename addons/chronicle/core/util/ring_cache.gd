## Fixed-capacity insert-only cache with FIFO eviction. Null values cannot be stored.
class_name ChronicleRingCache
extends RefCounted

var _cache: Dictionary[String, Variant] = {}
var _order: PackedStringArray = PackedStringArray()
var _head: int = 0
var _fill: int = 0
var _cap: int


func _init(cap: int = 128) -> void:
	_cap = maxi(cap, 1)
	_order.resize(_cap)
	_head = 0
	_fill = 0


func get_or_null(key: String) -> Variant:
	return _cache.get(key)


func put(key: String, value: Variant) -> void:
	if value == null:
		return
	if key in _cache:
		return
	if _fill >= _cap:
		_cache.erase(_order[_head])
		_order[_head] = key
		_head = (_head + 1) % _cap
	else:
		_order[_fill] = key
		_fill += 1
	_cache[key] = value


func size() -> int:
	return _fill


func get_cap() -> int:
	return _cap


func clear() -> void:
	_cache.clear()
	_order.resize(_cap)
	_head = 0
	_fill = 0
