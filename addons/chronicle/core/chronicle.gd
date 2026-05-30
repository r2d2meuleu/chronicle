class_name ChronicleEngine
extends Node


## Facade for the Chronicle fact-tracking system.

## Emitted after any fact write, BEFORE watcher callbacks for the same write. [param erase_source] is only meaningful when [param value] is null (erasure).
signal fact_changed(key: String, value: Variant, old_value: Variant, erase_source: EraseSource)
## Emitted after state has been reset. After rollback, state_rolled_back fires first.
signal state_reset
## Emitted after rollback, before state_reset. Handler writes are deferred and not yet visible.
signal state_rolled_back(target_time: float)
## Emitted on fact expiry. Destructive operations (clear, rollback, deserialize) are blocked from handlers.
signal fact_expired(key: String, expired_value: Variant)

## Re-exported from [ChronicleWriteCoordinator]. Identifies why a fact was erased: [code]USER[/code] (explicit erase), [code]EXPIRY[/code] (lifetime expired), or [code]ROLLBACK[/code] (removed during rollback).
const EraseSource = ChronicleWriteCoordinator.EraseSource
## Sentinel value. Return from a write interceptor (see [method set_write_interceptor]) to reject the write entirely.
static var REJECT: RefCounted = ChronicleWriteCoordinator._RejectSentinel.new()
## Sentinel value returned by [method toggle_fact], [method increment_fact], and [method clamp_fact] when the write is deferred because it was called from inside a watcher callback at maximum cascade depth.
static var DEFERRED: RefCounted = ChronicleWriteCoordinator._DeferredSentinel.new()

## Sentinel value (-2.0). Pass as [param lifetime] to preserve a fact's existing expiry. Pass [code]0.0[/code] to clear expiry.
const KEEP_LIFETIME: float = ChronicleWriteCoordinator.KEEP_LIFETIME
## Pass as timeline_cap to [method serialize] to include all entries (no cap).
const SERIALIZE_ALL: int = ChronicleSerializer.SERIALIZE_ALL
## Return-value sentinel from [method get_expiry_remaining]: the fact has no expiry (-1.0). [b]Do not pass as a [param lifetime] argument[/b] — use [constant KEEP_LIFETIME] to preserve, or [code]0.0[/code] to clear.
const EXPIRY_NONE: float = -1.0
## Pass to [method serialize] to use the project setting [code]chronicle/storage/serialize_timeline_cap[/code] as the timeline cap (default).
const SERIALIZE_USE_SETTING: int = 0
const _PRUNE_INTERVAL_FRAMES: int = 60

var _store: ChronicleStore
var _key_codec: ChronicleKeyCodec
var _timeline: ChronicleTimeline
var _watch_bus: ChronicleWatchBus
var _rollback: ChronicleRollback
var _expiry: ChronicleExpiry
var _serializer: ChronicleSerializer
var _coordinator: ChronicleWriteCoordinator
var _query: ChronicleQuery
var _clock: ChronicleGameClock
var _type_registry: ChronicleTypeRegistry
var _type_codec: ChronicleTypeCodec
var _expression: ChronicleExpressionEngine
var _watch_prune_counter: int = 0
var _is_processing: bool = false
var _eval_resolver: Callable
var _warnings: ChronicleWarningBus = ChronicleWarningBus.new()
var _matches_fn: Callable = ChroniclePatternMatcher.matches
var _save_fn: Callable = ChronicleFileIO.save_to_file
var _load_fn: Callable = ChronicleFileIO.load_from_file
var _purge_expiry_fn: Callable


const RollbackResult := preload("res://addons/chronicle/core/rollback_result.gd")


static func _get_setting(path: String, default_value: int) -> int:
	if not ProjectSettings.has_setting(path):
		return default_value
	var raw: Variant = ProjectSettings.get_setting(path, default_value)
	if (raw is int or raw is float) and not (raw is bool):
		return int(raw)
	return default_value


