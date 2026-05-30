extends RefCounted
class_name ChronicleWriteCoordinator


## Sentinel value to signal erase. Not a command.
class _EraseSentinel extends RefCounted:
	pass

## Sentinel returned by a write interceptor to reject a write.
class _RejectSentinel extends RefCounted:
	pass

## Sentinel returned when a write is deferred (e.g. during cascade).
class _DeferredSentinel extends RefCounted:
	pass

class _WriteSnapshot extends RefCounted:
	var norm_key: String
	var display_key: String
	var value: Variant
	var old_value: Variant
	var old_expire_at: float = ChronicleExpiry.NO_EXPIRY
	var old_transient: bool = false


enum EraseSource { USER, EXPIRY, ROLLBACK }

# State machine transitions (legal paths only):
# IDLE -> PROCESSING_EXPIRY -> EMITTING_EXPIRY -> IDLE
# IDLE -> ROLLING_BACK -> FINALIZING_ROLLBACK -> IDLE
# ROLLING_BACK -> IDLE (on rollback failure/no-op)
# IDLE -> FINALIZING_ROLLBACK (direct entry for rollback dispatch)
# IDLE -> DESERIALIZING -> IDLE -> RESTORING -> IDLE
# IDLE -> CLEARING -> IDLE
# IDLE -> DRAINING -> IDLE
enum _Mode { IDLE, PROCESSING_EXPIRY, ROLLING_BACK, DESERIALIZING, EMITTING_EXPIRY, FINALIZING_ROLLBACK, CLEARING, RESTORING, DRAINING }

const _TRANSITIONS: Dictionary = {
	_Mode.IDLE: [_Mode.PROCESSING_EXPIRY, _Mode.ROLLING_BACK, _Mode.DESERIALIZING, _Mode.CLEARING, _Mode.DRAINING, _Mode.FINALIZING_ROLLBACK, _Mode.RESTORING],
	_Mode.PROCESSING_EXPIRY: [_Mode.EMITTING_EXPIRY, _Mode.IDLE],
	_Mode.EMITTING_EXPIRY: [_Mode.IDLE],
	_Mode.ROLLING_BACK: [_Mode.FINALIZING_ROLLBACK, _Mode.IDLE],
	_Mode.FINALIZING_ROLLBACK: [_Mode.IDLE],
	_Mode.DESERIALIZING: [_Mode.IDLE],
	_Mode.RESTORING: [_Mode.IDLE],
	_Mode.CLEARING: [_Mode.IDLE],
	_Mode.DRAINING: [_Mode.IDLE],
}

const MAX_CASCADE_DEPTH: int = 8
const _SNAP_NORM_KEY: int = 0
const _SNAP_DISPLAY_KEY: int = 1
const _SNAP_VALUE: int = 2
const _SNAP_OLD_VALUE: int = 3
const _SNAP_OLD_EXPIRE_AT: int = 4
const _SNAP_OLD_TRANSIENT: int = 5
## Pass to preserve a fact's existing expiry unchanged.
const KEEP_LIFETIME: float = -2.0
const STORE_WARN_THRESHOLD: int = 10000

var _store: ChronicleStore
var _store_warned: bool = false
var _key_codec: ChronicleKeyCodec
var _timeline: ChronicleTimeline
var _watch_bus: ChronicleWatchBus
var _expiry: ChronicleExpiry
var _clock: ChronicleGameClock
var _emit_fact_changed_fn: Callable
var _warn_fn: Callable

var _erase_sentinel: _EraseSentinel = _EraseSentinel.new()
var _deferred_sentinel: _DeferredSentinel = _DeferredSentinel.new()

var _hard_cap: int = 0
var _mode: _Mode = _Mode.IDLE
var _expiring_norm_key: String = ""

var _cascade_depth: int = 0
var _deferred: ChronicleDeferredQueue = ChronicleDeferredQueue.new()
var _cascade_dedup_stack: Array[Dictionary] = []
var _active_erase_source: EraseSource = EraseSource.USER

var _rollback: ChronicleRollback

var _type_registry: ChronicleTypeRegistry
var _copy_fn: Callable
var _write_interceptor: Callable = Callable()

