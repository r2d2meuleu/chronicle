## Lightweight watcher event collector for Chronicle test suites.
##
## Captures (key, value, old_value) triples from Chronicle's watch/watch_once
## callbacks and provides typed accessors + assertion helpers that delegate
## to GUT's built-in assertion API.
##
## Usage:
##   var events := collect_signal(chronicle_node, "fact_changed")  # via ChronicleTestSuite
##   # or directly: EventCollector.watch(self, chronicle, "player.gold")
##   chronicle.set_fact("player.gold", 100)
class_name EventCollector
extends RefCounted


# ── Collected data ───────────────────────────────────────────────────────────

## Each entry: { key: String, value: Variant, old_value: Variant }
var events: Array[Dictionary] = []

## Raw any-arity emissions captured by connect_any(). Each entry is the array of
## emitted arguments (0-4 elements).
const _UNSET := &"__EC_UNSET__"
var signal_emissions: Array[Array] = []

## The watch ID returned by chronicle.watch() / watch_once().
## Exposed so tests that exercise unwatch() can reference it directly.
var watch_id: int = -1


# ── Internal ─────────────────────────────────────────────────────────────────

## Reference to the assertion facade (passed in from the GutTest).
## Stored so assert helpers can call assert_eq / assert_true / assert_null.
var _suite: Object  # GutTest — typed as Object to avoid hard dep
var _chronicle: Node

func _validate_suite() -> void:
	assert(_suite != null, "EventCollector: _suite is null. Use the factory methods.")
	assert(_suite.has_method("assert_eq"), "EventCollector: _suite must be a GutTest.")


# ── Callback ─────────────────────────────────────────────────────────────────

## Named method so it can accept an optional old_value. Watchers and the unified
## connect_signal forward here: 2-arg (fact_expired: key,value), 3-arg
## (fact_matched/fact_recorded: key,value,old_value), and 4-arg (fact_changed:
## key,value,old_value,erase_source — erase_source is dropped before this call).
func _on_event(key: String, value: Variant, old_value: Variant = null) -> void:
	events.append({
		key = key,
		value = value,
		old_value = old_value,
		time = _chronicle.get_game_time() if _chronicle else 0.0,
	})


## Public access to the callback for tests that need to pass it manually.
func callback() -> Callable:
	return _on_event


# ── Factory methods ──────────────────────────────────────────────────────────

## Creates a persistent watcher via chronicle.watch() or chronicle.watch_any().
static func watch(suite: Object, chronicle: Node, pattern: Variant) -> EventCollector:
	var collector := EventCollector.new()
	collector._suite = suite
	collector._chronicle = chronicle
	collector._validate_suite()
	if pattern is Array:
		var str_patterns: Array[String] = []
		for p: Variant in pattern:
			if p is String:
				str_patterns.append(p)
		collector.watch_id = chronicle.watch_any(str_patterns, collector._on_event)
	elif pattern is String:
		collector.watch_id = chronicle.watch(pattern, collector._on_event)
	else:
		collector.watch_id = -1
	return collector


## Creates a one-shot watcher via chronicle.watch(pattern, cb, true) or chronicle.watch_any(patterns, cb, true).
static func watch_once(suite: Object, chronicle: Node, pattern: Variant) -> EventCollector:
	var collector := EventCollector.new()
	collector._suite = suite
	collector._chronicle = chronicle
	collector._validate_suite()
	if pattern is Array:
		var str_patterns: Array[String] = []
		for p: Variant in pattern:
			if p is String:
				str_patterns.append(p)
		collector.watch_id = chronicle.watch_any(str_patterns, collector._on_event, true)
	elif pattern is String:
		collector.watch_id = chronicle.watch(pattern, collector._on_event, true)
	else:
		collector.watch_id = -1
	return collector


## Creates a collector without registering a watch.
## Useful when you need the raw callback for manual plumbing.
static func standalone(suite: Object) -> EventCollector:
	var collector := EventCollector.new()
	collector._suite = suite
	collector._validate_suite()
	return collector


