## Base class for all Chronicle tests. Extend this instead of GutTest.
## Exception: tests with no Chronicle dependency (expression compiler/evaluator, pattern_matcher) extend GutTest directly.
## EventCollector replaces GUT's signal watcher — it captures (key, value, old_value, time) with domain assertions.
## CompanionFactory creates Gate/Reactor/Recorder from config dicts with key validation and enum aliases.
## Benchmarks are excluded from GUT via filename prefix (no test_ prefix).
class_name ChronicleTestSuite
extends GutTest

const Chronicle := preload("res://addons/chronicle/core/chronicle.gd")

var _chronicle: Node
var _temp_files: Array[String] = []
var _default_timeline_cap: int = 0
var _signal_snapshot: Dictionary = {}


func before_each() -> void:
	_chronicle = get_node("/root/Chronicle")
	_chronicle.clear()
	# clear() does NOT reset these persistent configs, so reset them to defaults here —
	# otherwise a test that overrides the save/load callables, hard cap, or write
	# interceptor leaks that config into every later test (order-dependent flakiness).
	_chronicle.set_save_fn(ChronicleFileIO.save_to_file)
	_chronicle.set_load_fn(ChronicleFileIO.load_from_file)
	_chronicle.set_store_hard_cap(0)
	_chronicle.set_write_interceptor(Callable())
	_chronicle.set_pattern_matcher(ChroniclePatternMatcher.matches, ChroniclePatternMatcher.validate)
	_default_timeline_cap = _chronicle.get_timeline_cap()
	_signal_snapshot = _take_signal_snapshot()


func after_each() -> void:
	_chronicle.unwatch_all()
	_disconnect_new_signals()
	for path in _temp_files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
	_temp_files.clear()
	_chronicle.set_timeline_cap(_default_timeline_cap)
	_chronicle = null


func _take_signal_snapshot() -> Dictionary:
	var snap: Dictionary = {}
	for sig_name: String in ["fact_changed", "state_reset", "state_rolled_back", "fact_expired"]:
		var conns: Array = _chronicle.get_signal_connection_list(sig_name)
		var callables: Array[Callable] = []
		for conn: Dictionary in conns:
			callables.append(conn["callable"])
		snap[sig_name] = callables
	return snap


func _disconnect_new_signals() -> void:
	for sig_name: String in ["fact_changed", "state_reset", "state_rolled_back", "fact_expired"]:
		var old_callables: Array = _signal_snapshot.get(sig_name, [])
		var conns: Array = _chronicle.get_signal_connection_list(sig_name)
		for conn: Dictionary in conns:
			var c: Callable = conn["callable"]
			if c not in old_callables:
				_chronicle.disconnect(sig_name, c)


# ── EventCollector convenience factories ─────────────────────────────────────
# These eliminate the need to pass `self` and `_chronicle` at every call site.


## Create a persistent watcher and return its EventCollector.
func watch_events(pattern: Variant) -> EventCollector:
	var collector := EventCollector.watch(self, _chronicle, pattern)
	assert_gte(collector.watch_id, 0,
		"watch_events('%s') failed — invalid pattern (watch_id=%d)" % [str(pattern), collector.watch_id])
	return collector


## Create a one-shot watcher and return its EventCollector.
func watch_once_events(pattern: Variant) -> EventCollector:
	var collector := EventCollector.watch_once(self, _chronicle, pattern)
	assert_gte(collector.watch_id, 0,
		"watch_once_events('%s') failed — invalid pattern (watch_id=%d)" % [str(pattern), collector.watch_id])
	return collector


## Create a bare EventCollector (no watch registered).
## Useful when you need to plumb the callback manually.
func make_collector() -> EventCollector:
	return EventCollector.standalone(self)


## Connect an EventCollector to any Chronicle/companion signal (2-4 args).
## Works for fact_changed, fact_matched, fact_recorded, and fact_expired.
func collect_signal(source: Node, signal_name: String) -> EventCollector:
	return EventCollector.connect_signal(self, source, signal_name, _chronicle)


## Capture ANY-arity signal emissions (for 0/1-arg lifecycle signals).
func collect_any_signal(source: Node, signal_name: String) -> EventCollector:
	return EventCollector.connect_any(self, source, signal_name)


# ── Node creation convenience ─────────────────────────────────────────────────


func add_node(node_name: String = "") -> Node:
	var node: Node = autoqfree(Node.new())
	if node_name != "":
		node.name = node_name
	get_tree().root.add_child(node)
	return node


func add_node_2d(node_name: String = "") -> Node2D:
	var node: Node2D = autoqfree(Node2D.new())
	node.visible = true
	if node_name != "":
		node.name = node_name
	get_tree().root.add_child(node)
	return node


func add_signaled_node(signal_name: String, signal_args: Array = []) -> Node:
	var node: Node = add_node()
	node.add_user_signal(signal_name, signal_args)
	return node