func _init(
	store: ChronicleStore,
	key_codec: ChronicleKeyCodec,
	timeline: ChronicleTimeline,
	watch_bus: ChronicleWatchBus,
	expiry: ChronicleExpiry,
	clock: ChronicleGameClock,
	emit_fact_changed_fn: Callable,
	warn_fn: Callable,
	hard_cap: int = 0,
	type_registry: ChronicleTypeRegistry = null,
	copy_fn: Callable = Callable(),
) -> void:
	_store = store
	_key_codec = key_codec
	_timeline = timeline
	_watch_bus = watch_bus
	_expiry = expiry
	_clock = clock
	_emit_fact_changed_fn = emit_fact_changed_fn
	_warn_fn = warn_fn
	_hard_cap = hard_cap
	_type_registry = type_registry
	_copy_fn = copy_fn
	if not emit_fact_changed_fn.is_valid():
		push_error("[Chronicle] WriteCoordinator: emit_fact_changed_fn is required")
		return
	if not warn_fn.is_valid():
		push_error("[Chronicle] WriteCoordinator: warn_fn is required")
		return


func _emit_fact_changed_safe(display_key: String, value: Variant,
		old_value: Variant, source: EraseSource) -> void:
	_emit_fact_changed_fn.call(display_key, value, old_value, source)


func _copy_for_dispatch(value: Variant) -> Variant:
	if value == null or not ChronicleValueUtils.needs_copy(typeof(value)):
		return value
	if _copy_fn.is_valid():
		return _copy_fn.call(value)
	return ChronicleValueUtils.safe_copy(value)


func _is_erase(value: Variant) -> bool:
	return value is _EraseSentinel


func _sanitize_lifetime(lifetime: float, raw_key: String, context: String = "set_fact") -> float:
	if lifetime != 0.0 and lifetime != KEEP_LIFETIME:
		if is_nan(lifetime) or is_inf(lifetime) or lifetime < 0.0:
			push_error("[Chronicle] %s(\"%s\"): invalid lifetime %.4f. Use Chronicle.KEEP_LIFETIME to preserve existing expiry, or 0.0 to clear it. Note: Chronicle.EXPIRY_NONE is a return value from get_expiry_remaining(), not a parameter." % [context, raw_key, lifetime])
			return 0.0
	return lifetime


func _resolve_erase_source(norm_key: String) -> EraseSource:
	if _active_erase_source == EraseSource.EXPIRY and norm_key != _expiring_norm_key:
		return EraseSource.USER
	return _active_erase_source


# Dispatch dedup contract:
# 1. WatchBus._fired: prevents same watcher ID from firing twice per dispatch call
# 2. _cascade_dedup_stack: prevents re-dispatching a key already dispatched in an ancestor batch
# These are independent mechanisms: WatchBus dedup = per-watcher, coordinator dedup = per-key.
func _dispatch_single_change(norm_key: String, display_key: String,
		value: Variant, old_value: Variant, erase_source: EraseSource) -> void:
	if value != null and typeof(value) == typeof(old_value) and value == old_value:
		return
	if not _cascade_dedup_stack.is_empty():
		for cascade_set: Dictionary in _cascade_dedup_stack:
			cascade_set[norm_key] = true
	_cascade_depth += 1
	_emit_fact_changed_safe(display_key, _copy_for_dispatch(value), _copy_for_dispatch(old_value), erase_source)
	_watch_bus.dispatch(norm_key, display_key, value, old_value)
	_cascade_depth -= 1


func _dispatch_change(norm_key: String, display_key: String,
		value: Variant, old_value: Variant, erase_source: EraseSource) -> void:
	_dispatch_single_change(norm_key, display_key, value, old_value, erase_source)
	if _cascade_depth == 0 and _mode != _Mode.DRAINING and not _must_defer():
		_drain_deferred_queue()


