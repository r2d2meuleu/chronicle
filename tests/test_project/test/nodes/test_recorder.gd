extends ChronicleTestSuite


# Recorder connects to parent signal and records fact on emit (EVERY_TIME mode)
func test_every_time_records_on_signal() -> void:
	var parent := add_recorder({
		trigger_signal = "died",
		fact_key = "boss.defeated",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})

	parent.emit_signal("died")
	assert_fact("boss.defeated", true)

	parent.emit_signal("died")
	assert_fact("boss.defeated", true)


# ONCE mode only records first trigger, ignores repeats
func test_once_mode_only_records_first() -> void:
	var parent := add_recorder({
		trigger_signal = "died",
		fact_key = "boss.first_kill",
		value = "yes",
		record_mode = CompanionFactory.RecordMode.ONCE,
	})
	var recorder: Node = parent.get_child(0)

	parent.emit_signal("died")
	assert_fact("boss.first_kill", "yes")

	recorder.value = "no"
	parent.emit_signal("died")
	assert_fact("boss.first_kill", "yes")


# INCREMENT mode increments the value each trigger
func test_increment_mode() -> void:
	var parent := add_recorder({
		trigger_signal = "scored",
		fact_key = "player.score",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 10.0,
	})

	parent.emit_signal("scored")
	assert_fact("player.score", 10)

	parent.emit_signal("scored")
	assert_fact("player.score", 20)

	parent.emit_signal("scored")
	assert_fact("player.score", 30)


# Missing signal on parent -> push_error, no crash, recorder is inert
func test_missing_signal_no_crash() -> void:
	var parent := add_node()
	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "nonexistent_signal",
		fact_key = "should.not.exist",
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	parent.add_child(recorder)

	assert_no_fact("should.not.exist")


# Empty fact_key -> configuration warning present
func test_empty_fact_key_warning() -> void:
	var recorder: Node = autofree(CompanionFactory.make_recorder({
		trigger_signal = "some_signal",
		fact_key = "",
	}))
	assert_has_warning(recorder, "fact_key")


# Empty trigger_signal -> configuration warning present
func test_empty_trigger_signal_warning() -> void:
	var recorder: Node = autofree(CompanionFactory.make_recorder({
		trigger_signal = "",
		fact_key = "some.key",
	}))
	assert_has_warning(recorder, "trigger_signal")


# Recorder emits recorded signal on trigger
func test_recorded_signal_emitted() -> void:
	var parent := add_recorder({
		trigger_signal = "died",
		fact_key = "boss.defeated",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	var recorder: Node = parent.get_child(0)

	var events := collect_signal(recorder, "fact_recorded")

	parent.emit_signal("died")
	events.assert_count(1)
	events.assert_event(0, "boss.defeated", true)


# Cleanup: after removing recorder from tree, parent signal is disconnected
func test_cleanup_disconnects_signal() -> void:
	var parent := add_signaled_node("died")
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "died",
		fact_key = "boss.defeated",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	}))
	parent.add_child(recorder)

	# Verify recorder is active (behavioral)
	parent.emit_signal("died")
	assert_fact("boss.defeated", true)

	# Remove recorder from tree — _exit_tree should disconnect
	parent.remove_child(recorder)

	# Verify signal is disconnected via public API
	var connections: Array = parent.get_signal_connection_list("died")
	var has_recorder_connection := false
	for conn: Dictionary in connections:
		if conn.callable.get_object() == recorder:
			has_recorder_connection = true
	assert_false(has_recorder_connection, "recorder disconnected after removal")

	# Emit signal on parent — should not crash or record
	_chronicle.erase_fact("boss.defeated")
	parent.emit_signal("died")
	assert_no_fact("boss.defeated")


# EVERY_TIME records correctly when signal carries one argument
func test_every_time_with_one_arg_signal() -> void:
	var parent := add_signaled_node("hit", [{"name": "damage", "type": TYPE_INT}])
	var _recorder := CompanionFactory.make_recorder({
		trigger_signal = "hit",
		fact_key = "player.was_hit",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	parent.add_child(_recorder)

	parent.emit_signal("hit", 25)
	assert_fact("player.was_hit", true)


# ONCE mode works with one-arg signal
func test_once_with_one_arg_signal() -> void:
	var parent := add_signaled_node("item_collected", [{"name": "item_id", "type": TYPE_STRING}])
	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "item_collected",
		fact_key = "first_item",
		value = "collected",
		record_mode = CompanionFactory.RecordMode.ONCE,
	})
	parent.add_child(recorder)

	parent.emit_signal("item_collected", "sword")
	assert_fact("first_item", "collected")

	recorder.value = "should_not_appear"
	parent.emit_signal("item_collected", "shield")
	assert_fact("first_item", "collected")


