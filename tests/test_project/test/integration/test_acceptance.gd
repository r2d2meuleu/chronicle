## Acceptance test suite — each function maps to a test case from testcase.md.
## TC-01 to TC-41 (TC-42 to TC-45 covered by test_debug_overlay.gd).
extends ChronicleTestSuite


# ── Chamber 1: The Basics (TC-01 to TC-12) ──


# audit: TC-01 — set_fact boolean true
func test_set_fact_bool_true() -> void:
	_chronicle.set_fact("test.bool", true)
	assert_fact("test.bool", true)


# audit: TC-02 — set_fact boolean false (toggle)
func test_set_fact_bool_toggle() -> void:
	_chronicle.set_fact("test.bool", true)
	_chronicle.set_fact("test.bool", false)
	assert_fact("test.bool", false)


# audit: TC-03 — set_fact integer
func test_set_fact_integer() -> void:
	_chronicle.set_fact("test.int", 42)
	assert_fact("test.int", 42)
	assert_eq(typeof(_chronicle.get_fact("test.int")), TYPE_INT)


# audit: TC-04 — set_fact string
func test_set_fact_string() -> void:
	_chronicle.set_fact("test.string", "hello")
	assert_fact("test.string", "hello")


# audit: TC-05 — mark
func test_mark() -> void:
	_chronicle.set_fact("test.flag")
	assert_marked("test.flag")


# audit: TC-06 — erase after mark
func test_erase_after_mark() -> void:
	_chronicle.set_fact("test.flag")
	assert_marked("test.flag")
	_chronicle.erase_fact("test.flag")
	assert_not_marked("test.flag")


# audit: TC-07 — increment
func test_increment() -> void:
	_chronicle.increment_fact("test.counter")
	assert_fact("test.counter", 1)
	_chronicle.increment_fact("test.counter")
	assert_fact("test.counter", 2)


# audit: TC-08 — decrement
func test_decrement() -> void:
	_chronicle.increment_fact("test.counter")
	_chronicle.increment_fact("test.counter")
	_chronicle.increment_fact("test.counter", -1.0)
	assert_fact("test.counter", 1)


# audit: TC-09 — erase_fact
func test_erase_fact() -> void:
	_chronicle.set_fact("test.eraseme", true)
	assert_has_fact("test.eraseme")
	_chronicle.erase_fact("test.eraseme")
	assert_no_fact("test.eraseme")


# audit: TC-10 — dotless key (global normalization)
func test_dotless_key() -> void:
	_chronicle.set_fact("global_flag", true)
	assert_fact("global_flag", true)
	var found_keys: Array[String] = _chronicle.get_fact_keys("*")
	for k: String in found_keys:
		assert_false(k.begins_with("_global."), "find result not prefixed: " + k)


# audit: TC-11 — key() sanitizer
func test_key_sanitizer() -> void:
	var sanitized: String = Chronicle.build_key(["player", "Dr.Evil"] as Array[String])
	assert_eq(sanitized, "player.dr_evil")
	_chronicle.set_fact(sanitized, true)
	assert_has_fact("player.dr_evil")


# audit: TC-12 — type preservation across set/get
func test_type_preservation() -> void:
	_chronicle.set_fact("type.int", 42)
	assert_eq(typeof(_chronicle.get_fact("type.int")), TYPE_INT)
	_chronicle.set_fact("type.float", 3.14)
	assert_eq(typeof(_chronicle.get_fact("type.float")), TYPE_FLOAT)
	_chronicle.set_fact("type.bool", true)
	assert_eq(typeof(_chronicle.get_fact("type.bool")), TYPE_BOOL)
	_chronicle.set_fact("type.string", "hello")
	assert_eq(typeof(_chronicle.get_fact("type.string")), TYPE_STRING)


# ── Chamber 2: The Gates (TC-13 to TC-18) ──


# audit: TC-13 — HIDE_WHEN_FALSE
func test_gate_hide_when_false() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({condition = "test.bool"})
	parent.add_child(gate)
	assert_gate_closed(parent)
	_chronicle.set_fact("test.bool", true)
	assert_gate_open(parent)
	_chronicle.set_fact("test.bool", false)
	assert_gate_closed(parent)


# audit: TC-14 — SHOW_WHEN_FALSE
func test_gate_show_when_false() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({
		condition = "test.flag",
		gate_mode = CompanionFactory.GateMode.SHOW_WHEN_FALSE,
	})
	parent.add_child(gate)
	assert_gate_open(parent)
	_chronicle.set_fact("test.flag")
	assert_gate_closed(parent)


# audit: TC-15 — QUEUE_FREE_WHEN_TRUE
func test_gate_queue_free_when_true() -> void:
	_chronicle.set_fact("test.int", 42)
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({
		condition = "test.int == 42",
		gate_mode = CompanionFactory.GateMode.QUEUE_FREE_WHEN_TRUE,
	})
	parent.add_child(gate)
	assert_true(parent.is_queued_for_deletion())