func _ready() -> void:
	_type_registry = ChronicleTypeRegistry.new()
	_type_codec = ChronicleTypeCodec.new(_type_registry)
	ChronicleBuiltinTypes.register_all(_type_registry, _type_codec)
	_expression = ChronicleExpressionEngine.new(_type_registry.get_truthy_fn)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_clock = ChronicleGameClock.new(_warnings.warn)
	var copy_fn: Callable = func(v: Variant) -> Variant: return ChronicleValueUtils.deep_copy(v, 64, _type_registry.copy_value)
	_store = ChronicleStore.new(copy_fn, ChronicleKeyCodec.parse_entity)
	_key_codec = ChronicleKeyCodec.new(_warnings.warn)
	_expiry = ChronicleExpiry.new(_clock.get_time)
	_purge_expiry_fn = func() -> void:
		for norm_key: String in _expiry.get_keys():
			if not _store.has(norm_key):
				_expiry.cancel(norm_key)
	_timeline = ChronicleTimeline.new(copy_fn, _warnings.warn)
	_watch_bus = ChronicleWatchBus.new(_key_codec, ChroniclePatternMatcher.matches, ChroniclePatternMatcher.validate, _warnings.warn, copy_fn)
	_rollback = ChronicleRollback.new(_timeline, _store, _key_codec)
	_coordinator = ChronicleWriteCoordinator.new(
		_store, _key_codec, _timeline, _watch_bus, _expiry, _clock,
		fact_changed.emit, _warnings.warn,
		_get_setting("chronicle/storage/store_hard_cap", 0),
		_type_registry, copy_fn,
	)
	_coordinator.set_rollback(_rollback)
	_query = ChronicleQuery.new(_store, _key_codec, _matches_fn, _timeline, copy_fn)
	_eval_resolver = func(key: String) -> Variant:
		var norm_key: String = _key_codec.validate_and_normalize(key)
		if norm_key.is_empty():
			return null
		return _store.get_value_raw(norm_key)
	var ser_cap: int = _get_setting("chronicle/storage/serialize_timeline_cap", 1000)
	_serializer = ChronicleSerializer.new(_store, _key_codec, _type_codec, _type_registry, ser_cap)
	_timeline.set_cap(_get_setting("chronicle/storage/timeline_cap", 10000))

	# load() not preload() — export plugin can strip the file without breaking compilation.
	if not Engine.is_editor_hint():
		if OS.is_debug_build() or OS.has_feature("CHRONICLE_DEBUG"):
			var script: GDScript = load("res://addons/chronicle/debug/debug_overlay.gd")
			if script != null:
				add_child(script.new())
	_update_processing()


func _process(delta: float) -> void:
	if _clock.is_auto_advancing():
		_clock.advance(delta)
		if _coordinator.is_idle():
			_flush_expiry()
	_watch_prune_counter += 1
	if _watch_prune_counter >= _PRUNE_INTERVAL_FRAMES:
		_watch_prune_counter = 0
		_watch_bus.prune_invalid()


## Does not emit state_reset — connect to tree_exiting for cleanup notification.
func _exit_tree() -> void:
	_reset_state()
	_type_registry.clear_handlers()
	_expression._clear_all()


func _update_processing() -> void:
	var should: bool = _clock.is_auto_advancing() or _watch_bus.get_watcher_count() > 0
	if should != _is_processing:
		_is_processing = should
		set_process(should)


func _disable_auto_advance() -> void:
	_clock.set_auto_advancing(false)
	_update_processing()


#region Write Operations

## Sets a fact value. Creates the fact if it doesn't exist. Returns [code]true[/code] if the write succeeded.
## [br][br]Keys must use [code][a-z0-9_.][/code] only. Dots separate namespaces (e.g. [code]"player.health"[/code]).
## [br][br][param value] defaults to [code]true[/code] for flag-style facts.
## [br][br][b]Lifetime note:[/b] A positive [param lifetime] automatically marks the fact transient (excluded from serialization).
## Use [method set_expiry] after [method set_fact] if you need an expiring but serializable fact.
func set_fact(key: String, value: Variant = true, transient: bool = false,
		lifetime: float = KEEP_LIFETIME) -> bool:
	return _coordinator.apply_write(key, value, lifetime, transient)


## Toggles a fact between truthy and falsy. Returns the new state, [constant DEFERRED] if deferred, or [code]null[/code] on error.
## [br][b]Note:[/b] Passing [code]transient=true[/code] promotes to transient but [code]false[/code] does not demote.
func toggle_fact(key: String, transient: bool = false,
		lifetime: float = KEEP_LIFETIME) -> Variant:
	return _wrap_deferred(_coordinator.toggle(key, lifetime, transient))


## Increments a numeric fact. Creates at 0 if absent. Returns the new value, [constant DEFERRED] if deferred, or [code]null[/code] on error.
## [br][b]Note:[/b] Passing [code]transient=true[/code] promotes to transient but [code]false[/code] does not demote.
func increment_fact(key: String, amount: float = 1.0, transient: bool = false,
		lifetime: float = KEEP_LIFETIME) -> Variant:
	return _wrap_deferred(_coordinator.increment(key, amount, lifetime, transient))


## Clamps a numeric fact to [[param min_value], [param max_value]]. No-op if absent or non-numeric. Returns the new value, [constant DEFERRED] if deferred, or [code]null[/code] on error.
## [br][b]Note:[/b] Passing [code]transient=true[/code] promotes to transient but [code]false[/code] does not demote.
func clamp_fact(key: String, min_value: float, max_value: float, transient: bool = false,
		lifetime: float = KEEP_LIFETIME) -> Variant:
	return _wrap_deferred(_coordinator.clamp(key, min_value, max_value, lifetime, transient))