# INCREMENT mode works with one-arg signal
func test_increment_with_one_arg_signal() -> void:
	var parent := add_signaled_node("enemy_killed", [{"name": "enemy", "type": TYPE_OBJECT}])
	var _recorder := CompanionFactory.make_recorder({
		trigger_signal = "enemy_killed",
		fact_key = "kill_count",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	})
	parent.add_child(_recorder)

	var dummy_node: Node = autofree(Node.new())
	parent.emit_signal("enemy_killed", dummy_node)
	assert_fact("kill_count", 1)

	parent.emit_signal("enemy_killed", dummy_node)
	assert_fact("kill_count", 2)


# EVERY_TIME records correctly when signal carries two arguments
func test_every_time_with_two_arg_signal() -> void:
	var parent := add_signaled_node("damage_dealt", [
		{"name": "amount", "type": TYPE_INT},
		{"name": "source", "type": TYPE_STRING},
	])
	var _recorder := CompanionFactory.make_recorder({
		trigger_signal = "damage_dealt",
		fact_key = "took_damage",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	parent.add_child(_recorder)

	parent.emit_signal("damage_dealt", 50, "fireball")
	assert_fact("took_damage", true)


# INCREMENT mode works with two-arg signal
func test_increment_with_two_arg_signal() -> void:
	var parent := add_signaled_node("scored_points", [
		{"name": "points", "type": TYPE_INT},
		{"name": "multiplier", "type": TYPE_FLOAT},
	])
	var _recorder := CompanionFactory.make_recorder({
		trigger_signal = "scored_points",
		fact_key = "total_score",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 5.0,
	})
	parent.add_child(_recorder)

	parent.emit_signal("scored_points", 100, 1.5)
	assert_fact("total_score", 5)

	parent.emit_signal("scored_points", 200, 2.0)
	assert_fact("total_score", 10)


# Recorder handles signal with five arguments without error
func test_every_time_with_five_arg_signal() -> void:
	var parent := add_signaled_node("complex_event", [
		{"name": "id", "type": TYPE_INT},
		{"name": "name", "type": TYPE_STRING},
		{"name": "position", "type": TYPE_VECTOR2},
		{"name": "active", "type": TYPE_BOOL},
		{"name": "metadata", "type": TYPE_DICTIONARY},
	])
	var _recorder := CompanionFactory.make_recorder({
		trigger_signal = "complex_event",
		fact_key = "complex.happened",
		value = "yes",
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	parent.add_child(_recorder)

	parent.emit_signal("complex_event", 1, "boss", Vector2(10, 20), true, {"level": 5})
	assert_fact("complex.happened", "yes")


# Recorder emits recorded signal even when trigger signal has arguments
func test_recorded_signal_emitted_with_args() -> void:
	var parent := add_signaled_node("hit", [{"name": "damage", "type": TYPE_INT}])
	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "hit",
		fact_key = "player.hit",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	parent.add_child(recorder)

	var events := collect_signal(recorder, "fact_recorded")

	parent.emit_signal("hit", 42)
	events.assert_count(1)
	events.assert_event(0, "player.hit", true)


# Cleanup works correctly for signals with arguments
func test_cleanup_with_arg_signal() -> void:
	var parent := add_signaled_node("body_entered", [{"name": "body", "type": TYPE_OBJECT}])
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "body_entered",
		fact_key = "zone.entered",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	}))
	parent.add_child(recorder)

	var dummy: Node = autofree(Node.new())

	parent.emit_signal("body_entered", dummy)
	assert_fact("zone.entered", true)

	parent.remove_child(recorder)
	_chronicle.erase_fact("zone.entered")

	parent.emit_signal("body_entered", dummy)
	assert_no_fact("zone.entered")


# Signal argument that is null does not crash the recorder
func test_null_arg_does_not_crash() -> void:
	var parent := add_signaled_node("target_lost", [{"name": "target", "type": TYPE_OBJECT}])
	var _recorder := CompanionFactory.make_recorder({
		trigger_signal = "target_lost",
		fact_key = "target.lost",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	parent.add_child(_recorder)

	parent.emit_signal("target_lost", null)
	assert_fact("target.lost", true)


# Multiple recorders on the same parent with different arg-count signals
func test_multiple_recorders_different_signals() -> void:
	var parent := add_signaled_node("died")
	parent.add_user_signal("hit", [{"name": "damage", "type": TYPE_INT}])

	var recorder_died := CompanionFactory.make_recorder({
		trigger_signal = "died",
		fact_key = "boss.dead",
		value = true,
		record_mode = CompanionFactory.RecordMode.ONCE,
	})
	var recorder_hit := CompanionFactory.make_recorder({
		trigger_signal = "hit",
		fact_key = "hit.count",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	})
	parent.add_child(recorder_died)
	parent.add_child(recorder_hit)

	parent.emit_signal("hit", 10)
	assert_no_fact("boss.dead")
	assert_fact("hit.count", 1)

	parent.emit_signal("hit", 20)
	assert_fact("hit.count", 2)

	parent.emit_signal("died")
	assert_fact("boss.dead", true)
	assert_fact("hit.count", 2)


# Re-adding recorder to tree reconnects to signal (with args)
func test_readd_recorder_reconnects_with_arg_signal() -> void:
	var parent := add_signaled_node("picked_up", [{"name": "item", "type": TYPE_STRING}])
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "picked_up",
		fact_key = "pickup.count",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	}))
	parent.add_child(recorder)

	parent.emit_signal("picked_up", "coin")
	assert_fact("pickup.count", 1)

	parent.remove_child(recorder)
	parent.emit_signal("picked_up", "gem")
	assert_fact("pickup.count", 1)

	parent.add_child(recorder)
	parent.emit_signal("picked_up", "key")
	assert_fact("pickup.count", 2)


