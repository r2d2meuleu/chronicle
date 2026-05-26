## Key-value store with defensive copying and transient key support.
extends RefCounted
class_name ChronicleStore

var _facts: Dictionary[String, Variant] = {}
var _transient_keys: Dictionary[String, bool] = {}
var _copy_fn: Callable
var _cached_keys: Array[String] = []
var _keys_dirty: bool = true
var _entity_index: Dictionary[String, Array] = {}
var _entity_fn: Callable


func _init(copy_fn: Callable = Callable(), entity_fn: Callable = Callable()) -> void:
	_copy_fn = copy_fn
	_entity_fn = entity_fn


func set_value(norm_key: String, value: Variant) -> void:
	if norm_key not in _facts:
		_keys_dirty = true
		if _entity_fn.is_valid():
			var entity: String = _entity_fn.call(norm_key)
			if entity not in _entity_index:
				_entity_index[entity] = [] as Array[String]
			_entity_index[entity].append(norm_key)
	_facts[norm_key] = _copy(value)


## Returns a defensive copy to prevent callers from mutating store internals.
func get_value(norm_key: String, default: Variant = null) -> Variant:
	if norm_key not in _facts:
		return default
	return _copy(_facts[norm_key])


func has(norm_key: String) -> bool:
	return norm_key in _facts


func erase_value(norm_key: String) -> void:
	if norm_key in _facts:
		_keys_dirty = true
		if _entity_fn.is_valid():
			var entity: String = _entity_fn.call(norm_key)
			if entity in _entity_index:
				var arr: Array = _entity_index[entity]
				var idx: int = arr.find(norm_key)
				if idx != -1:
					arr.remove_at(idx)
				if arr.is_empty():
					_entity_index.erase(entity)
	_facts.erase(norm_key)
	_transient_keys.erase(norm_key)


func size() -> int:
	return _facts.size()


## Wraps untyped Dictionary.keys() into a typed Array[String]. Cached until the key set changes.
func get_keys() -> Array[String]:
	if _keys_dirty:
		_cached_keys = Array(_facts.keys(), TYPE_STRING, &"", null)
		_keys_dirty = false
	return _cached_keys.duplicate()


## Returns the raw cache without duplicating. Internal callers that only iterate (never mutate) should use this.
func get_keys_raw() -> Array[String]:
	if _keys_dirty:
		_cached_keys = Array(_facts.keys(), TYPE_STRING, &"", null)
		_keys_dirty = false
	return _cached_keys


func set_transient(norm_key: String, transient: bool) -> void:
	if transient:
		_transient_keys[norm_key] = true
	else:
		_transient_keys.erase(norm_key)


func is_transient(norm_key: String) -> bool:
	return norm_key in _transient_keys


func clear() -> void:
	_facts.clear()
	_transient_keys.clear()
	_keys_dirty = true
	_entity_index.clear()


func get_keys_for_entity(entity: String) -> Array[String]:
	if entity in _entity_index:
		return _entity_index[entity].duplicate()
	return [] as Array[String]


## No defensive copy — caller must not mutate the returned value.
func get_value_raw(norm_key: String, default: Variant = null) -> Variant:
	return _facts.get(norm_key, default)


func _copy(value: Variant) -> Variant:
	if value == null:
		return null
	if not ChronicleValueUtils.needs_copy(typeof(value)):
		return value
	if _copy_fn.is_valid():
		return _copy_fn.call(value)
	return value.duplicate()