# audit: TC-16 — SIGNAL_ONLY
func test_gate_signal_only() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({
		condition = "test.bool",
		gate_mode = CompanionFactory.GateMode.SIGNAL_ONLY,
	})
	parent.add_child(gate)
	var opened := collect_any_signal(gate, "gate_opened")
	var closed := collect_any_signal(gate, "gate_closed")
	assert_true(parent.visible)
	_chronicle.set_fact("test.bool", true)
	opened.assert_emission_count(1)
	assert_true(parent.visible)
	_chronicle.set_fact("test.bool", false)
	closed.assert_emission_count(1)
	assert_true(parent.visible)


# audit: TC-17 — compound expression (AND with comparison)
func test_gate_compound_expression() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({
		condition = "test.counter >= 3 AND test.bool",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	parent.add_child(gate)
	assert_gate_closed(parent)
	_chronicle.set_fact("test.bool", true)
	assert_gate_closed(parent)
	_chronicle.set_fact("test.counter", 5)
	assert_gate_open(parent)
	_chronicle.set_fact("test.counter", 1)
	assert_gate_closed(parent)


# audit: TC-18 — default_when_missing
func test_gate_default_when_missing() -> void:
	var parent := add_node_2d()
	var gate := CompanionFactory.make_gate({
		condition = "nonexistent.key",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
		default_when_missing = true,
	})
	parent.add_child(gate)
	assert_gate_open(parent)
	_chronicle.set_fact("nonexistent.key", false)
	assert_gate_closed(parent)


# ── Chamber 3: Recorders & Reactors (TC-19 to TC-25) ──


# audit: TC-19 — Recorder ONCE
func test_recorder_once() -> void:
	var bell := add_signaled_node("rung")
	var rec := CompanionFactory.make_recorder({
		trigger_signal = "rung",
		fact_key = "recorder.bell_once",
		record_mode = CompanionFactory.RecordMode.ONCE,
	})
	bell.add_child(rec)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_once", true)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_once", true)


# audit: TC-20 — Recorder EVERY_TIME
func test_recorder_every_time() -> void:
	var bell := add_signaled_node("rung")
	var rec := CompanionFactory.make_recorder({
		trigger_signal = "rung",
		fact_key = "recorder.bell_every",
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	bell.add_child(rec)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_every", true)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_every", true)


# audit: TC-21 — Recorder INCREMENT
func test_recorder_increment() -> void:
	var bell := add_signaled_node("rung")
	var rec := CompanionFactory.make_recorder({
		trigger_signal = "rung",
		fact_key = "recorder.bell_count",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
	})
	bell.add_child(rec)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_count", 1)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_count", 2)
	bell.emit_signal("rung")
	assert_fact("recorder.bell_count", 3)


# audit: TC-22 — Reactor ANY
func test_reactor_any() -> void:
	var parent := add_node()
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "reactor.*",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	parent.add_child(reactor)
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("reactor.test", 1)
	events.assert_count(1)
	_chronicle.set_fact("reactor.test", 2)
	events.assert_count(2)
	_chronicle.set_fact("reactor.test2", 1)
	events.assert_count(3)


# audit: TC-23 — Reactor CREATION
func test_reactor_creation() -> void:
	var parent := add_node()
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "reactor.*",
		react_to = CompanionFactory.ReactTo.CREATION,
	})
	parent.add_child(reactor)
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("reactor.test", 1)
	events.assert_count(1)
	_chronicle.set_fact("reactor.test", 2)
	events.assert_count(1)
	_chronicle.set_fact("reactor.test2", 1)
	events.assert_count(2)


# audit: TC-24 — Reactor CHANGE
func test_reactor_change() -> void:
	var parent := add_node()
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "reactor.*",
		react_to = CompanionFactory.ReactTo.CHANGE,
	})
	parent.add_child(reactor)
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("reactor.test", 1)
	events.assert_count(0)
	_chronicle.set_fact("reactor.test", 2)
	events.assert_count(1)


# audit: TC-25 — Reactor ONE_SHOT
func test_reactor_one_shot() -> void:
	var parent := add_node()
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "reactor.*",
		react_to = CompanionFactory.ReactTo.ANY,
		one_shot = true,
	})
	parent.add_child(reactor)
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("reactor.test", 1)
	events.assert_count(1)
	_chronicle.set_fact("reactor.test", 2)
	events.assert_count(1)
	_chronicle.set_fact("reactor.test2", 1)
	events.assert_count(1)


# ── Chamber 4: Queries & Watchers (TC-26 to TC-34) ──


func _setup_query_facts() -> void:
	_chronicle.set_fact("test.a", 1)
	_chronicle.set_fact("test.b", 2)
	_chronicle.set_fact("test.c", 3)
	_chronicle.set_fact("other.x", 99)


# audit: TC-26 — find
func test_find() -> void:
	_setup_query_facts()
	var found: Array[String] = _chronicle.get_fact_keys("test.*")
	assert_eq(found.size(), 3)
	assert_has(found, "test.a")
	assert_has(found, "test.b")
	assert_has(found, "test.c")


# audit: TC-27 — count
func test_count() -> void:
	_setup_query_facts()
	assert_fact_count("test.*", 3)
	assert_fact_count("*", 4)