## Returns [code]true[/code] if the fact existed and was erased, [code]false[/code] otherwise.
## [br][b]Note:[/b] Returns [code]false[/code] when the erase is deferred (e.g. called from a watcher callback).
func erase_fact(key: String) -> bool:
	return _coordinator.erase(key)


## Writes multiple facts in a single batch. Returns the count of changed keys.
## Mutations are applied atomically first, then [signal fact_changed] and watchers fire for each changed key in sequence. During watcher callbacks, all batch facts are already visible.
## [br][b]Note:[/b] All entries share the same [param lifetime] and [param transient] flag. For per-key control, call [method set_fact] individually.
func set_facts(entries: Dictionary, transient: bool = false,
		lifetime: float = KEEP_LIFETIME) -> int:
	if entries.is_empty():
		return 0
	return _coordinator.write_batch(entries, lifetime, transient).size()


## Returns the number of facts that existed and were erased. Not atomic — watchers fire between each erasure.
## [br][b]Note:[/b] When called at cascade depth (>= MAX_CASCADE_DEPTH) the batch is deferred, but the returned
## count still reflects the requested keys that exist NOW and will be erased during the deferred drain.
func erase_facts(keys: Array[String]) -> int:
	if keys.is_empty():
		return 0
	return _coordinator.erase_batch(keys)


## Destroys all state. Emits state_reset.
func clear() -> void:
	if not _assert_not_in_mutation("clear()"):
		return
	_reset_state()
	_coordinator.execute_clearing(state_reset.emit)

#endregion


#region Rollback

## Rolls back state to [param target_time]. Returns a [code]RollbackResult[/code] with [code].success[/code], [code].error[/code] fields.
## [br][b]Note:[/b] Cannot target times before the earliest retained timeline entry. Increase the timeline cap or record an anchor fact at t=0 for full rollback.
func rollback_to(target_time: float) -> RollbackResult:
	if not _assert_not_in_mutation("rollback_to()"):
		var r := RollbackResult.new()
		r.error = "called during mutation"
		return r
	var r: RollbackResult = _coordinator.execute_rollback_to(
		target_time, _clock.get_time(), _purge_expiry_fn,
		state_rolled_back.emit, state_reset.emit)
	if not r.success and not r.error.is_empty():
		push_error("[Chronicle] %s" % r.error)
	return r


## Undoes the last [param step_count] timeline entries. On partial revert, [code]success[/code] is false
## but [code]partial[/code] is true and state IS modified.
## [br][b]Warning:[/b] [signal state_rolled_back] and [signal state_reset] still fire on partial revert. Do not retry without checking [code]r.partial[/code].
func rollback_steps(step_count: int) -> RollbackResult:
	if step_count < 0:
		var r := RollbackResult.new()
		r.requested = step_count
		push_error("[Chronicle] rollback_steps(%d): step_count must be >= 0." % step_count)
		return r
	if step_count == 0:
		var r := RollbackResult.new()
		r.requested = 0
		r.success = true
		return r
	if not _assert_not_in_mutation("rollback_steps()"):
		var r := RollbackResult.new()
		r.requested = step_count
		r.error = "called during mutation"
		return r
	var r: RollbackResult = _coordinator.execute_rollback_steps(
		step_count, _purge_expiry_fn,
		state_rolled_back.emit, state_reset.emit)
	r.requested = step_count
	if not r.success and not r.error.is_empty():
		push_error("[Chronicle] %s" % r.error)
	return r

#endregion


#region Read & Query

## Returns the fact's value, or [param default] if absent or the key is invalid.
## [br]Keys must use [code][a-z0-9_.][/code] only. Dots separate namespaces.
func get_fact(key: String, default: Variant = null) -> Variant:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return default
	return _store.get_value(norm_key, default)


## Returns [code]true[/code] if the fact exists in the store.
func has_fact(key: String) -> bool:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return false
	return _store.has(norm_key)


## Returns [code]true[/code] if the fact exists and is truthy (non-null, non-zero, non-empty).
func is_marked(key: String) -> bool:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return false
	return ChronicleValueUtils.is_truthy(_store.get_value_raw(norm_key), _type_registry.get_truthy_fn)


## Returns [code]true[/code] if the fact exists and is marked transient (excluded from serialization).
func is_transient(key: String) -> bool:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return false
	return _store.is_transient(norm_key)


## Evaluates a Chronicle expression. Returns [code]true[/code]/[code]false[/code] on success, [code]null[/code] on parse error.
func evaluate(expression: String) -> Variant:
	var ast: Variant = _expression.parse(expression)
	if ast == null:
		return null
	return _expression.evaluate_ast(ast, _eval_resolver)


