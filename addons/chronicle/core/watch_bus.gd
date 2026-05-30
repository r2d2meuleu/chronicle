extends RefCounted
class_name ChronicleWatchBus


class WatchEntry extends RefCounted:
	var id: int
	var pattern: String
	var callback: Callable
	var once: bool = false
	var norm_prefix: String = ""
	var pat_segs: PackedStringArray = PackedStringArray()
	var has_pat_segs: bool = false
	func _init(p_id: int, p_pattern: String, p_callback: Callable) -> void:
		id = p_id
		pattern = p_pattern
		callback = p_callback


class WatchMeta extends RefCounted:
	var keys: Array[String]
	var callback: Callable
	func _init(p_keys: Array[String], p_callback: Callable) -> void:
		keys = p_keys
		callback = p_callback


var _exact_watches: Dictionary[String, Array] = {}
var _glob_watches_dirty: bool = true
var _glob_by_entity: Dictionary[String, Array] = {}
var _glob_any_entity: Array = []
var _glob_by_id: Dictionary[int, Array] = {}
var _glob_pattern_index: Dictionary[String, Array] = {}
var _watch_reverse: Dictionary[int, WatchMeta] = {}
var _alive_ids: Dictionary[int, bool] = {}
# Overflow impossible in practice (2^63 at 1M/sec = ~292B years). No cap or deser path sets IDs.
var _next_watch_id: int = 0
var _dispatch_depth: int = 0
var _dead_ids: Dictionary[int, bool] = {}
var _pending_clear: bool = false
var _custom_matcher_active: bool = false
var _fired: Dictionary[int, bool] = {}
var _seg_cache: ChronicleRingCache = ChronicleRingCache.new(2048)


var _key_codec: ChronicleKeyCodec
var _matches_fn: Callable
var _validate_pattern_fn: Callable
var _warn_fn: Callable
var _copy_fn: Callable
var _default_matches_fn: Callable
var _default_validate_fn: Callable


func _init(key_codec: ChronicleKeyCodec, matches_fn: Callable, validate_pattern_fn: Callable, warn_fn: Callable, copy_fn: Callable = Callable()) -> void:
	_key_codec = key_codec
	_matches_fn = matches_fn
	_validate_pattern_fn = validate_pattern_fn
	_default_matches_fn = matches_fn
	_default_validate_fn = validate_pattern_fn
	_warn_fn = warn_fn
	_copy_fn = copy_fn


func set_matcher(matches_fn: Callable, validate_pattern_fn: Callable, is_custom: bool = true) -> void:
	_matches_fn = matches_fn
	_validate_pattern_fn = validate_pattern_fn
	_custom_matcher_active = is_custom
	if is_custom:
		for id: int in _glob_by_id:
			for entry: WatchEntry in _glob_by_id[id]:
				entry.has_pat_segs = false
	_glob_watches_dirty = true


func watch(pattern: String, callback: Callable, once: bool = false) -> int:
	var id: int = _next_watch_id
	if not _register_pattern(id, pattern, callback, once):
		return -1
	_next_watch_id += 1
	return id


## Fires at most once per dispatch call, even if multiple patterns match the same key.
## Nested dispatches (triggered by watcher callbacks) have independent deduplication.
## All patterns are validated before any registration — if any pattern is invalid, none are registered.
func watch_any(patterns: Array[String], callback: Callable, once: bool = false) -> int:
	if not callback.is_valid():
		push_error("[Chronicle] watch_any() received an invalid Callable.")
		return -1
	# Phase 1: Validate all
	var errors: Array[String] = []
	for pat: String in patterns:
		if "*" in pat:
			var err: String = _key_codec.validate_watch_pattern(pat)
			if not err.is_empty():
				errors.append("'%s': %s" % [pat, err])
		else:
			var norm_key: String = _key_codec.validate_and_normalize(pat)
			if norm_key.is_empty():
				errors.append("'%s': invalid key" % pat)
	if not errors.is_empty():
		push_error("[Chronicle] watch_any: invalid patterns: %s" % ", ".join(errors))
		return -1
	# Phase 2: Register all (guaranteed to succeed after validation unless _pending_clear)
	var id: int = _next_watch_id
	var registered: int = 0
	for pat: String in patterns:
		if _register_pattern(id, pat, callback, once):
			registered += 1
	if registered == 0:
		return -1
	_next_watch_id += 1
	return id