func _mutate_state(raw_key: String, value: Variant, transient: bool, lifetime: float, context: String = "set_fact") -> _WriteSnapshot:
	var norm_key: String = _key_codec.validate_and_normalize(raw_key)
	if norm_key.is_empty():
		return null

	if lifetime == 0.0 and not _is_erase(value) and _expiry.has(norm_key):
		_warn_fn.call("set_fact(\"%s\"): lifetime=0.0 clears existing expiry. Pass KEEP_LIFETIME to preserve." % raw_key)

	if not _is_erase(value) and _type_registry != null and not _type_registry.is_valid_type(value):
		push_error("[Chronicle] %s(\"%s\") received %s, not a storable type. Use bool, int, float, String, Array, Dictionary, or Godot value types (Vector2, Color, etc.)." % [context, raw_key, type_string(typeof(value))])
		return null

	if _write_interceptor.is_valid() and not _is_erase(value):
		var intercepted: Variant = _write_interceptor.call(raw_key, value, _store.get_value_raw(norm_key, null))
		if intercepted is _RejectSentinel:
			return null
		value = intercepted

	if lifetime > 0.0:
		transient = true

	if _hard_cap > 0 and not _is_erase(value) and not _store.has(norm_key) and _store.size() >= _hard_cap:
		push_error("[Chronicle] Store hard cap (%d) reached writing \"%s\" — rejected. Call set_store_hard_cap() with a higher value, or 0 to disable." % [_hard_cap, raw_key])
		return null

	var is_new: bool = not _store.has(norm_key)
	var old_expire_at: float = _expiry.get_expire_at(norm_key)
	var old_transient: bool = _store.is_transient(norm_key)
	var _raw_old: Variant = _store.get_value_raw(norm_key, null)
	var old_value: Variant = _copy_fn.call(_raw_old) if _copy_fn.is_valid() else ChronicleValueUtils.safe_copy(_raw_old)

	if _is_erase(value):
		if is_new:
			return null
		_store.erase_value(norm_key)
		_expiry.cancel(norm_key)
		value = null
	else:
		_store.set_value(norm_key, value)
		if not _store_warned and _store.size() >= STORE_WARN_THRESHOLD:
			_store_warned = true
			_warn_fn.call("Store has %d+ facts. This is a one-time warning." % STORE_WARN_THRESHOLD)
		if transient:
			_store.set_transient(norm_key, true)
		else:
			_store.set_transient(norm_key, false)
		if lifetime > 0.0:
			_expiry.schedule(norm_key, lifetime)
		elif lifetime == 0.0 and _expiry.has(norm_key):
			_expiry.cancel(norm_key)

	var result := _WriteSnapshot.new()
	result.norm_key = norm_key
	result.display_key = _key_codec.denormalize(norm_key)
	result.value = value
	result.old_value = old_value
	result.old_expire_at = old_expire_at
	result.old_transient = old_transient
	return result



func apply_write(raw_key: String, value: Variant, lifetime: float = KEEP_LIFETIME, transient: bool = false) -> bool:
	if value == null:
		_warn_fn.call("set_fact(\"%s\", null) — use erase_fact() to delete facts explicitly." % raw_key)
		value = _erase_sentinel
	lifetime = _sanitize_lifetime(lifetime, raw_key)
	if _must_defer():
		var safe_val: Variant = _copy_fn.call(value) if _copy_fn.is_valid() else ChronicleValueUtils.deep_copy(value)
		_try_defer(_apply_set_immediate.bind(raw_key, safe_val, transient, lifetime), "set_fact(\"%s\")" % raw_key)
		return false
	return _apply_set_immediate(raw_key, value, transient, lifetime)


func _commit_and_dispatch(result: _WriteSnapshot) -> void:
	var norm_key: String = result.norm_key
	var display_key: String = result.display_key
	var new_value: Variant = result.value
	var old_value: Variant = result.old_value
	var old_expire_at: float = result.old_expire_at
	var old_transient: bool = result.old_transient
	if _should_dispatch_events():
		if _should_record_timeline():
			_timeline.append(display_key, norm_key, new_value, old_value, _clock.get_time(), _expiry.get_expire_at(norm_key), old_expire_at, old_transient)
		var erase_source: EraseSource = _resolve_erase_source(norm_key)
		_expiring_norm_key = ""
		_dispatch_change(norm_key, display_key, new_value, old_value, erase_source)


func _apply_set_immediate(raw_key: String, value: Variant, transient: bool, lifetime: float, context: String = "set_fact") -> bool:
	var result: _WriteSnapshot = _mutate_state(raw_key, value, transient, lifetime, context)
	if result == null:
		return false
	_commit_and_dispatch(result)
	return true