## Convenience: evaluates an expression and returns [param default] on parse error.
func evaluate_bool(expression: String, default: bool = false) -> bool:
	var result: Variant = evaluate(expression)
	return default if result == null else bool(result)


## Parses a Chronicle expression string into an AST. Returns the AST or [code]null[/code] on parse error.
func parse_expression(source: String) -> Variant:
	return _expression.parse(source)


## Evaluates a pre-parsed AST. Returns [code]bool[/code]. Uses the default fact resolver if [param resolver] is not provided.
func evaluate_expression(ast: Variant, resolver: Callable = Callable()) -> bool:
	var r: Callable = resolver if resolver.is_valid() else _eval_resolver
	return _expression.evaluate_ast(ast, r)


## Extracts all fact keys referenced in a parsed AST.
func extract_expression_keys(ast: Variant) -> Array[String]:
	return _expression.extract_keys(ast)


## Walks an expression AST, calling [param leaf_fn] on each leaf node.
func walk_expression_ast(ast: Variant, leaf_fn: Callable) -> void:
	_expression.walk_ast(ast, leaf_fn)


## Joins [param segments] with dots to build a normalized fact key.
static func build_key(segments: Array[String]) -> String:
	return ChronicleKeyCodec.build_key(segments)


## Validates a watch pattern. Returns [code]""[/code] if valid, or an error message string.
func validate_pattern(pattern: String) -> String:
	return _key_codec.validate_watch_pattern(pattern)


## Returns diagnostic counters: fact_count, watcher_count, timeline_size, timeline_cap, expiry_count.
func get_stats() -> Dictionary:
	return {
		fact_count = _store.size(),
		watcher_count = _watch_bus.get_watcher_count(),
		timeline_size = _timeline.size(),
		timeline_cap = _timeline.get_cap(),
		expiry_count = _expiry.size(),
	}


## Returns a [code]{key: value}[/code] dictionary of all facts matching [param pattern].
## [br]Pattern matching: [code]"player.*"[/code] matches all keys under player (multi-level).
## [code]"player.*.health"[/code] matches exactly one level between player and health.
func get_facts(pattern: String = "*") -> Dictionary:
	return _query.get_facts(pattern)


## Returns keys of all facts matching [param pattern].
## [br]Pattern matching: [code]"player.*"[/code] matches all keys under player (multi-level).
## [code]"player.*.health"[/code] matches exactly one level between player and health.
func get_fact_keys(pattern: String = "*") -> Array[String]:
	return _query.find(pattern)


## Returns the number of facts matching [param pattern].
func count_facts(pattern: String = "*") -> int:
	return _query.count(pattern)


## Returns the earliest timeline entry matching [param pattern], or [code]null[/code] if none.
func get_first_change(pattern: String = "*") -> Variant:
	return _query.get_first_change(pattern)


## Returns the most recent timeline entry matching [param pattern], or [code]null[/code] if none.
func get_last_change(pattern: String = "*") -> Variant:
	return _query.get_last_change(pattern)


## Returns timeline entries strictly after [param since_time] (exclusive lower bound).
func get_changes_since(since_time: float) -> Array[Dictionary]:
	if not _validate_time(since_time, "get_changes_since"):
		return []
	return _query.get_changes_since(since_time)


## Returns the full change history for a single fact key.
func get_fact_history(key: String) -> Array[Dictionary]:
	return _query.get_fact_history(key)


## Returns timeline entries in the half-open range ([param since_time], [param until_time]] (exclusive lower, inclusive upper).
func get_changes_between(since_time: float, until_time: float) -> Array[Dictionary]:
	if not _validate_time_range(since_time, until_time, "get_changes_between"):
		return []
	return _query.get_changes_between(since_time, until_time)


## Returns timeline entries for [param key] in the half-open range ([param since_time], [param until_time]].
func get_fact_changes_between(key: String, since_time: float, until_time: float) -> Array[Dictionary]:
	if not _validate_time_range(since_time, until_time, "get_fact_changes_between"):
		return []
	return _query.get_fact_changes_between(key, since_time, until_time)

#endregion


#region Watchers

## Registers a watcher. [param callback] receives [code](key: String, value: Variant, old_value: Variant)[/code].
## Returns a watch ID for [method unwatch], or [code]-1[/code] on failure.
## [br][param once]: if [code]true[/code], the watcher auto-removes after the first match. Prefer [method watch_once] for clarity.
## [br]Pattern matching: [code]"player.*"[/code] matches all keys under player (multi-level).
## [code]"player.*.health"[/code] matches exactly one level between player and health.
func watch(pattern: String, callback: Callable, once: bool = false) -> int:
	if pattern.is_empty():
		push_error("[Chronicle] watch(): empty pattern — programmer error.")
		return -1
	var id: int = _watch_bus.watch(pattern, callback, once)
	_update_processing()
	return id