func unwatch(watch_id: int) -> bool:
	var found: bool = watch_id in _alive_ids
	if _dispatch_depth > 0:
		if found:
			_dead_ids[watch_id] = true
		return found
	_alive_ids.erase(watch_id)
	if watch_id in _watch_reverse:
		var meta: WatchMeta = _watch_reverse[watch_id]
		for key: String in meta.keys:
			if key in _exact_watches:
				var arr: Array = _exact_watches[key]
				for i: int in range(arr.size() - 1, -1, -1):
					if (arr[i] as WatchEntry).id == watch_id:
						arr.remove_at(i)
				if arr.is_empty():
					_exact_watches.erase(key)
		_watch_reverse.erase(watch_id)
	if watch_id in _glob_by_id:
		for entry: WatchEntry in _glob_by_id[watch_id]:
			var pat: String = entry.pattern
			if pat in _glob_pattern_index:
				var pat_arr: Array = _glob_pattern_index[pat]
				var pidx: int = pat_arr.find(entry)
				if pidx != -1:
					pat_arr.remove_at(pidx)
				if pat_arr.is_empty():
					_glob_pattern_index.erase(pat)
		_glob_by_id.erase(watch_id)
		_glob_watches_dirty = true
	return found


## Removes all watchers registered with [param pattern]. For watch_any watchers,
## removes the entire watcher (all patterns), not just the matching pattern.
func unwatch_pattern(pattern: String) -> int:
	pattern = pattern.to_lower()
	if _dispatch_depth > 0:
		var count: int = 0
		if "*" in pattern:
			if pattern in _glob_pattern_index:
				count = _glob_pattern_index[pattern].size()
				for entry: WatchEntry in _glob_pattern_index[pattern]:
					_dead_ids[entry.id] = true
		else:
			var norm_key: String = _key_codec.normalize_unchecked(pattern)
			if norm_key in _exact_watches:
				count = _exact_watches[norm_key].size()
				for entry: WatchEntry in _exact_watches[norm_key]:
					_dead_ids[entry.id] = true
		return count
	var removed: int = 0
	if "*" in pattern:
		if pattern not in _glob_pattern_index:
			return 0
		var entries_snapshot: Array = _glob_pattern_index[pattern].duplicate()
		var ids_to_remove: Array[int] = []
		for entry: WatchEntry in entries_snapshot:
			if entry.id not in ids_to_remove:
				ids_to_remove.append(entry.id)
		for id: int in ids_to_remove:
			unwatch(id)
			removed += 1
	else:
		var norm_key: String = _key_codec.normalize_unchecked(pattern)
		if norm_key not in _exact_watches:
			return 0
		var entries_snapshot: Array = _exact_watches[norm_key].duplicate()
		var ids_to_remove: Array[int] = []
		for entry: WatchEntry in entries_snapshot:
			if entry.id not in ids_to_remove:
				ids_to_remove.append(entry.id)
		for id: int in ids_to_remove:
			unwatch(id)
			removed += 1
	return removed


## Deferred until dispatch completes if called mid-dispatch.
func unwatch_all() -> void:
	if _dispatch_depth > 0:
		_pending_clear = true
		return
	_exact_watches.clear()
	_glob_watches_dirty = true
	_glob_by_entity.clear()
	_glob_by_id.clear()
	_glob_pattern_index.clear()
	_glob_any_entity.clear()
	_watch_reverse.clear()
	_alive_ids.clear()
	_dead_ids.clear()
	_seg_cache.clear()
	if _custom_matcher_active:
		_matches_fn = _default_matches_fn
		_validate_pattern_fn = _default_validate_fn
		_custom_matcher_active = false