func write_batch(entries: Dictionary, lifetime: float, transient: bool) -> Array[String]:
	lifetime = _sanitize_lifetime(lifetime, "batch", "set_facts")
	if _must_defer():
		var copied: Dictionary = {}
		for k: Variant in entries:
			copied[k] = _copy_fn.call(entries[k]) if _copy_fn.is_valid() else ChronicleValueUtils.deep_copy(entries[k])
		_try_defer(_apply_batch_internal.bind(copied, lifetime, transient), "set_facts()")
		return []
	return _apply_batch_internal(entries, lifetime, transient)


## Bypasses _try_defer — used during expiry processing where the mode defers
## but the erase itself must execute immediately.
## Note: callers pass display_key (e.g. execute_expiry_flush), which is valid here
## because validate_and_normalize round-trips display_key back to the same norm_key.
func _erase_immediate(key: String) -> bool:
	var result: _WriteSnapshot = _mutate_state(key, _erase_sentinel, false, KEEP_LIFETIME, "erase")
	if result == null:
		return false
	_commit_and_dispatch(result)
	return true


func erase(raw_key: String) -> bool:
	return apply_write(raw_key, _erase_sentinel)


func erase_batch(keys: Array[String]) -> int:
	var count: int = 0
	for key: String in keys:
		if erase(key):
			count += 1
	return count


func is_idle() -> bool:
	return _mode == _Mode.IDLE and _cascade_depth == 0


func get_hard_cap() -> int:
	return _hard_cap


func set_hard_cap(cap: int) -> void:
	_hard_cap = maxi(cap, 0)


func is_in_mutation() -> bool:
	return _cascade_depth > 0 or _mode != _Mode.IDLE


func _mode_defers_writes() -> bool:
	return _mode in [_Mode.PROCESSING_EXPIRY, _Mode.EMITTING_EXPIRY,
		_Mode.FINALIZING_ROLLBACK, _Mode.CLEARING, _Mode.RESTORING]


func _must_defer() -> bool:
	return _mode_defers_writes() or _cascade_depth >= MAX_CASCADE_DEPTH


func _try_defer(deferred_call: Callable, context: String) -> bool:
	if not _must_defer():
		return false
	return _deferred.enqueue(deferred_call, context, _cascade_depth, MAX_CASCADE_DEPTH, _warn_fn)


func _transition_to(new_mode: _Mode) -> bool:
	if new_mode not in _TRANSITIONS.get(_mode, []):
		push_error("[Chronicle] Invalid state transition: %s -> %s" % [_Mode.keys()[_mode], _Mode.keys()[new_mode]])
		return false
	_mode = new_mode
	return true


func _should_record_timeline() -> bool:
	return _mode != _Mode.DESERIALIZING and _mode != _Mode.ROLLING_BACK


func _should_dispatch_events() -> bool:
	return _mode != _Mode.DESERIALIZING


func clear() -> void:
	_cascade_depth = 0
	_deferred.clear()
	_mode = _Mode.IDLE
	_expiring_norm_key = ""
	_cascade_dedup_stack.clear()
	_active_erase_source = EraseSource.USER
	_store_warned = false


func write_expiry(raw_key: String, lifetime: float) -> bool:
	if not ChronicleValueUtils.is_valid_float(lifetime):
		push_error("[Chronicle] set_expiry(\"%s\"): NaN/INF lifetime — ignored." % raw_key)
		return false
	if lifetime < 0.0:
		push_error("[Chronicle] set_expiry(\"%s\"): negative lifetime (%.4f) — use 0.0 to clear expiry." % [raw_key, lifetime])
		return false
	if _must_defer():
		_try_defer(_apply_expiry_internal.bind(raw_key, lifetime), "set_expiry(\"%s\")" % raw_key)
		return false
	return _apply_expiry_internal(raw_key, lifetime)


func _apply_expiry_internal(raw_key: String, lifetime: float) -> bool:
	var norm_key: String = _key_codec.validate_and_normalize(raw_key)
	if norm_key.is_empty():
		return false
	if not _store.has(norm_key):
		_warn_fn.call("set_expiry(\"%s\"): fact does not exist." % raw_key)
		return false
	var display_key: String = _key_codec.denormalize(norm_key)
	var old_expire_at: float = _expiry.get_expire_at(norm_key)
	if lifetime > 0.0:
		_expiry.schedule(norm_key, lifetime)
	else:
		_expiry.cancel(norm_key)
	var new_expire_at: float = _expiry.get_expire_at(norm_key)
	if old_expire_at == new_expire_at:
		return false
	var current_value: Variant = _store.get_value_raw(norm_key, null)
	var current_transient: bool = _store.is_transient(norm_key)
	if _should_record_timeline():
		var old_value_copy: Variant = _copy_fn.call(current_value) if _copy_fn.is_valid() else ChronicleValueUtils.safe_copy(current_value)
		_timeline.append(display_key, norm_key, current_value, old_value_copy, _clock.get_time(), new_expire_at, old_expire_at, current_transient)
	return true