## Registers a watcher that triggers on any of the given [param patterns]. Returns a watch ID or [code]-1[/code].
func watch_any(patterns: Array[String], callback: Callable, once: bool = false) -> int:
	if patterns.is_empty():
		push_error("[Chronicle] watch_any(): empty patterns array — programmer error.")
		return -1
	var id: int = _watch_bus.watch_any(patterns, callback, once)
	_update_processing()
	return id


## Convenience for [code]watch(pattern, callback, true)[/code]. Auto-unwatches after the first match.
func watch_once(pattern: String, callback: Callable) -> int:
	return watch(pattern, callback, true)


## Convenience for [code]watch_any(patterns, callback, true)[/code]. Auto-unwatches after the first match.
func watch_any_once(patterns: Array[String], callback: Callable) -> int:
	return watch_any(patterns, callback, true)


## Removes a watcher by ID. Returns [code]true[/code] if found and removed.
func unwatch(watch_id: int) -> bool:
	var result: bool = _watch_bus.unwatch(watch_id)
	_update_processing()
	return result


## Removes all watchers registered with the exact [param pattern]. Also removes entire watch_any groups that contain the pattern.
func unwatch_pattern(pattern: String) -> int:
	var result: int = _watch_bus.unwatch_pattern(pattern)
	_update_processing()
	return result


## Removes every registered watcher.
func unwatch_all() -> void:
	_watch_bus.unwatch_all()
	_update_processing()

#endregion


#region Time & Expiry

## Returns the current game clock time.
func get_game_time() -> float:
	return _clock.get_time()


## Returns [code]true[/code] if the game clock auto-advances each frame.
func is_auto_advancing() -> bool:
	return _clock.is_auto_advancing()


## Enables or disables per-frame auto-advance of the game clock.
func set_auto_advancing(enabled: bool) -> void:
	_clock.set_auto_advancing(enabled)
	_update_processing()


## Forward jumps only — use [method rollback_to] to go backwards.
## [br]No-op if [param value] equals the current time. Values less than current time are ignored with a warning.
func set_game_time(value: float) -> void:
	if not ChronicleValueUtils.is_valid_float(value):
		push_error("[Chronicle] set_game_time(): NaN/INF value — ignored.")
		return
	if value < _clock.get_time():
		push_warning("[Chronicle] set_game_time(%.4f) is before current time (%.4f) — ignored. Use rollback_to() to go backwards." % [value, _clock.get_time()])
		return
	if value == _clock.get_time():
		return
	_clock.set_time(value)
	if _coordinator.is_idle():
		_flush_expiry()


## Advances the game clock by [param delta] seconds.
func advance_game_time(delta: float) -> void:
	if not ChronicleValueUtils.is_valid_float(delta):
		push_error("[Chronicle] advance_game_time(): NaN/INF delta — ignored.")
		return
	if delta <= 0.0:
		if delta < 0.0:
			push_warning("[Chronicle] advance_game_time(%.4f): negative delta — ignored." % delta)
		return
	_clock.advance(delta)
	if _coordinator.is_idle():
		_flush_expiry()


## Returns [constant EXPIRY_NONE] if the fact has no expiry or the key is invalid.
func get_expiry_remaining(key: String) -> float:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return EXPIRY_NONE
	if not _expiry.has(norm_key):
		return EXPIRY_NONE
	return _expiry.get_remaining(norm_key)


## Returns [code]true[/code] if the fact has an active expiry timer.
func has_expiry(key: String) -> bool:
	var norm_key: String = _key_codec.validate_and_normalize(key)
	if norm_key.is_empty():
		return false
	return _expiry.has(norm_key)


## Adds or updates an expiry timer on an existing fact without changing its value. Pass [code]0.0[/code] to remove expiry.
## [br][b]Note:[/b] Returns [code]false[/code] when the write is deferred (e.g. called from a watcher callback).
func set_expiry(key: String, lifetime: float) -> bool:
	return _coordinator.write_expiry(key, lifetime)


## Removes the expiry timer from a fact. Shorthand for [code]set_expiry(key, 0.0)[/code].
## [br][b]Note:[/b] Returns [code]false[/code] when deferred.
func clear_expiry(key: String) -> bool:
	return set_expiry(key, 0.0)


## Processes pending expiries immediately. Call before [method serialize] to remove expired facts from the save.
func flush_expiry() -> bool:
	if not _coordinator.is_idle():
		push_warning("[Chronicle] flush_expiry() called during mutation — skipped.")
		return false
	_flush_expiry()
	return true

#endregion


#region Serialization & I/O