func dispatch(norm_key: String, display_key: String, value: Variant, old_value: Variant) -> void:
	if _dispatch_depth == 0 and _glob_watches_dirty:
		_rebuild_glob_buckets()
		_glob_watches_dirty = false

	_dispatch_depth += 1
	var fired: Dictionary
	if _dispatch_depth == 1:
		_fired.clear()
		fired = _fired
	else:
		fired = {}

	var copy_value: Variant = value
	var copy_old: Variant = old_value
	if _copy_fn.is_valid():
		if value != null and ChronicleValueUtils.needs_copy(typeof(value)):
			copy_value = _copy_fn.call(value)
		if old_value != null and ChronicleValueUtils.needs_copy(typeof(old_value)):
			copy_old = _copy_fn.call(old_value)

	if norm_key in _exact_watches:
		_dispatch_exact(norm_key, display_key, copy_value, copy_old, fired)

	var entity: String = ChronicleKeyCodec.parse_entity(norm_key)
	var key_segs: PackedStringArray
	if _glob_by_entity.is_empty() and _glob_any_entity.is_empty():
		key_segs = PackedStringArray()
	else:
		var cached_segs: Variant = _seg_cache.get_or_null(norm_key)
		if cached_segs != null:
			key_segs = cached_segs
		else:
			key_segs = norm_key.split(".")
			_seg_cache.put(norm_key, key_segs)

	if entity in _glob_by_entity:
		_dispatch_glob_list(_glob_by_entity[entity], norm_key, key_segs, display_key, copy_value, copy_old, fired)
	_dispatch_glob_list(_glob_any_entity, norm_key, key_segs, display_key, copy_value, copy_old, fired)

	_dispatch_depth -= 1
	if _dispatch_depth == 0:
		if _pending_clear:
			_pending_clear = false
			unwatch_all()
			return
		if not _dead_ids.is_empty():
			for id: int in _dead_ids:
				unwatch(id)
			_dead_ids.clear()
		if _glob_watches_dirty:
			_rebuild_glob_buckets()
			_glob_watches_dirty = false


func _dispatch_exact(norm_key: String, display_key: String,
		value: Variant, old_value: Variant, fired: Dictionary) -> void:
	var entries: Array = _exact_watches[norm_key]
	for i: int in range(entries.size()):
		_invoke_watcher(entries[i] as WatchEntry, display_key, value, old_value, fired)


func _dispatch_glob_list(watchers: Array, norm_key: String,
		key_segs: PackedStringArray, display_key: String, value: Variant,
		old_value: Variant, fired: Dictionary) -> void:
	for watcher: WatchEntry in watchers:
		# Performance coupling: presplit fast-path uses ChroniclePatternMatcher directly.
		# When _custom_matcher_active is true, this is bypassed in favor of _matches_fn.
		if not _custom_matcher_active and watcher.has_pat_segs:
			if not ChroniclePatternMatcher.matches_presplit_segs(watcher.pat_segs, key_segs):
				continue
		elif not _matches_fn.call(watcher.pattern, norm_key):
			continue
		_invoke_watcher(watcher, display_key, value, old_value, fired)


func _invoke_watcher(watcher: WatchEntry, display_key: String,
		value: Variant, old_value: Variant, fired: Dictionary) -> void:
	if _pending_clear:
		return
	if watcher.id in fired:
		return
	fired[watcher.id] = true
	if watcher.id in _dead_ids:
		return
	if watcher.id not in _alive_ids:
		return
	if not watcher.callback.is_valid():
		_dead_ids[watcher.id] = true
		return
	if watcher.once:
		_dead_ids[watcher.id] = true
	watcher.callback.call(display_key, value, old_value)


func get_watcher_count() -> int:
	return _alive_ids.size()