func increment(raw_key: String, amount: float, lifetime: float, transient: bool = false) -> Variant:
	if not ChronicleValueUtils.is_valid_float(amount):
		push_error("[Chronicle] increment_fact(\"%s\") received invalid amount — ignored." % raw_key)
		return null
	lifetime = _sanitize_lifetime(lifetime, raw_key, "increment_fact")
	if _must_defer():
		_try_defer(_apply_increment_internal.bind(raw_key, amount, lifetime, transient), "increment_fact(\"%s\")" % raw_key)
		return _deferred_sentinel
	return _apply_increment_internal(raw_key, amount, lifetime, transient)


func clamp(raw_key: String, min_value: float, max_value: float,
		lifetime: float = KEEP_LIFETIME, transient: bool = false) -> Variant:
	if not ChronicleValueUtils.is_valid_float(min_value) or not ChronicleValueUtils.is_valid_float(max_value):
		push_error("[Chronicle] clamp_fact(\"%s\"): NaN/INF bounds — ignored." % raw_key)
		return null
	if min_value > max_value:
		push_error("[Chronicle] clamp_fact(\"%s\"): min_value (%.4f) > max_value (%.4f)." % [raw_key, min_value, max_value])
		return null
	if _must_defer():
		_try_defer(_apply_clamp_internal.bind(raw_key, min_value, max_value, lifetime, transient), "clamp_fact(\"%s\")" % raw_key)
		return _deferred_sentinel
	return _apply_clamp_internal(raw_key, min_value, max_value, lifetime, transient)


func toggle(raw_key: String, lifetime: float, transient: bool) -> Variant:
	lifetime = _sanitize_lifetime(lifetime, raw_key, "toggle_fact")
	if _must_defer():
		_try_defer(_apply_toggle_internal.bind(raw_key, lifetime, transient), "toggle_fact(\"%s\")" % raw_key)
		return _deferred_sentinel
	return _apply_toggle_internal(raw_key, lifetime, transient)



func _apply_batch_internal(entries: Dictionary, lifetime: float, transient: bool) -> Array[String]:
	# Phase 1: mutate store
	var batch_results: Array[Array] = []

	for raw_key: Variant in entries:
		if raw_key is not String:
			_warn_fn.call("set_facts() key is not a String: %s" % str(raw_key))
			continue
		var val: Variant = entries[raw_key]
		if val == null:
			_warn_fn.call("set_facts() key \"%s\" has null value — use erase_fact() to delete facts explicitly." % str(raw_key))
			val = _erase_sentinel

		var result: _WriteSnapshot = _mutate_state(raw_key, val, transient, lifetime)
		if result == null:
			continue

		# Snapshot result fields into a plain Array for batch accumulation (avoids holding RefCounted refs).
		var snap: Array = [result.norm_key, result.display_key, result.value, result.old_value, result.old_expire_at, result.old_transient]

		if _should_record_timeline():
			_timeline.append(snap[_SNAP_DISPLAY_KEY], snap[_SNAP_NORM_KEY], snap[_SNAP_VALUE],
				snap[_SNAP_OLD_VALUE], _clock.get_time(),
				_expiry.get_expire_at(snap[_SNAP_NORM_KEY]),
				snap[_SNAP_OLD_EXPIRE_AT], snap[_SNAP_OLD_TRANSIENT])

		for cascade_set: Dictionary in _cascade_dedup_stack:
			cascade_set[snap[_SNAP_NORM_KEY]] = true
		batch_results.append(snap)

	if batch_results.is_empty():
		return []

	if not _should_dispatch_events():
		var keys: Array[String] = []
		for r: Array in batch_results:
			keys.append(r[_SNAP_DISPLAY_KEY])
		return keys

	# Phase 2: dispatch — nested write_batch may recurse
	var my_cascade: Dictionary = {}
	_cascade_dedup_stack.append(my_cascade)
	_cascade_depth += 1

	var changed_display_keys: Array[String] = []
	for r: Array in batch_results:
		if r[_SNAP_NORM_KEY] in my_cascade:
			continue
		if r[_SNAP_VALUE] != null and typeof(r[_SNAP_VALUE]) == typeof(r[_SNAP_OLD_VALUE]) and r[_SNAP_VALUE] == r[_SNAP_OLD_VALUE]:
			continue
		var source: EraseSource = _resolve_erase_source(r[_SNAP_NORM_KEY])
		_dispatch_single_change(r[_SNAP_NORM_KEY], r[_SNAP_DISPLAY_KEY], r[_SNAP_VALUE], r[_SNAP_OLD_VALUE], source)
		changed_display_keys.append(r[_SNAP_DISPLAY_KEY])

	_cascade_dedup_stack.pop_back()
	_cascade_depth -= 1

	if _cascade_depth == 0 and _mode != _Mode.DRAINING and not _must_defer():
		_drain_deferred_queue()

	return changed_display_keys