# ── Companion node creation ──────────────────────────────────────────────────


func add_gate(condition: String, config: Dictionary = {}) -> Node2D:
	var cfg := config.duplicate()
	cfg["condition"] = condition
	var target := add_node_2d()
	var gate: Node = CompanionFactory.make_gate(cfg)
	target.add_child(gate)
	return target


func add_reactor(config: Dictionary) -> Node:
	var cfg := config.duplicate()
	if not cfg.has("target_method"):
		cfg["target_method"] = "on_fact"
	var parent: Node = autoqfree(Node.new())
	parent.set_script(preload("res://test/support/chronicle_spy_node.gd"))
	get_tree().root.add_child(parent)
	var reactor: Node = CompanionFactory.make_reactor(cfg)
	parent.add_child(reactor)
	return reactor


func add_recorder(config: Dictionary) -> Node:
	var signal_name: String = config.get("trigger_signal", "")
	assert(not signal_name.is_empty(), "add_recorder: config must include 'trigger_signal'")
	var parent: Node = add_signaled_node(signal_name)
	var recorder: Node = CompanionFactory.make_recorder(config)
	parent.add_child(recorder)
	return parent


## Assert the SpyNode parent of [reactor] recorded [expected] on_fact calls.
func assert_spy_calls(reactor: Node, expected: int) -> void:
	var calls: Array = reactor.get_parent().calls
	assert_eq(calls.size(), expected,
		"spy calls: expected %d, got %d (%s)" % [expected, calls.size(), str(calls)])


## Assert a specific recorded on_fact call. Pass EventCollector.SKIP to skip a field.
func assert_spy_call(reactor: Node, index: int, key: Variant = EventCollector.SKIP,
		value: Variant = EventCollector.SKIP, old_value: Variant = EventCollector.SKIP) -> void:
	var calls: Array = reactor.get_parent().calls
	if index < 0 or index >= calls.size():
		assert_true(false, "assert_spy_call(%d): out of range (have %d)" % [index, calls.size()])
		return
	var c: Dictionary = calls[index]
	if not (key is StringName and key == EventCollector.SKIP):
		assert_eq(c.key, key, "spy.calls[%d].key" % index)
	if not (value is StringName and value == EventCollector.SKIP):
		assert_eq(c.value, value, "spy.calls[%d].value" % index)
	if not (old_value is StringName and old_value == EventCollector.SKIP):
		assert_eq(c.old_value, old_value, "spy.calls[%d].old_value" % index)


## Builds a linear cascade: watch("<prefix>.i") -> set_fact("<prefix>.(i+1)").
## Returns the final key ("<prefix>.<depth>").
func build_cascade_chain(prefix: String, depth: int = 8) -> String:
	for i: int in range(depth):
		var nk: String = "%s.%d" % [prefix, i + 1]
		_chronicle.watch("%s.%d" % [prefix, i], func(_k, _v, _o, next: String = nk) -> void:
			_chronicle.set_fact(next, true)
		)
	return "%s.%d" % [prefix, depth]


func make_counter() -> Array:
	return [0]


func make_signal_sink(counter: Array) -> Callable:
	return func() -> void: counter[0] += 1


# ── Manual clock helpers ─────────────────────────────────────────────────────


func set_time(t: float) -> void:
	_chronicle.set_game_time(t)


func advance_time(delta: float) -> void:
	_chronicle.advance_game_time(delta)


## Assert the game clock equals [expected].
func assert_game_time(expected: float) -> void:
	assert_eq(_chronicle.get_game_time(), expected,
		"game_time: expected %s, got %s" % [str(expected), str(_chronicle.get_game_time())])


## Assert the number of active watchers.
func assert_watcher_count(expected: int) -> void:
	var actual: int = _chronicle.get_stats().watcher_count
	assert_eq(actual, expected, "watcher_count: expected %d, got %d" % [expected, actual])


## Assert a rollback result succeeded.
func assert_rollback_ok(result: Variant) -> void:
	assert_true(result.success, "expected rollback to succeed, got %s" % str(result))


## Assert a rollback result was rejected / did not succeed.
func assert_rollback_rejected(result: Variant) -> void:
	assert_false(result.success, "expected rollback to be rejected, got %s" % str(result))


# ── Fact assertions ───────────────────────────────────────────────────────────


func assert_fact(key: String, expected: Variant) -> void:
	assert_true(_chronicle.has_fact(key), "expected fact '%s' to exist" % key)
	assert_eq(_chronicle.get_fact(key), expected, "fact '%s'" % key)


func assert_no_fact(key: String) -> void:
	assert_false(_chronicle.has_fact(key), "expected fact '%s' to NOT exist (value: %s)" \
		% [key, str(_chronicle.get_fact(key))])