func _register_pattern(id: int, pattern: String, callback: Callable, once: bool) -> bool:
	if _pending_clear:
		_warn_fn.call("watch() ignored — unwatch_all() pending. Register after dispatch completes.")
		return false
	if not callback.is_valid():
		push_error("[Chronicle] watch() received an invalid Callable — the watcher was not registered.")
		return false
	if "*" in pattern:
		return _register_glob(id, pattern, callback, once)
	return _register_exact(id, pattern, callback, once)


func _register_glob(id: int, pattern: String, callback: Callable, once: bool) -> bool:
	# Validate through the codec's unified pattern validator so glob watches honor the
	# same reserved-prefix rule as exact keys (e.g. "_global.*" is rejected, watch -> -1),
	# in addition to the pattern-matcher syntax check it delegates to.
	var err: String = _key_codec.validate_watch_pattern(pattern)
	if not err.is_empty():
		_warn_fn.call("watch() invalid glob pattern \"%s\": %s" % [pattern, err])
		return false
	pattern = pattern.to_lower()
	var norm_prefix: String = ""
	if pattern != "*":
		var star_pos: int = pattern.find("*")
		var prefix: String = pattern.substr(0, star_pos)
		if prefix.ends_with("."):
			prefix = prefix.substr(0, prefix.length() - 1)
		if not prefix.is_empty():
			var dot_pos: int = prefix.find(".")
			norm_prefix = prefix.substr(0, dot_pos) if dot_pos != -1 else prefix
	var is_trailing_wildcard: bool = pattern.ends_with(".*") and pattern.count("*") == 1
	var entry := WatchEntry.new(id, pattern, callback)
	entry.norm_prefix = norm_prefix
	if not is_trailing_wildcard and not _custom_matcher_active:
		entry.pat_segs = pattern.split(".")
		entry.has_pat_segs = true
	if once:
		entry.once = true
	if id not in _glob_by_id:
		_glob_by_id[id] = []
	_glob_by_id[id].append(entry)
	if pattern not in _glob_pattern_index:
		_glob_pattern_index[pattern] = []
	_glob_pattern_index[pattern].append(entry)
	_glob_watches_dirty = true
	_alive_ids[id] = true
	return true


func _register_exact(id: int, pattern: String, callback: Callable, once: bool) -> bool:
	var norm_key: String = _key_codec.validate_and_normalize(pattern)
	if norm_key.is_empty():
		return false
	if norm_key not in _exact_watches:
		_exact_watches[norm_key] = []
	var entry := WatchEntry.new(id, norm_key, callback)
	if once:
		entry.once = true
	_exact_watches[norm_key].append(entry)
	_alive_ids[id] = true
	# Track in reverse map for O(keys per watcher) unwatch
	if id not in _watch_reverse:
		_watch_reverse[id] = WatchMeta.new([] as Array[String], callback)
	_watch_reverse[id].keys.append(norm_key)
	return true


func _rebuild_glob_buckets() -> void:
	_glob_by_entity.clear()
	_glob_any_entity.clear()
	for id: int in _glob_by_id:
		for entry: WatchEntry in _glob_by_id[id]:
			if entry.norm_prefix.is_empty():
				_glob_any_entity.append(entry)
			else:
				if entry.norm_prefix not in _glob_by_entity:
					_glob_by_entity[entry.norm_prefix] = []
				_glob_by_entity[entry.norm_prefix].append(entry)


## Best-effort cleanup -- not a correctness requirement.
func prune_invalid() -> void:
	var to_remove: Array[int] = []
	for id: int in _watch_reverse:
		var meta: WatchMeta = _watch_reverse[id]
		if not meta.callback.is_valid():
			to_remove.append(id)
	for id: int in _glob_by_id:
		if id in _watch_reverse:
			continue
		var entries: Array = _glob_by_id[id]
		if not entries.is_empty() and not (entries[0] as WatchEntry).callback.is_valid():
			to_remove.append(id)
	for id: int in to_remove:
		unwatch(id)