func _apply_increment_internal(raw_key: String, amount: float, lifetime: float, transient: bool = false) -> Variant:
	var norm_key: String = _key_codec.validate_and_normalize(raw_key)
	if norm_key.is_empty():
		return null
	var current: Variant = _store.get_value_raw(norm_key, null)
	var result: Variant = ChronicleValueUtils.compute_increment(current, amount)
	if result == null:
		if current != null and not (current is int or current is float):
			_warn_fn.call("increment_fact(\"%s\", amount=%.4f) — current value is %s (%s), not numeric." % [raw_key, amount, str(current), type_string(typeof(current))])
		else:
			_warn_fn.call("increment_fact(\"%s\", amount=%.4f) — result would be INF, ignored." % [raw_key, amount])
		return null
	var current_transient: bool = transient or _store.is_transient(norm_key)
	if not _apply_set_immediate(raw_key, result, current_transient, lifetime, "increment_fact"):
		return null
	return result


func _apply_clamp_internal(raw_key: String, min_value: float, max_value: float,
		lifetime: float = KEEP_LIFETIME, transient: bool = false) -> Variant:
	var norm_key: String = _key_codec.validate_and_normalize(raw_key)
	if norm_key.is_empty():
		return null
	var current: Variant = _store.get_value_raw(norm_key, null)
	var result: Variant = ChronicleValueUtils.compute_clamp(current, min_value, max_value)
	if result == null:
		_warn_fn.call("clamp_fact(\"%s\"): value is %s, not numeric — ignored." % [raw_key, type_string(typeof(current))])
		return null
	if result == current:
		return result
	var current_transient: bool = transient or _store.is_transient(norm_key)
	if not _apply_set_immediate(raw_key, result, current_transient, lifetime, "clamp_fact"):
		return null
	return result


func _apply_toggle_internal(raw_key: String, lifetime: float, transient: bool) -> Variant:
	var norm_key: String = _key_codec.validate_and_normalize(raw_key)
	if norm_key.is_empty():
		return null
	var current_transient: bool = transient or _store.is_transient(norm_key)
	var toggle_val: Variant = _store.get_value_raw(norm_key, null)
	var is_truthy: bool = ChronicleValueUtils.is_truthy(toggle_val, _type_registry.get_truthy_fn if _type_registry != null else Callable())
	if is_truthy:
		if not _apply_set_immediate(raw_key, false, current_transient, lifetime, "toggle_fact"):
			return null
		return false
	else:
		if not _apply_set_immediate(raw_key, true, current_transient, lifetime, "toggle_fact"):
			return null
		return true


func _drain_deferred_queue() -> void:
	if _mode == _Mode.DRAINING:
		return
	_deferred.drain(_transition_to, _Mode.IDLE, _Mode.DRAINING, _warn_fn)