## Serializes all non-transient facts and timeline entries to a Dictionary.
## [br][param timeline_cap]: pass [constant SERIALIZE_ALL] for no cap, a positive integer to override, or [constant SERIALIZE_USE_SETTING] (default) to use the project setting [code]chronicle/storage/serialize_timeline_cap[/code].
func serialize(timeline_cap: int = SERIALIZE_USE_SETTING) -> Dictionary:
	return _serializer.serialize(_timeline, _expiry, _clock, timeline_cap)


## Restores state from a serialized Dictionary. Returns [code]false[/code] on invalid data.
## [br][b]Note:[/b] The input [param data] Dictionary may be mutated in-place during migration.
func deserialize(data: Dictionary) -> bool:
	if not _assert_not_in_mutation("deserialize()"):
		return false
	var snapshot: ChronicleSerializer.Snapshot = _serializer.deserialize(data)
	if snapshot == null:
		return false
	_reset_state(true)
	var failed: int = _coordinator.execute_restore(
		snapshot.facts, snapshot.timeline_entries, snapshot.tick,
		snapshot.expiry_entries, snapshot.game_time, snapshot.auto_advance,
		state_reset.emit)
	if failed < 0:
		return false
	if failed > 0:
		push_warning("[Chronicle] deserialize: %d facts failed to restore." % failed)
	_update_processing()
	return true


## Serializes and saves state to [param path]. Returns [constant OK] on success.
func save_file(path: String) -> Error:
	if path.is_empty():
		push_error("[Chronicle] save_file(): empty path — ignored.")
		return ERR_FILE_BAD_PATH
	var data: Dictionary = serialize()
	return _save_fn.call(path, data)


## Loads and deserializes state from [param path]. Returns [constant OK] on success.
func load_file(path: String) -> Error:
	if path.is_empty():
		push_error("[Chronicle] load_file(): empty path — ignored.")
		return ERR_FILE_BAD_PATH
	var data: Variant = _load_fn.call(path)
	if data == null:
		push_error("[Chronicle] load_file(\"%s\"): file could not be read or returned null." % path)
		return ERR_FILE_CANT_READ
	if data is not Dictionary:
		push_error("[Chronicle] load_file(): load function returned %s, expected Dictionary." % type_string(typeof(data)))
		return ERR_INVALID_DATA
	if not deserialize(data):
		return ERR_INVALID_DATA
	return OK

#endregion


#region Configuration

## Overrides the default file save callable. Signature: [code]func(path: String, data: Dictionary) -> Error[/code].
func set_save_fn(save_fn: Callable) -> void:
	if not save_fn.is_valid():
		push_error("[Chronicle] set_save_fn() received invalid Callable — reverting to default.")
		_save_fn = ChronicleFileIO.save_to_file
		return
	_save_fn = save_fn


## Overrides the default file load callable. Signature: [code]func(path: String) -> Variant[/code].
func set_load_fn(load_fn: Callable) -> void:
	if not load_fn.is_valid():
		push_error("[Chronicle] set_load_fn() received invalid Callable — reverting to default.")
		_load_fn = ChronicleFileIO.load_from_file
		return
	_load_fn = load_fn


## Replaces the pattern matcher used for watches and queries. Pass [code]force=true[/code] to clear existing watchers first.
func set_pattern_matcher(matches_fn: Callable, validate_pattern_fn: Callable, force: bool = false) -> void:
	if not matches_fn.is_valid() or not validate_pattern_fn.is_valid():
		push_error("[Chronicle] set_pattern_matcher(): both callables must be valid.")
		return
	if _watch_bus.get_watcher_count() > 0:
		if not force:
			push_error("[Chronicle] Cannot change pattern matcher while %d watchers are registered. Pass force=true to clear all watchers first." % _watch_bus.get_watcher_count())
			return
		_watch_bus.unwatch_all()
	_matches_fn = matches_fn
	_query.set_matcher(matches_fn)
	_watch_bus.set_matcher(matches_fn, validate_pattern_fn)
	_key_codec.set_validate_pattern_fn(validate_pattern_fn)
	_key_codec.clear()
	_update_processing()


## Resets deduplication so previously-suppressed warnings can fire again.
func clear_warnings() -> void:
	_warnings.clear()


## Sets the maximum number of timeline entries retained in memory.
func set_timeline_cap(cap: int) -> void:
	if not _assert_not_in_mutation("set_timeline_cap()"):
		return
	_timeline.set_cap(cap)


## When > 0, new keys beyond this count are rejected. 0 disables.
func set_store_hard_cap(cap: int) -> void:
	_coordinator.set_hard_cap(cap)


## Returns the current timeline entry cap.
func get_timeline_cap() -> int:
	return _timeline.get_cap()


## Returns the current store hard cap (0 means disabled).
func get_store_hard_cap() -> int:
	return _coordinator.get_hard_cap()