func assert_marked(key: String) -> void:
	assert_true(_chronicle.is_marked(key), "expected '%s' to be marked" % key)


func assert_not_marked(key: String) -> void:
	assert_false(_chronicle.is_marked(key), "expected '%s' to NOT be marked" % key)


func assert_fact_count(pattern: String, expected: int) -> void:
	assert_eq(_chronicle.count_facts(pattern), expected, "count('%s')" % pattern)


func assert_facts(expected: Dictionary) -> void:
	for key: String in expected:
		assert_fact(key, expected[key])


## Assert the write coordinator is idle (no cascade in progress).
## is_idle() already requires _cascade_depth == 0, so one assertion suffices;
## the message reports both pieces of state so a failure is self-explanatory.
func assert_idle() -> void:
	var coord: Object = _chronicle._coordinator
	assert_true(coord.is_idle(),
		"expected coordinator to be idle (mode=%s, cascade_depth=%d)" \
		% [str(coord._mode), coord._cascade_depth])


## Assert the fact has an active expiry.
func assert_has_expiry(key: String) -> void:
	assert_true(_chronicle.has_expiry(key),
		"expected '%s' to have an active expiry" % key)


## Assert the fact has no active expiry.
func assert_no_expiry(key: String) -> void:
	assert_false(_chronicle.has_expiry(key),
		"expected '%s' to NOT have an active expiry" % key)


## Assert the fact exists (value not checked). Use when only existence matters.
func assert_has_fact(key: String) -> void:
	assert_true(_chronicle.has_fact(key), "expected fact '%s' to exist" % key)


## Assert the fact exists and is marked transient.
func assert_transient(key: String) -> void:
	assert_true(_chronicle.is_transient(key), "expected '%s' to be transient" % key)


## Assert the fact is not transient.
func assert_not_transient(key: String) -> void:
	assert_false(_chronicle.is_transient(key), "expected '%s' to NOT be transient" % key)


## Assert the stored value's type matches a TYPE_* constant.
func assert_fact_type(key: String, expected_type: int) -> void:
	assert_true(_chronicle.has_fact(key), "assert_fact_type: '%s' does not exist" % key)
	var actual: int = typeof(_chronicle.get_fact(key))
	assert_eq(actual, expected_type,
		"fact '%s' type: expected %s, got %s" % [key, type_string(expected_type), type_string(actual)])


# ── Gate assertions (HIDE/SHOW modes only) ────────────────────────────────────


func assert_gate_open(target: CanvasItem) -> void:
	assert_true(target.visible, "gate target '%s' should be visible (open)" % target.name)
	assert_eq(target.process_mode, Node.PROCESS_MODE_INHERIT, \
		"gate target '%s' process_mode should be INHERIT (open)" % target.name)


func assert_gate_closed(target: CanvasItem) -> void:
	assert_false(target.visible, "gate target '%s' should be hidden (closed)" % target.name)
	assert_eq(target.process_mode, Node.PROCESS_MODE_DISABLED, \
		"gate target '%s' process_mode should be DISABLED (closed)" % target.name)


# ── History assertions ────────────────────────────────────────────────────────


func assert_history(key: String, expected_values: Array, expected_times: Array = [],
		expected_old_values: Array = []) -> void:
	var history: Array[Dictionary] = _chronicle.get_fact_history(key)
	assert_eq(history.size(), expected_values.size(), "fact_history('%s') count" % key)
	if not expected_old_values.is_empty():
		assert_eq(expected_old_values.size(), expected_values.size(),
			"fact_history('%s'): expected_old_values length (%d) != expected_values length (%d)" \
			% [key, expected_old_values.size(), expected_values.size()])
	for i: int in range(mini(history.size(), expected_values.size())):
		if expected_values[i] == null:
			assert_null(history[i].value, "fact_history('%s')[%d]" % [key, i])
		else:
			assert_eq(history[i].value, expected_values[i], "fact_history('%s')[%d]" % [key, i])
	if not expected_times.is_empty():
		assert_eq(expected_times.size(), expected_values.size(),
			"fact_history('%s'): expected_times length (%d) != expected_values length (%d)" \
			% [key, expected_times.size(), expected_values.size()])
		for i: int in range(mini(history.size(), expected_times.size())):
			assert_eq(history[i].time, expected_times[i], "fact_history('%s')[%d].time" % [key, i])
	if not expected_old_values.is_empty():
		for i: int in range(mini(history.size(), expected_old_values.size())):
			if expected_old_values[i] == null:
				assert_null(history[i].old_value, "fact_history('%s')[%d].old_value" % [key, i])
			else:
				assert_eq(history[i].old_value, expected_old_values[i],
					"fact_history('%s')[%d].old_value" % [key, i])