func execute_expiry_flush(emit_expired_fn: Callable) -> void:
	if _mode != _Mode.IDLE:
		return
	if not _transition_to(_Mode.PROCESSING_EXPIRY):
		return
	_active_erase_source = EraseSource.EXPIRY
	var expired_norm_keys: Array[String] = _expiry.flush_expired()
	var expired_info: Array[Dictionary] = []
	for norm_key: String in expired_norm_keys:
		var display_key: String = _key_codec.denormalize(norm_key)
		var value: Variant = _store.get_value(norm_key)
		_expiring_norm_key = norm_key
		if _erase_immediate(display_key):
			expired_info.append({key = display_key, value = value})
		_expiring_norm_key = ""
	_active_erase_source = EraseSource.USER
	if not expired_info.is_empty():
		if not _transition_to(_Mode.EMITTING_EXPIRY):
			_transition_to(_Mode.IDLE)
			_drain_deferred_queue()
			return
		for entry: Dictionary in expired_info:
			var norm_key: String = _key_codec.validate_and_normalize(entry.key)
			if _store.has(norm_key):
				continue
			emit_expired_fn.call(entry.key, entry.value)
	_transition_to(_Mode.IDLE)
	_drain_deferred_queue()


func _emit_in_protected_mode(mode: _Mode, emit_fn: Callable) -> void:
	if _mode != _Mode.IDLE:
		push_error("[Chronicle] _emit_in_protected_mode() called in non-IDLE mode: %d — ignored." % _mode)
		return
	if not _transition_to(mode):
		return
	emit_fn.call()
	_transition_to(_Mode.IDLE)
	_drain_deferred_queue()


func execute_clearing(emit_fn: Callable) -> void:
	_emit_in_protected_mode(_Mode.CLEARING, emit_fn)


func set_rollback(rollback: ChronicleRollback) -> void:
	_rollback = rollback


func execute_rollback_to(target_time: float, current_time: float,
		purge_expiry_fn: Callable,
		emit_rolled_back_fn: Callable, emit_reset_fn: Callable) -> ChronicleRollbackResult:
	var r := ChronicleRollbackResult.new()
	if not ChronicleValueUtils.is_valid_float(target_time):
		r.error = "rollback_to() received invalid time — ignored."
		return r
	if target_time < 0.0:
		r.error = "rollback_to(%.4f) failed — time cannot be negative." % target_time
		return r
	if target_time > current_time:
		r.error = "rollback_to(%.4f) failed — target time is ahead of current game clock (%.4f)." % [target_time, current_time]
		return r
	if not _transition_to(_Mode.ROLLING_BACK):
		r.error = "internal state transition failed"
		return r
	r = _rollback.rollback_to(target_time)
	if not r.success:
		_transition_to(_Mode.IDLE)
		r.error = "rollback_to(%.4f) failed — unknown rollback failure." % target_time
		return r
	if r._restore_map.is_empty():
		_transition_to(_Mode.IDLE)
		_clock.set_time(r._target_time)
		_emit_in_protected_mode(_Mode.FINALIZING_ROLLBACK, func(): emit_rolled_back_fn.call(target_time))
		return r
	_execute_rollback_internal(r._restore_map, r._cut, _clock.set_time.bind(r._target_time), purge_expiry_fn, func(): emit_rolled_back_fn.call(target_time), emit_reset_fn)
	return r


func execute_rollback_steps(step_count: int,
		purge_expiry_fn: Callable,
		emit_rolled_back_fn: Callable, emit_reset_fn: Callable) -> ChronicleRollbackResult:
	var r := ChronicleRollbackResult.new()
	if not _transition_to(_Mode.ROLLING_BACK):
		r.error = "internal state transition failed"
		return r
	r = _rollback.rollback_steps(step_count)
	# CF-4 fix: check _restore_map.is_empty() regardless of r.success
	if r._restore_map.is_empty():
		_transition_to(_Mode.IDLE)
		return r
	_execute_rollback_internal(r._restore_map, r._cut,
		_clock.set_time.bind(r._target_time), purge_expiry_fn,
		func(): emit_rolled_back_fn.call(r._target_time), emit_reset_fn)
	return r