## Connects the collector to a node signal of any arity (2-4 args:
## key, value[, old_value[, erase_source]]). Captures (key, value, old_value, time).
## Replaces the former two-factory signal-connection split.
static func connect_signal(suite: Object, source: Node, signal_name: String, chronicle: Node = null) -> EventCollector:
	var collector := EventCollector.new()
	collector._suite = suite
	collector._chronicle = chronicle
	collector._validate_suite()
	source.connect(signal_name, func(key: String, value: Variant = null, old_value: Variant = null, _e1: Variant = null) -> void:
		collector._on_event(key, value, old_value)
	)
	return collector


## Connects to a signal of ANY arity (0-4 args); records each emission's raw args.
static func connect_any(suite: Object, source: Node, signal_name: String) -> EventCollector:
	var collector := EventCollector.new()
	collector._suite = suite
	collector._validate_suite()
	source.connect(signal_name, func(a: Variant = _UNSET, b: Variant = _UNSET, c: Variant = _UNSET, d: Variant = _UNSET) -> void:
		var args: Array = []
		for v: Variant in [a, b, c, d]:
			if v is StringName and v == _UNSET:
				break
			args.append(v)
		collector.signal_emissions.append(args)
	)
	return collector


# ── Typed accessors ──────────────────────────────────────────────────────────

## Number of collected events.
func count() -> int:
	return events.size()


## All collected keys, in order.
func keys() -> Array:
	var result: Array = []
	for e: Dictionary in events:
		result.append(e.key)
	return result


## Clear all collected events (useful for multi-phase tests).
func clear() -> void:
	events.clear()


func first() -> Dictionary:
	return events[0] if not events.is_empty() else {}


func last() -> Dictionary:
	return events[-1] if not events.is_empty() else {}


# ── Assertion helpers ────────────────────────────────────────────────────────
#
# These return void — they call GUT assertions internally.
# When an assertion fails, the failure message includes a dump of all
# collected events so the developer never has to guess what actually fired.


## Assert the number of collected events equals [expected].
func assert_count(expected: int) -> void:
	_suite.assert_eq(events.size(), expected,
		"EventCollector expected %d event(s), got %d.\n%s" % [expected, events.size(), _dump()]
	)


func _check_field(index: int, field_name: String, actual: Variant, expected: Variant) -> void:
	if expected == null:
		_suite.assert_null(actual,
			"EventCollector[%d].%s: expected null, got %s.\n%s" % [index, field_name, str(actual), _dump()])
	else:
		_suite.assert_eq(actual, expected,
			"EventCollector[%d].%s: expected %s, got %s.\n%s" % [index, field_name, str(expected), str(actual), _dump()])


## Assert a specific event's key, value, and old_value.
## Pass [SKIP] for any field you don't want to check.
func assert_event(index: int, expected_key: Variant = SKIP, expected_value: Variant = SKIP, expected_old_value: Variant = SKIP) -> void:
	if index < 0 or index >= events.size():
		_suite.assert_true(false,
			"EventCollector.assert_event(%d) — index out of range (have %d events).\n%s" % [index, events.size(), _dump()])
		return
	var e: Dictionary = events[index]
	if not _is_skip(expected_key):
		_check_field(index, "key", e.key as String, expected_key as String)
	if not _is_skip(expected_value):
		_check_field(index, "value", e.value, expected_value)
	if not _is_skip(expected_old_value):
		_check_field(index, "old_value", e.old_value, expected_old_value)


## Assert the watch_id is a valid (non-negative) value.
func assert_valid_id() -> void:
	_suite.assert_gte(watch_id, 0,
		"EventCollector.watch_id expected >= 0, got %d." % watch_id
	)


## Assert the watch_id equals -1 (pattern was rejected).
func assert_invalid_id() -> void:
	_suite.assert_eq(watch_id, -1,
		"EventCollector.watch_id expected -1, got %d." % watch_id
	)