## Sets a write interceptor called before every non-erase mutation.
## [br]Signature: [code]func(key: String, value: Variant, old_value: Variant) -> Variant[/code].
## [br]Return the (possibly modified) value, or [constant REJECT] to prevent the write.
## [br]Pass an invalid Callable to remove the interceptor.
func set_write_interceptor(fn: Callable) -> void:
	_coordinator.set_write_interceptor(fn)

#endregion


#region Type & Expression Registration

## Registers a custom type for serialization roundtrip.
## [br][br][param type_id]: The Godot type ID ([code]typeof(your_value)[/code]).
## [br][param tag]: Unique string tag for the serialized format (e.g. [code]"my_custom_type"[/code]).
## [br][param pack_fn]: [code]func(value) -> Dictionary[/code] — converts the value to a serializable Dictionary.
## [br][param unpack_fn]: [code]func(dict: Dictionary) -> Variant[/code] — reconstructs the value from the Dictionary.
## [br][param copy_fn]: [code]func(value) -> Variant[/code] — deep-copies the value. Defaults to pack→unpack roundtrip.
## [br][param keys]: Required Dictionary keys for validation. Empty = accept any structure from [param pack_fn].
## [br][param truthy_fn]: [code]func(value) -> bool[/code] — custom truthiness check for [method is_marked] / expressions.
## [br][param force]: If [code]true[/code], overrides an existing registration for [param type_id].
## [br][br]Returns [code]true[/code] on success, [code]false[/code] if the tag is reserved or already registered (without force).
func register_type(type_id: int, tag: String, pack_fn: Callable, unpack_fn: Callable,
		copy_fn: Callable = Callable(), keys: Array[String] = [],
		truthy_fn: Callable = Callable(), force: bool = false) -> bool:
	return _type_registry.register_type(type_id, tag, pack_fn, unpack_fn, copy_fn, keys, truthy_fn, force)


## Registers a script-based custom type for serialization. Unlike [method register_type], this
## matches values by their attached GDScript, enabling support for script-defined value objects.
## [br][br][param script]: The GDScript to match (e.g. [code]preload("res://my_type.gd")[/code]).
## [br][param tag]: Unique string tag for the serialized format.
## [br][param pack_fn]: [code]func(value) -> Dictionary[/code] — converts the value to a serializable Dictionary.
## [br][param unpack_fn]: [code]func(dict: Dictionary) -> Variant[/code] — reconstructs the value from the Dictionary.
## [br][param copy_fn]: [code]func(value) -> Variant[/code] — deep-copies the value. Defaults to pack->unpack roundtrip.
## [br][param required_keys]: Required Dictionary keys for validation.
## [br][param truthy_fn]: [code]func(value) -> bool[/code] — custom truthiness check.
## [br][br]Returns [code]true[/code] on success, [code]false[/code] if the tag is reserved or already registered.
func register_script_type(script: GDScript, tag: String, pack_fn: Callable,
		unpack_fn: Callable, copy_fn: Callable = Callable(),
		required_keys: Array[String] = [], truthy_fn: Callable = Callable()) -> bool:
	return _type_registry.register_script_type(script, tag, pack_fn, unpack_fn, copy_fn, required_keys, truthy_fn)


## Removes a previously registered custom type.
func unregister_type(type_id: int) -> bool:
	return _type_registry.unregister_type(type_id)


## Returns [code]true[/code] if a custom type with [param type_id] is registered.
func is_type_registered(type_id: int) -> bool:
	return _type_registry.is_type_registered(type_id)


## Returns [code]true[/code] if [param value] is a storable Chronicle type (built-in or registered).
func is_valid_type(value: Variant) -> bool:
	return _type_registry.is_valid_type(value)


## Returns [code]true[/code] if [param keyword] is registered as a custom expression keyword.
func is_keyword_registered(keyword: String) -> bool:
	return _expression.get_custom_token_type(keyword) != null


## Registers a data migration from [param from_version] to [code]from_version + 1[/code].
## [br][param migrate_fn]: [code]func(data: Dictionary) -> Dictionary[/code] — receives the save data and must return the migrated version with [code]data["version"] = from_version + 1[/code].
func register_migration(from_version: int, migrate_fn: Callable, force: bool = false) -> bool:
	return _serializer.register_migration(from_version, migrate_fn, force)


## Registers a custom expression AST node handler.
## [br][param node_type]: String identifier for the AST node (e.g. [code]"between"[/code]).
## [br][param eval_fn]: [code]func(ast: Dictionary, get_fact_fn: Callable) -> Variant[/code] — evaluates the node.
## [br][param keys_fn]: [code]func(ast: Dictionary, keys: Array[String]) -> void[/code] — appends referenced fact keys.
## [br][param walk_fn]: [code]func(ast: Dictionary, visitor_fn: Callable) -> void[/code] — walks child nodes.
## [br][param force]: If [code]true[/code], overrides an existing handler for the same [param node_type].
## [br][br]Returns [code]true[/code] on success. For simple single-key operators, prefer [method register_simple_expression].
func register_expression_handler(node_type: String, eval_fn: Callable,
		keys_fn: Callable, walk_fn: Callable, force: bool = false) -> bool:
	return _expression.register_expression_handler(node_type, eval_fn, keys_fn, walk_fn, force)