func execute_restore(
	snapshot_facts: Dictionary,
	timeline_entries: Array[Dictionary],
	timeline_tick: int,
	expiry_entries: Dictionary,
	game_time: float,
	auto_advance: bool,
	emit_reset_fn: Callable,
) -> int:
	if is_in_mutation():
		push_error("[Chronicle] execute_restore() called during mutation — not permitted.")
		return -1
	if not _transition_to(_Mode.DESERIALIZING):
		return -1
	_clock.set_time(game_time)
	_clock.set_auto_advancing(auto_advance)
	var failed: int = 0
	for key: String in snapshot_facts:
		var display_key: String = _key_codec.denormalize(key)
		if not apply_write(display_key, snapshot_facts[key]):
			failed += 1
	_timeline.set_entries(timeline_entries)
	_timeline.set_tick(timeline_tick)
	_expiry.set_entries(expiry_entries)
	for norm_key: String in _expiry.get_keys():
		if not _store.has(norm_key):
			_expiry.cancel(norm_key)
	_transition_to(_Mode.IDLE)
	_emit_in_protected_mode(_Mode.RESTORING, emit_reset_fn)
	return failed


func _execute_rollback_internal(restore_map: Dictionary, cut: int,
		set_clock_fn: Callable, purge_expiry_fn: Callable,
		emit_rolled_back_fn: Callable, emit_reset_fn: Callable) -> void:
	var pre_rollback_expire: Dictionary = _capture_pre_rollback_expiry(restore_map)
	_apply_restore_to_store(restore_map, cut)
	# CF-5 fix: transition to FINALIZING_ROLLBACK after store mutation, before event dispatch loop
	if not _transition_to(_Mode.FINALIZING_ROLLBACK):
		_mode = _Mode.IDLE
		return
	_active_erase_source = EraseSource.ROLLBACK
	for norm_key: String in restore_map:
		var info: Dictionary = restore_map[norm_key]
		if info.restore_value == null and info.pre_rollback_value == null:
			continue
		var transient_changed: bool = info.old_transient != _store.is_transient(norm_key)
		if info.restore_value != null and typeof(info.restore_value) == typeof(info.pre_rollback_value) and info.restore_value == info.pre_rollback_value and not transient_changed:
			var restored_expire: float = info.get("old_expire_at", ChronicleExpiry.NO_EXPIRY)
			var prev_expire: float = pre_rollback_expire.get(norm_key, ChronicleExpiry.NO_EXPIRY)
			if restored_expire == prev_expire:
				continue
			_cascade_depth += 1
			_emit_fact_changed_safe(info.display_key, _copy_for_dispatch(info.restore_value), _copy_for_dispatch(info.pre_rollback_value), EraseSource.ROLLBACK)
			_watch_bus.dispatch(norm_key, info.display_key, info.restore_value, info.pre_rollback_value)
			_cascade_depth -= 1
			continue
		_dispatch_change(norm_key, info.display_key, info.restore_value, info.pre_rollback_value, EraseSource.ROLLBACK)
	_active_erase_source = EraseSource.USER
	set_clock_fn.call()
	purge_expiry_fn.call()
	emit_rolled_back_fn.call()
	emit_reset_fn.call()
	# CF-6 fix: force IDLE on failed transition instead of silently passing
	if not _transition_to(_Mode.IDLE):
		push_error("[Chronicle] Failed to transition to IDLE after rollback — forcing IDLE.")
		_mode = _Mode.IDLE
	_drain_deferred_queue()


func _capture_pre_rollback_expiry(restore_map: Dictionary) -> Dictionary:
	var pre_rollback_expire: Dictionary = {}
	for norm_key: String in restore_map:
		var info: Dictionary = restore_map[norm_key]
		if info.restore_value != null and typeof(info.restore_value) == typeof(info.pre_rollback_value) and info.restore_value == info.pre_rollback_value:
			pre_rollback_expire[norm_key] = _expiry.get_expire_at(norm_key)
	return pre_rollback_expire


func _apply_restore_to_store(restore_map: Dictionary, cut: int) -> void:
	for norm_key: String in restore_map:
		var info: Dictionary = restore_map[norm_key]
		if info.restore_value == null:
			_store.erase_value(norm_key)
			_expiry.cancel(norm_key)
		else:
			_store.set_value(norm_key, info.restore_value)
			if info.old_transient:
				_store.set_transient(norm_key, true)
			else:
				_store.set_transient(norm_key, false)
			if info.old_expire_at != ChronicleExpiry.NO_EXPIRY:
				_expiry.schedule_at(norm_key, info.old_expire_at)
			else:
				_expiry.cancel(norm_key)
	_timeline.truncate(cut)


func set_write_interceptor(fn: Callable) -> void:
	_write_interceptor = fn