## Assert that collected keys (in order) match the given array.
func assert_keys(expected_keys: Array) -> void:
	var actual_keys: Array = keys()
	_suite.assert_eq(actual_keys.size(), expected_keys.size(),
		"EventCollector key count mismatch: expected %s, got %s.\n%s" % [str(expected_keys), str(actual_keys), _dump()]
	)
	for i: int in range(mini(actual_keys.size(), expected_keys.size())):
		_suite.assert_eq(actual_keys[i] as String, expected_keys[i] as String,
			"EventCollector keys[%d]: expected \"%s\", got \"%s\".\n%s" % [i, expected_keys[i], actual_keys[i], _dump()]
		)


## Assert a specific event's captured timestamp.
func assert_event_time(index: int, expected_time: float) -> void:
	if index < 0 or index >= events.size():
		_suite.assert_true(false,
			"EventCollector.assert_event_time(%d) — index out of range (have %d events).\n%s" % [index, events.size(), _dump()]
		)
		return
	_suite.assert_eq(events[index].get("time", -1.0), expected_time,
		"EventCollector[%d].time: expected %.4f, got %s.\n%s" % [index, expected_time, str(events[index].get("time")), _dump()]
	)


func assert_values(expected_values: Array) -> void:
	_suite.assert_eq(events.size(), expected_values.size(),
		"EventCollector value count mismatch: expected %d, got %d.\n%s" \
		% [expected_values.size(), events.size(), _dump()])
	for i: int in range(mini(events.size(), expected_values.size())):
		_check_field(i, "value", events[i].value, expected_values[i])


func assert_value_transition(index: int, expected_old: Variant, expected_new: Variant) -> void:
	if index < 0 or index >= events.size():
		_suite.assert_true(false,
			"EventCollector.assert_value_transition(%d) — out of range.\n%s" % [index, _dump()])
		return
	_check_field(index, "value", events[index].value, expected_new)
	_check_field(index, "old_value", events[index].old_value, expected_old)


## Assert the number of any-arity signal emissions (from connect_any).
func assert_emission_count(expected: int) -> void:
	_suite.assert_eq(signal_emissions.size(), expected,
		"expected %d signal emission(s), got %d: %s" % [expected, signal_emissions.size(), str(signal_emissions)])


## Assert a specific any-arity emission's raw argument array (from connect_any).
func assert_emission_args(index: int, expected_args: Array) -> void:
	if index < 0 or index >= signal_emissions.size():
		_suite.assert_true(false, "emission index %d out of range (have %d)" % [index, signal_emissions.size()])
		return
	_suite.assert_eq(signal_emissions[index], expected_args,
		"emission[%d] args: expected %s, got %s" % [index, str(expected_args), str(signal_emissions[index])])


func assert_no_key(key: String) -> void:
	for i: int in range(events.size()):
		if events[i].key == key:
			_suite.assert_true(false,
				"EventCollector.assert_no_key(\"%s\") — found at index %d.\n%s" % [key, i, _dump()])
			return
	_suite.pass_test(
		"EventCollector.assert_no_key(\"%s\") — key absent (correct)." % key)


# ── Skip sentinel ────────────────────────────────────────────────────────────

## Sentinel value for skipping a field in assert_event().
## Uses a unique StringName that will never collide with real test data.
const SKIP := &"__EventCollector_SKIP__"


static func _is_skip(value: Variant) -> bool:
	return value is StringName and value == SKIP


# ── Debug dump ───────────────────────────────────────────────────────────────

func _dump() -> String:
	if events.is_empty():
		return "  (no events collected)"
	var lines: Array = ["  Collected events:"]
	for i: int in range(events.size()):
		var e: Dictionary = events[i]
		lines.append("    [%d] key=%s  value=%s  old_value=%s  time=%s" % [
			i, str(e.key), str(e.value), str(e.old_value), str(e.get("time", "?"))
		])
	return "\n".join(lines)
