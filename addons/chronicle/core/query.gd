extends RefCounted
class_name ChronicleQuery

var _store: ChronicleStore
var _key_codec: ChronicleKeyCodec
var _matches_fn: Callable
var _timeline: ChronicleTimeline
var _copy_fn: Callable
var _key_index: Dictionary[String, Array] = {}
var _last_timeline_tick: int = -1
var _index_valid: bool = false
var _last_structural_gen: int = -1
var _last_indexed_size: int = 0


static func _entry_to_dict(e: ChronicleTimeline.Entry) -> Dictionary:
	return e.to_dict()


func _init(store: ChronicleStore, key_codec: ChronicleKeyCodec, matches_fn: Callable, timeline: ChronicleTimeline, copy_fn: Callable) -> void:
	_store = store
	_key_codec = key_codec
	_matches_fn = matches_fn
	_timeline = timeline
	_copy_fn = copy_fn


## Call when the timeline is cleared or replaced.
func clear() -> void:
	_key_index.clear()
	_last_timeline_tick = -1
	_index_valid = false
	_last_structural_gen = -1
	_last_indexed_size = 0


func set_matcher(matches_fn: Callable) -> void:
	_matches_fn = matches_fn


## Accepts glob patterns: "player.*", "player.hp", "*".
func find(pattern: String) -> Array[String]:
	var norm_pattern: String = _key_codec.normalize_pattern(pattern)
	if norm_pattern.is_empty():
		return []
	var result: Array[String] = []
	if "*" not in norm_pattern:
		if _store.has(norm_pattern):
			result.append(_key_codec.denormalize(norm_pattern))
		return result
	if norm_pattern == "*":
		for norm_key: String in _store.get_keys():
			result.append(_key_codec.denormalize(norm_key))
		return result
	var matching: Array[String] = _matching_norm_keys(norm_pattern)
	for norm_key: String in matching:
		result.append(_key_codec.denormalize(norm_key))
	return result


## Returns the number of facts matching the pattern without allocating result arrays.
func count(pattern: String) -> int:
	var norm_pattern: String = _key_codec.normalize_pattern(pattern)
	if norm_pattern.is_empty():
		return 0
	if "*" not in norm_pattern:
		return 1 if _store.has(norm_pattern) else 0
	if norm_pattern == "*":
		return _store.size()
	return _count_matching_norm_keys(norm_pattern)


## Returns a Dictionary of display_key -> value for all facts matching the pattern.
func get_facts(pattern: String) -> Dictionary:
	var norm_pattern: String = _key_codec.normalize_pattern(pattern)
	if norm_pattern.is_empty():
		return {}
	var result: Dictionary = {}
	if "*" not in norm_pattern:
		if _store.has(norm_pattern):
			result[_key_codec.denormalize(norm_pattern)] = _store.get_value(norm_pattern)
		return result
	if norm_pattern == "*":
		for norm_key: String in _store.get_keys():
			result[_key_codec.denormalize(norm_key)] = _store.get_value(norm_key)
		return result
	var matching: Array[String] = _matching_norm_keys(norm_pattern)
	for norm_key: String in matching:
		result[_key_codec.denormalize(norm_key)] = _store.get_value(norm_key)
	return result


## Matches in normalized key space, consistent with find/count/get_facts.
func get_first_change(pattern: String = "*") -> Variant:
	var norm_pattern: String = _key_codec.normalize_pattern(pattern)
	if norm_pattern.is_empty():
		return null
	for i: int in range(_timeline.size()):
		var entry: ChronicleTimeline.Entry = _timeline.get_at(i)
		if _matches_fn.call(norm_pattern, entry.norm_key):
			return _entry_to_dict(entry.copy(_copy_fn))
	return null


## Matches in normalized key space, consistent with find/count/get_facts.
func get_last_change(pattern: String = "*") -> Variant:
	var norm_pattern: String = _key_codec.normalize_pattern(pattern)
	if norm_pattern.is_empty():
		return null
	for i: int in range(_timeline.size() - 1, -1, -1):
		var entry: ChronicleTimeline.Entry = _timeline.get_at(i)
		if _matches_fn.call(norm_pattern, entry.norm_key):
			return _entry_to_dict(entry.copy(_copy_fn))
	return null