## Returns [code]true[/code] if [param node_type] is registered as a custom (non-built-in) expression handler.
func is_expression_handler_registered(node_type: String) -> bool:
	return _expression.is_expression_handler_registered(node_type)


## Removes a previously registered custom expression handler. Returns [code]true[/code] if found and removed.
func unregister_expression_handler(node_type: String) -> bool:
	return _expression.unregister_expression_handler(node_type)


## Registers a custom keyword operator for expression parsing.
## [br][param keyword]: The keyword string (e.g. [code]"BETWEEN"[/code]).
## [br][param token_type]: Integer token type for the lexer. Must be >= 1000 ([code]Lexer.FIRST_CUSTOM_TOKEN_TYPE[/code]).
## [br][param parse_fn]: [code]func(state: ParseState, operand: Dictionary, negated: bool) -> Variant[/code] — receives the parser state, the left-hand operand [code]{op_type = "key", value = <key_string>}[/code], and whether [code]NOT[/code] preceded the keyword. Returns an AST node Dictionary.
## [br][param negatable]: If [code]true[/code], the keyword can be prefixed with [code]NOT[/code] (e.g. [code]NOT BETWEEN[/code]).
## [br][br]Returns [code]true[/code] on success. Must be paired with [method register_expression_handler] for the same node type.
func register_keyword(keyword: String, token_type: int, parse_fn: Callable, negatable: bool = false) -> bool:
	return _expression.register_keyword(keyword, token_type, parse_fn, negatable)


## Removes a previously registered custom keyword from expression parsing. Returns [code]true[/code] if found and removed.
func unregister_keyword(keyword: String) -> bool:
	return _expression.unregister_keyword(keyword)


## Convenience wrapper for registering a single-key expression operator.
## [br][param keyword]: The AST node type string (e.g. [code]"starts_with"[/code]).
## [br][param eval_fn]: [code]func(key: String, arg: Variant, resolver: Callable) -> bool[/code] — receives the key name, the operator argument from the AST, and a resolver callable.
## [br][br]Automatically generates keys/walk functions that extract the single [code]"key"[/code] field.
func register_simple_expression(keyword: String, eval_fn: Callable) -> bool:
	var keys_fn := func(ast: Dictionary, keys: Array[String]) -> void:
		var k: String = ast.get("key", "")
		if not k.is_empty() and k not in keys:
			keys.append(k)
	var walk_fn := func(ast: Dictionary, leaf_fn: Callable) -> void:
		leaf_fn.call(ast)
	var wrapped_eval := func(ast: Dictionary, resolver: Callable) -> bool:
		return eval_fn.call(ast.key, ast.get("arg"), resolver)
	return _expression.register_expression_handler(keyword, wrapped_eval, keys_fn, walk_fn)

#endregion


func _reset_state(keep_watchers: bool = false) -> void:
	_store.clear()
	_key_codec.clear()
	_timeline.clear()
	_expiry.clear()
	_clock.clear()
	_query.clear()
	_coordinator.clear()
	_warnings.clear()
	_serializer.clear_user_migrations()
	if not keep_watchers:
		_watch_bus.unwatch_all()
	_watch_prune_counter = 0
	_update_processing()


func _assert_not_in_mutation(context: String) -> bool:
	if _coordinator.is_in_mutation():
		push_error("[Chronicle] %s called during mutation — not permitted. Defer the call or restructure to avoid calling from watcher/signal handlers." % context)
		return false
	return true


func _flush_expiry() -> void:
	_coordinator.execute_expiry_flush(fact_expired.emit)
	_update_processing()


func _validate_time_range(since_time: float, until_time: float, method: String) -> bool:
	if not _validate_time(since_time, method) or not _validate_time(until_time, method):
		return false
	if since_time > until_time:
		push_warning("[Chronicle] %s: since_time (%.4f) > until_time (%.4f)." % [method, since_time, until_time])
		return false
	return true


func _validate_time(value: float, method: String) -> bool:
	if not ChronicleValueUtils.is_valid_float(value):
		push_error("[Chronicle] %s: NaN/Inf time — ignored." % method)
		return false
	if value < 0.0:
		push_error("[Chronicle] %s: negative time (%.4f) — ignored." % [method, value])
		return false
	return true


func _wrap_deferred(result: Variant) -> Variant:
	if result is ChronicleWriteCoordinator._DeferredSentinel:
		return DEFERRED
	return result