# ONCE-mode recorder stays inert after re-add to tree
func test_once_mode_readd_resets_has_fired() -> void:
	var parent := add_signaled_node("died")
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "died",
		fact_key = "boss.defeated",
		value = true,
		record_mode = CompanionFactory.RecordMode.ONCE,
	}))
	parent.add_child(recorder)

	parent.emit_signal("died")
	assert_fact("boss.defeated", true)

	parent.remove_child(recorder)
	_chronicle.erase_fact("boss.defeated")
	parent.add_child(recorder)

	parent.emit_signal("died")
	assert_no_fact("boss.defeated")


# _custom_trigger_fn bypasses record_mode logic and calls user-supplied callable
func test_custom_trigger_fn_bypasses_record_mode() -> void:
	var parent := add_recorder({
		trigger_signal = "test_signal",
		fact_key = "custom",
	})
	var recorder: Node = parent.get_child(0)
	recorder.set_custom_trigger(func(chronicle: Node, key: String) -> void:
		chronicle.set_fact(key, "custom_value"))
	await get_tree().process_frame
	parent.emit_signal("test_signal")
	assert_fact("custom", "custom_value")


# ── Merged from test/audit/test_r16_a10_nodes.gd — Recorder bug regression tests ──

# Recorder is in chronicle_recorders group (consistency with Gate and Reactor)
func test_recorder_in_chronicle_recorders_group() -> void:
	var parent := add_recorder({
		trigger_signal = "test_signal",
		fact_key = "test.key",
	})
	var recorder: Node = parent.get_child(0)
	# Bug was fixed in commit 825bc56 (R16 org refactor): recorder.gd:53 now
	# calls add_to_group("chronicle_recorders") for consistency with Gate
	# ("chronicle_gates") and Reactor ("chronicle_reactors").
	assert_true(recorder.is_in_group("chronicle_recorders"),
		"Recorder should be in chronicle_recorders group (fixed in R16 org refactor)")


# ONCE mode survives state_reset — "once per session, not per state"
func test_recorder_once_mode_survives_state_reset() -> void:
	var parent := add_recorder({
		trigger_signal = "action",
		fact_key = "once.test",
		record_mode = CompanionFactory.RecordMode.ONCE,
	})

	parent.emit_signal("action")
	assert_fact("once.test", true)

	# Clear state (triggers state_reset)
	_chronicle.clear()
	assert_no_fact("once.test")

	# ONCE recorder should NOT fire again after state_reset
	parent.emit_signal("action")
	assert_no_fact("once.test")


# ── Merged from test/audit/test_r17_a10_nodes.gd — Recorder audit tests ──

# Recorder is in chronicle_recorders group (corrected assertion)
func test_recorder_is_in_chronicle_recorders_group() -> void:
	var parent := add_recorder({
		trigger_signal = "action",
		fact_key = "test.key",
	})
	var recorder: Node = parent.get_child(0)
	assert_true(recorder.is_in_group("chronicle_recorders"),
		"Recorder should be in chronicle_recorders group (gate=chronicle_gates, reactor=chronicle_reactors)")