## Assert the number of history entries for [key].
func assert_history_size(key: String, expected: int) -> void:
	var n: int = _chronicle.get_fact_history(key).size()
	assert_eq(n, expected, "fact_history('%s') size: expected %d, got %d" % [key, expected, n])


## Assert the first history entry's value for [key].
func assert_history_first(key: String, expected_value: Variant) -> void:
	var h: Array[Dictionary] = _chronicle.get_fact_history(key)
	assert_gt(h.size(), 0, "fact_history('%s') is empty" % key)
	if h.size() > 0:
		assert_eq(h[0].value, expected_value, "fact_history('%s')[0].value" % key)


## Assert the last history entry's value for [key].
func assert_history_last(key: String, expected_value: Variant) -> void:
	var h: Array[Dictionary] = _chronicle.get_fact_history(key)
	assert_gt(h.size(), 0, "fact_history('%s') is empty" % key)
	if h.size() > 0:
		assert_eq(h[-1].value, expected_value, "fact_history('%s')[-1].value" % key)


## Assert the earliest timeline entry matching [pattern] has the given key/value.
func assert_first_change(pattern: String, expected_key: String, expected_value: Variant) -> void:
	var entry: Variant = _chronicle.get_first_change(pattern)
	assert_not_null(entry, "expected a first change for '%s', got null" % pattern)
	if entry == null:
		return
	assert_eq(entry.key, expected_key, "first_change('%s').key" % pattern)
	assert_eq(entry.value, expected_value, "first_change('%s').value" % pattern)


## Assert the most recent timeline entry matching [pattern] has the given key/value.
func assert_last_change(pattern: String, expected_key: String, expected_value: Variant) -> void:
	var entry: Variant = _chronicle.get_last_change(pattern)
	assert_not_null(entry, "expected a last change for '%s', got null" % pattern)
	if entry == null:
		return
	assert_eq(entry.key, expected_key, "last_change('%s').key" % pattern)
	assert_eq(entry.value, expected_value, "last_change('%s').value" % pattern)


## Assert no timeline entry matches [pattern].
func assert_no_first_change(pattern: String) -> void:
	assert_null(_chronicle.get_first_change(pattern),
		"expected no first change for '%s'" % pattern)


func assert_no_last_change(pattern: String) -> void:
	assert_null(_chronicle.get_last_change(pattern),
		"expected no last change for '%s'" % pattern)


## Assert the number of timeline changes strictly after [since_time].
func assert_changes_since_count(since_time: float, expected: int) -> void:
	var n: int = _chronicle.get_changes_since(since_time).size()
	assert_eq(n, expected, "changes_since(%s): expected %d, got %d" % [str(since_time), expected, n])


# ── Warning assertions ───────────────────────────────────────────────────────


func assert_has_warning(node: Node, substring: String) -> void:
	var warnings: PackedStringArray = node._get_configuration_warnings()
	for warning: String in warnings:
		if substring in warning:
			pass_test("found warning containing '%s'" % substring)
			return
	assert_true(false,
		"expected warning containing '%s' on '%s'. Got: %s"
		% [substring, node.name, str(Array(warnings))])


func assert_no_warnings(node: Node) -> void:
	var warnings: PackedStringArray = node._get_configuration_warnings()
	assert_true(warnings.is_empty(),
		"expected no warnings on '%s'. Got: %s" % [node.name, str(Array(warnings))])


## Serialize the current Chronicle, clear it, and deserialize back into the same
## instance. For "does state survive a save/load cycle" tests. Returns the
## serialized Dictionary so callers can inspect the wire format.
func roundtrip() -> Dictionary:
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	assert_true(_chronicle.deserialize(data), "roundtrip(): deserialize should succeed")
	return data


## Serialize the current Chronicle and deserialize into a FRESH, autoqueued
## instance. For "does state survive a save/load into a new instance" tests and
## any case needing two live instances. Asserts deserialize succeeds.
func serialize_into_new() -> Node:
	var c2: Node = add_child_autoqfree(Chronicle.new())
	assert_true(c2.deserialize(_chronicle.serialize()),
		"serialize_into_new(): deserialize should succeed")
	return c2


## Register a path for automatic deletion in after_each (the path and its ".bak"
## companion). Use when a test writes a file via a path the base does not already
## track (e.g. direct ChronicleFileIO / _chronicle.save_file calls).
func register_temp(path: String) -> void:
	_temp_files.append(path)


func save_temp(path: String, data: Dictionary) -> Error:
	_temp_files.append(path)
	return ChronicleFileIO.save_to_file(path, data)


static func read_file(path: String) -> Variant:
	var raw: Variant = ChronicleFileIO.load_from_file(path)
	if raw == null:
		return null
	var registry := ChronicleTypeRegistry.new()
	var codec := ChronicleTypeCodec.new(registry)
	ChronicleBuiltinTypes.register_all(registry, codec)
	return codec.decode_value(raw)