# audit: TC-28 — first_change
func test_first_change() -> void:
	_setup_query_facts()
	var f: Variant = _chronicle.get_first_change("test.*")
	assert_not_null(f)
	assert_eq(f.key, "test.a")


# audit: TC-29 — last_change
func test_last_change() -> void:
	_setup_query_facts()
	var l: Variant = _chronicle.get_last_change("test.*")
	assert_not_null(l)
	assert_eq(l.key, "test.c")


# audit: TC-30 — fact_history
func test_fact_history() -> void:
	_chronicle.set_fact("test.counter", 10)
	_chronicle.set_fact("test.counter", 20)
	_chronicle.set_fact("test.counter", 30)
	assert_history("test.counter", [10, 20, 30])


# audit: TC-31 — watch
func test_watch() -> void:
	_setup_query_facts()
	var watch_ev := watch_events("test.*")
	_chronicle.set_fact("test.d", 4)
	watch_ev.assert_count(1)
	watch_ev.assert_event(0, "test.d")


# audit: TC-32 — unwatch
func test_unwatch() -> void:
	var watch_ev := watch_events("test.*")
	_chronicle.set_fact("test.a", 1)
	watch_ev.assert_count(1)
	_chronicle.unwatch(watch_ev.watch_id)
	_chronicle.set_fact("test.b", 2)
	watch_ev.assert_count(1)


# audit: TC-33 — game_time
func test_game_time() -> void:
	set_time(10.0)
	assert_game_time(10.0)


# audit: TC-34 — changes_since
func test_changes_since() -> void:
	set_time(20.0)
	_chronicle.set_fact("test.timed", true)
	var since_10: Array[Dictionary] = _chronicle.get_changes_since(10.0)
	assert_eq(since_10.size(), 1, "changes_since(10.0) includes the single t=20 entry")
	var since_25: Array[Dictionary] = _chronicle.get_changes_since(25.0)
	assert_eq(since_25.size(), 0, "changes_since(25.0) returns empty")


# ── Chamber 5: Save/Load (TC-35 to TC-41) ──


# audit: TC-35 — serialize + save_to_file
func test_serialize_save() -> void:
	_chronicle.set_fact("test.bool", true)
	_chronicle.set_fact("test.int", 42)
	var data: Dictionary = _chronicle.serialize()
	assert_has(data, "version")
	assert_has(data, "facts")
	assert_has(data, "timeline")
	var save_path: String = "user://chronicle_acceptance_test.json"
	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)


# audit: TC-36 — load_from_file + deserialize
func test_load_deserialize() -> void:
	_chronicle.set_fact("test.bool", true)
	_chronicle.set_fact("test.int", 42)
	_chronicle.set_fact("test.string", "hello")
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_acceptance_tc36.json"
	save_temp(save_path, data)

	_chronicle.clear()
	assert_no_fact("test.bool")
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	var ok: bool = _chronicle.deserialize(loaded)
	assert_true(ok)
	assert_fact("test.bool", true)
	assert_fact("test.int", 42)
	assert_fact("test.string", "hello")


# audit: TC-37 — clear
func test_clear() -> void:
	_chronicle.set_fact("test.a", 1)
	_chronicle.set_fact("test.b", 2)
	_chronicle.clear()
	assert_fact_count("*", 0)


# audit: TC-38 — transient fact
func test_transient_fact() -> void:
	_chronicle.set_fact("temp.volatile", 99, true, 0.0)
	assert_fact("temp.volatile", 99)


# audit: TC-39 — transient excluded from serialize
func test_transient_excluded_from_serialize() -> void:
	_chronicle.set_fact("test.int", 42)
	_chronicle.set_fact("temp.volatile", 99, true, 0.0)
	var data: Dictionary = _chronicle.serialize()
	var transient_found: bool = false
	for k: String in data.facts:
		if "volatile" in k:
			transient_found = true
	assert_false(transient_found)


# audit: TC-40 — roundtrip test (all types)
func test_roundtrip_all_types() -> void:
	_chronicle.set_fact("rt.bool", true)
	_chronicle.set_fact("rt.int", 7)
	_chronicle.set_fact("rt.float", 3.14)
	_chronicle.set_fact("rt.string", "test")
	_chronicle.set_fact("rt.array", [1, 2, 3])
	_chronicle.set_fact("rt.dict", {"a": 1})
	roundtrip()
	assert_fact("rt.bool", true)
	assert_fact("rt.int", 7)
	assert_fact("rt.float", 3.14)
	assert_fact("rt.string", "test")
	assert_fact("rt.array", [1, 2, 3])
	var d: Variant = _chronicle.get_fact("rt.dict")
	assert_true(d is Dictionary, "rt.dict survives roundtrip as Dictionary")
	assert_eq(d.get("a"), 1)


# audit: TC-41 — int/float type preservation after JSON save/load
func test_int_float_type_preservation() -> void:
	_chronicle.set_fact("type.check", 42)
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_acceptance_tc41.json"
	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)
	var loaded: Variant = read_file(save_path)
	_chronicle.clear()
	_chronicle.deserialize(loaded)
	assert_eq(typeof(_chronicle.get_fact("type.check")), TYPE_INT)