# All three companion types are in their respective groups
func test_all_three_companions_in_groups() -> void:
	var target := add_node_2d()
	var gate: Node = CompanionFactory.make_gate({condition = "flag"})
	target.add_child(gate)
	assert_true(gate.is_in_group("chronicle_gates"),
		"Gate should be in chronicle_gates group")

	var reactor := add_reactor({watch_pattern = "flag"})
	assert_true(reactor.is_in_group("chronicle_reactors"),
		"Reactor should be in chronicle_reactors group")

	var parent := add_recorder({trigger_signal = "action", fact_key = "k"})
	var recorder: Node = parent.get_child(0)
	assert_true(recorder.is_in_group("chronicle_recorders"),
		"Recorder should be in chronicle_recorders group")


# Recorder ONCE mode preserved across remove/re-add to scene tree
func test_recorder_once_preserved_on_readd() -> void:
	var parent := add_signaled_node("action")
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "action",
		fact_key = "once.key",
		record_mode = CompanionFactory.RecordMode.ONCE,
	}))
	parent.add_child(recorder)

	# Fire once
	parent.emit_signal("action")
	assert_fact("once.key", true)

	# Remove and re-add
	parent.remove_child(recorder)
	_chronicle.erase_fact("once.key")
	parent.add_child(recorder)

	# Should NOT fire again (ONCE means once per session)
	parent.emit_signal("action")
	assert_no_fact("once.key")


# ── Merged from test/audit/test_r23_bug_1.gd — Recorder API compatibility tests ──

# recorder.gd can be loaded and instantiated
func test_recorder_script_can_be_instantiated() -> void:
	var script: GDScript = load("res://addons/chronicle/nodes/recorder.gd") as GDScript
	assert_not_null(script, "recorder.gd should load as a GDScript")
	assert_true(script.can_instantiate(), "recorder.gd should compile and be instantiable")


# ── R14 bug regression ───────────────────────


# INCREMENT-mode recorder against a non-numeric fact does not crash and leaves it unchanged
func test_increment_mode_non_numeric_fact_no_crash() -> void:
	_chronicle.set_fact("counter", "not_a_number")
	var parent := add_recorder({
		trigger_signal = "scored",
		fact_key = "counter",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	})

	# increment_fact returns null for a non-numeric fact; the recorder guards on
	# that null and returns early — no script error, the fact stays untouched.
	parent.emit_signal("scored")
	assert_fact("counter", "not_a_number")


# ALWAYS re-records on EVERY trigger: changing recorder.value between triggers
# makes the second write observably distinct, distinguishing ALWAYS from ONCE
# (which would latch the first value and never re-fire).
func test_always_re_records_distinct_value_each_trigger() -> void:
	var parent := add_recorder({
		trigger_signal = "died",
		fact_key = "boss.last_drop",
		value = "first",
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	var recorder: Node = parent.get_child(0)
	var events := collect_signal(recorder, "fact_recorded")

	parent.emit_signal("died")
	assert_fact("boss.last_drop", "first")

	# Change the value, then trigger again — ALWAYS must overwrite with the new
	# value (ONCE would keep "first" and not re-fire).
	recorder.value = "second"
	parent.emit_signal("died")
	assert_fact("boss.last_drop", "second")

	# Both triggers recorded.
	events.assert_count(2)
	events.assert_event(1, "boss.last_drop", "second")


# has_fired() reflects ONCE-mode state: false before the first trigger, true after
func test_has_fired_reflects_once_mode_state() -> void:
	var parent := add_signaled_node("triggered")
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "triggered",
		fact_key = "rec.flag",
		value = true,
		record_mode = CompanionFactory.RecordMode.ONCE,
	}))
	parent.add_child(recorder)

	assert_false(recorder.has_fired(), "has_fired() false before the first trigger")
	parent.emit_signal("triggered")
	assert_fact("rec.flag", true)
	assert_true(recorder.has_fired(), "has_fired() true after a ONCE-mode trigger")


# reset() re-arms a ONCE-mode recorder so it records again
func test_reset_rearms_once_mode_recorder() -> void:
	var parent := add_signaled_node("triggered")
	var recorder: Node = autoqfree(CompanionFactory.make_recorder({
		trigger_signal = "triggered",
		fact_key = "rec.count",
		value = 1,
		record_mode = CompanionFactory.RecordMode.ONCE,
	}))
	parent.add_child(recorder)

	parent.emit_signal("triggered")
	assert_fact("rec.count", 1)
	assert_true(recorder.has_fired())

	# Erase the recorded fact and reset — the recorder re-arms and records again.
	_chronicle.erase_fact("rec.count")
	recorder.reset()
	assert_false(recorder.has_fired(), "reset() clears has_fired")
	parent.emit_signal("triggered")
	assert_fact("rec.count", 1)