## Returns all timeline entries with time strictly after since_time.
func get_changes_since(since_time: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start: int = _timeline.bisect_after(since_time)
	for i: int in range(start, _timeline.size()):
		result.append(_entry_to_dict(_timeline.get_at(i).copy(_copy_fn)))
	return result


## Returns all timeline entries in the half-open range (since_time, until_time].
func get_changes_between(since_time: float, until_time: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start: int = _timeline.bisect_after(since_time)
	var end: int = _timeline.bisect_after(until_time)
	for i: int in range(start, end):
		result.append(_entry_to_dict(_timeline.get_at(i).copy(_copy_fn)))
	return result


func _ensure_index_valid() -> void:
	var current_gen: int = _timeline.get_structural_gen()
	var current_tick: int = _timeline.get_tick()
	if not _index_valid or current_gen != _last_structural_gen:
		_rebuild_key_index()
		_last_structural_gen = current_gen
		_last_timeline_tick = current_tick
		_index_valid = true
	elif current_tick != _last_timeline_tick:
		_incremental_index_update()
		_last_timeline_tick = current_tick


## Results are in chronological order; uses a lazily-built index for speed.
func get_fact_history(key: String) -> Array[Dictionary]:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return []
	var denorm_key: String = _key_codec.denormalize(norm_key)
	_ensure_index_valid()
	var result: Array[Dictionary] = []
	if denorm_key not in _key_index:
		return result
	for idx: int in _key_index[denorm_key]:
		result.append(_entry_to_dict(_timeline.get_at(idx).copy(_copy_fn)))
	return result


## Returns timeline entries for a single key within the half-open range (since_time, until_time].
func get_fact_changes_between(key: String, since_time: float, until_time: float) -> Array[Dictionary]:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return []
	var denorm_key: String = _key_codec.denormalize(norm_key)
	var result: Array[Dictionary] = []
	var start: int = _timeline.bisect_after(since_time)
	var end: int = _timeline.bisect_after(until_time)
	for i: int in range(start, end):
		var entry: ChronicleTimeline.Entry = _timeline.get_at(i)
		if entry.display_key == denorm_key:
			result.append(_entry_to_dict(entry.copy(_copy_fn)))
	return result


func _rebuild_key_index() -> void:
	_key_index.clear()
	for i: int in range(_timeline.size()):
		var entry: ChronicleTimeline.Entry = _timeline.get_at(i)
		var key: String = entry.display_key
		if key not in _key_index:
			var idx_arr: Array[int] = []
			_key_index[key] = idx_arr
		_key_index[key].append(i)
	_last_indexed_size = _timeline.size()


func _incremental_index_update() -> void:
	var size: int = _timeline.size()
	for i in range(_last_indexed_size, size):
		var entry: Variant = _timeline.get_at(i)
		if entry == null:
			continue
		var key: String = entry.display_key
		if key not in _key_index:
			_key_index[key] = [] as Array[int]
		_key_index[key].append(i)
	_last_indexed_size = size


func _get_candidate_keys(norm_pattern: String) -> Array[String]:
	var entity: String = ChronicleKeyCodec.parse_entity(norm_pattern)
	if "*" in entity:
		return _store.get_keys_raw()
	var entity_keys: Array = _store.get_keys_for_entity(entity)
	if not entity_keys.is_empty():
		var result: Array[String] = []
		result.assign(entity_keys)
		return result
	return []


func _count_matching_norm_keys(norm_pattern: String) -> int:
	var count: int = 0
	for norm_key: String in _get_candidate_keys(norm_pattern):
		if _matches_fn.call(norm_pattern, norm_key):
			count += 1
	return count


func _matching_norm_keys(norm_pattern: String) -> Array[String]:
	var result: Array[String] = []
	for norm_key: String in _get_candidate_keys(norm_pattern):
		if _matches_fn.call(norm_pattern, norm_key):
			result.append(norm_key)
	return result
