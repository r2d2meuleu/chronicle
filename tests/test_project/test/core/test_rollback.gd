extends ChronicleTestSuite


# ── Basic rollback_to ──


# Single key rollback restores previous value
func test_rollback_single_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	set_time(2.0)
	_chronicle.set_fact("player.gold", 200)

	var ok = _chronicle.rollback_to(1.5)

	assert_rollback_ok(ok)
	assert_fact("player.gold", 100)


# Multi-key rollback restores all affected keys
func test_rollback_multi_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	set_time(2.0)
	_chronicle.set_fact("player.gold", 200)
	set_time(3.0)
	_chronicle.set_fact("player.hp", 75)
	_chronicle.set_fact("quest.done", true)

	var ok = _chronicle.rollback_to(1.5)

	assert_rollback_ok(ok)
	assert_fact("player.gold", 100)
	assert_fact("player.hp", 50)
	assert_no_fact("quest.done")


# Rollback restores erased key
func test_rollback_restores_erased_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("item.sword", true)
	set_time(2.0)
	_chronicle.erase_fact("item.sword")

	assert_no_fact("item.sword")

	var ok = _chronicle.rollback_to(1.5)

	assert_rollback_ok(ok)
	assert_fact("item.sword", true)


# Rollback erases key that didn't exist before target_time
func test_rollback_erases_new_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("anchor", 1)
	set_time(2.0)
	_chronicle.set_fact("quest.started", true)

	var ok = _chronicle.rollback_to(1.5)

	assert_rollback_ok(ok)
	assert_no_fact("quest.started")
	assert_fact("anchor", 1)


# Game clock resets to target_time
func test_rollback_resets_game_clock() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	set_time(10.0)
	_chronicle.set_fact("b", 2)

	_chronicle.rollback_to(7.0)

	assert_game_time(7.0)


# Tick continues forward after rollback (Lamport clock)
func test_tick_continues_forward() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("b", 2)

	_chronicle.rollback_to(0.0)

	# Timeline tick always increases — after rollback, new writes get appended.
	# Verify via get_fact_history on the new fact.
	_chronicle.set_fact("c", 3)
	var history: Array[Dictionary] = _chronicle.get_fact_history("c")
	assert_eq(history.size(), 1, "new fact after rollback has one timeline entry")


# Timeline is truncated after rollback
func test_timeline_truncated() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)

	_chronicle.rollback_to(1.5)

	var history: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(history.size(), 1)
	assert_eq(history[0].key, "a")


# state_reset signal fires during rollback
func test_state_reset_fires() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 1)
	set_time(2.0)
	_chronicle.set_fact("x", 2)

	var ev := collect_any_signal(_chronicle, "state_reset")

	_chronicle.rollback_to(1.5)

	ev.assert_emission_count(1)


# state_rolled_back signal fires with correct target_time
func test_state_rolled_back_signal_fires() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 1)
	set_time(5.0)
	_chronicle.set_fact("x", 2)

	var ev := collect_any_signal(_chronicle, "state_rolled_back")

	_chronicle.rollback_to(3.0)

	ev.assert_emission_count(1)
	ev.assert_emission_args(0, [3.0])


# fact_changed fires during rollback with correct null value for erasures
func test_fact_changed_fires_during_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	set_time(2.0)
	_chronicle.set_fact("player.gold", 200)
	set_time(3.0)
	_chronicle.set_fact("player.hp", 50)

	var change_log := collect_signal(_chronicle, "fact_changed")

	_chronicle.rollback_to(1.5)

	# player.gold reverts 200->100 (fact_changed), player.hp erased (fact_changed with null)
	change_log.assert_count(2)


# ── Edge case validation ──


# NaN time returns false
func test_nan_returns_false() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_rollback_rejected(_chronicle.rollback_to(NAN))
	assert_fact("a", 1)


# INF time returns false
func test_inf_returns_false() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_rollback_rejected(_chronicle.rollback_to(INF))
	assert_fact("a", 1)


# Negative time returns false
func test_negative_returns_false() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	assert_rollback_rejected(_chronicle.rollback_to(-1.0))
	assert_fact("a", 1)


# Future time returns false
func test_future_time_returns_false() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	assert_rollback_rejected(_chronicle.rollback_to(100.0))
	assert_fact("a", 1)


# Re-entrancy during cascade returns false
func test_reentrant_rollback_blocked() -> void:
	set_time(1.0)
	_chronicle.set_fact("trigger", false)
	set_time(2.0)
	_chronicle.set_fact("guarded", 100)

	var rollback_result: Array = []
	_chronicle.watch("trigger", func(_k: String, _v: Variant, _old: Variant) -> void:
		rollback_result.append(_chronicle.rollback_to(0.5))
	)

	_chronicle.set_fact("trigger", true)

	assert_eq(rollback_result.size(), 1)
	assert_rollback_rejected(rollback_result[0])
	assert_fact("guarded", 100)


# Beyond timeline cap — rollback still succeeds by restoring from old_value
func test_beyond_timeline_cap_returns_false() -> void:
	# Reduce cap via internal API — after_each restores it to 10000
	_chronicle._timeline.set_cap(10)

	set_time(50.0)
	for i in range(12):
		_chronicle.set_fact("key%d" % i, i)

	# With R22+ rollback_to before oldest entry succeeds — all remaining entries are undone
	var result = _chronicle.rollback_to(30.0)
	assert_rollback_ok(result)
	# All entries at t=50 are rolled back; key0-key1 were dropped by cap, key2-key11 erased
	assert_no_fact("key11")


# No-op when nothing to undo returns true
func test_noop_returns_true() -> void:
	set_time(5.0)
	_chronicle.set_fact("a", 1)
	set_time(10.0)

	var ok = _chronicle.rollback_to(8.0)
	assert_rollback_ok(ok)
	assert_fact("a", 1)
	# No-action rollback still rewinds clock and emits rolled_back
	assert_game_time(8.0)


# Empty timeline returns true
func test_empty_timeline_returns_true() -> void:
	set_time(5.0)
	var ok = _chronicle.rollback_to(3.0)
	assert_rollback_ok(ok)
	# No-action rollback still rewinds clock
	assert_game_time(3.0)


# Full undo to time 0 — anchor at t=0 enables rollback_to(0.0)
func test_full_undo_to_zero() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	set_time(2.0)
	_chronicle.set_fact("quest.done", true)

	var ok = _chronicle.rollback_to(0.0)

	assert_rollback_ok(ok)
	# Anchor at t=0 survives (bisect_after(0.0) is past it)
	assert_fact("anchor", 0)
	assert_no_fact("player.gold")
	assert_no_fact("quest.done")
	assert_game_time(0.0)


# No-op rollback emits state_rolled_back but not state_reset
func test_noop_emits_state_rolled_back_only() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(10.0)

	var reset_ev := collect_any_signal(_chronicle, "state_reset")
	var rolled_ev := collect_any_signal(_chronicle, "state_rolled_back")

	var ok = _chronicle.rollback_to(8.0)

	assert_rollback_ok(ok)
	# No-op rollback emits state_rolled_back but not state_reset
	reset_ev.assert_emission_count(0)
	rolled_ev.assert_emission_count(1)
	rolled_ev.assert_emission_args(0, [8.0])
	assert_fact("a", 1)


# ── Multi-write and data integrity ──


# Same key written multiple times — rollback restores correct intermediate value
func test_multi_write_same_key() -> void:
	set_time(1.0)
	_chronicle.set_fact("score", 10)
	set_time(2.0)
	_chronicle.set_fact("score", 20)
	set_time(3.0)
	_chronicle.set_fact("score", 30)
	set_time(4.0)
	_chronicle.set_fact("score", 40)

	_chronicle.rollback_to(2.5)

	assert_fact("score", 20)


# Write-erase-write pattern — rollback to before second write
func test_write_erase_write() -> void:
	set_time(1.0)
	_chronicle.set_fact("flag", true)
	set_time(2.0)
	_chronicle.erase_fact("flag")
	set_time(3.0)
	_chronicle.set_fact("flag", false)

	_chronicle.rollback_to(1.5)

	assert_fact("flag", true)


# Erase-then-write pattern — rollback to after erase
func test_erase_then_write() -> void:
	set_time(1.0)
	_chronicle.set_fact("item", "sword")
	set_time(2.0)
	_chronicle.erase_fact("item")
	set_time(3.0)
	_chronicle.set_fact("item", "shield")

	_chronicle.rollback_to(2.5)

	assert_no_fact("item")


# Deep copy safety — restored Dictionary is independent of timeline
func test_deep_copy_on_restore() -> void:
	var config: Dictionary = {"speed": 1, "volume": 5}
	set_time(1.0)
	_chronicle.set_fact("config", config)
	set_time(2.0)
	_chronicle.set_fact("config", {"speed": 99, "volume": 99})

	_chronicle.rollback_to(1.5)

	var restored: Variant = _chronicle.get_fact("config")
	assert_eq(restored["speed"], 1)
	assert_eq(restored["volume"], 5)

	# Mutate the restored copy — original timeline should be unaffected
	restored["speed"] = 999
	var history: Array[Dictionary] = _chronicle.get_fact_history("config")
	assert_eq(history[0].value["speed"], 1)


# Entity index correct after rollback — erased keys removed
func test_entity_index_after_erase() -> void:
	set_time(1.0)
	_chronicle.set_fact("enemy.a.hp", 10)
	set_time(2.0)
	_chronicle.set_fact("enemy.b.hp", 20)

	_chronicle.rollback_to(1.5)

	assert_fact_count("enemy.*", 1)
	assert_has(_chronicle.get_fact_keys("enemy.*"), "enemy.a.hp")
	assert_no_fact("enemy.b.hp")


# Entity bucket pruned when all keys in entity removed
func test_entity_bucket_pruned() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("temp.x", 1)
	set_time(2.0)
	_chronicle.set_fact("temp.y", 2)

	_chronicle.rollback_to(0.0)

	assert_fact_count("temp.*", 0)


# Entity index correct after rollback — restored keys present
func test_entity_index_after_restore() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	set_time(2.0)
	_chronicle.erase_fact("player.gold")
	_chronicle.erase_fact("player.hp")

	assert_fact_count("player.*", 0)

	_chronicle.rollback_to(1.5)

	assert_fact_count("player.*", 2)
	assert_fact("player.gold", 100)
	assert_fact("player.hp", 50)


# ── rollback_steps ──


# rollback_steps(1) undoes the last entry
func test_rollback_steps_one() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("a", 2)

	var result = _chronicle.rollback_steps(1)

	assert_rollback_ok(result)
	assert_fact("a", 1)


# rollback_steps(3) undoes the last 3 entries
func test_rollback_steps_three() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)
	set_time(3.0)
	_chronicle.set_fact("c", 3)
	set_time(4.0)
	_chronicle.set_fact("d", 4)

	var result = _chronicle.rollback_steps(3)

	assert_rollback_ok(result)
	assert_fact("a", 1)
	assert_no_fact("b")
	assert_no_fact("c")
	assert_no_fact("d")


# rollback_steps(0) is a no-op
func test_rollback_steps_zero() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)

	var result = _chronicle.rollback_steps(0)

	assert_rollback_ok(result)
	assert_fact("a", 1)


# rollback_steps(-1) returns false
func test_rollback_steps_negative() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)

	assert_rollback_rejected(_chronicle.rollback_steps(-1))
	assert_fact("a", 1)


# rollback_steps(n) where n exceeds entries — partial rollback returns false
func test_rollback_steps_exceeds_entries() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(2.0)
	_chronicle.set_fact("b", 2)

	var result = _chronicle.rollback_steps(100)

	assert_rollback_rejected(result)
	# But the partial rollback should still have executed
	assert_no_fact("a")
	assert_no_fact("b")
	# When all entries are rolled back (cut==0), target_time is 0.0
	assert_game_time(0.0)


# rollback_steps skips transient entries when counting
func test_rollback_steps_skips_transient() -> void:
	set_time(1.0)
	_chronicle.set_fact("persistent.a", 1)
	set_time(2.0)
	_chronicle.set_fact("temp.flag", true, true, 0.0)
	set_time(3.0)
	_chronicle.set_fact("persistent.b", 2)

	# Step 1 should undo persistent.b (skipping transient temp.flag)
	var result = _chronicle.rollback_steps(1)

	assert_rollback_ok(result)
	assert_no_fact("persistent.b")
	# persistent.a still exists
	assert_fact("persistent.a", 1)
	# transient fact preserved
	assert_fact("temp.flag", true)
	# clock set to last surviving entry's time (transient at t=2.0)
	assert_game_time(2.0)


# rollback_steps with empty timeline is a successful no-op
func test_rollback_steps_empty_timeline() -> void:
	var result = _chronicle.rollback_steps(1)
	assert_rollback_ok(result)
	assert_false(result.partial)
	assert_eq(result.steps_reverted, 0)


# rollback_steps sets game clock to last surviving entry's time
func test_rollback_steps_clock() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(5.0)
	_chronicle.set_fact("b", 2)
	set_time(10.0)
	_chronicle.set_fact("c", 3)

	_chronicle.rollback_steps(1)

	assert_game_time(5.0)


# rollback_steps with same-time entries undoes correct count
func test_rollback_steps_same_time() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	set_time(5.0)
	_chronicle.set_fact("b", 2)
	_chronicle.set_fact("c", 3)
	_chronicle.set_fact("d", 4)

	# Undo 2 steps: should undo d and c (both at time=5.0)
	_chronicle.rollback_steps(2)

	assert_fact("a", 1)
	assert_fact("b", 2)
	assert_no_fact("c")
	assert_no_fact("d")


# rollback_steps re-entrancy during cascade returns false
func test_rollback_steps_reentrant_blocked() -> void:
	set_time(1.0)
	_chronicle.set_fact("trigger", false)
	set_time(2.0)
	_chronicle.set_fact("guarded", 100)

	var rollback_result: Array = []
	_chronicle.watch("trigger", func(_k: String, _v: Variant, _old: Variant) -> void:
		rollback_result.append(_chronicle.rollback_steps(1))
	)

	_chronicle.set_fact("trigger", true)

	assert_eq(rollback_result.size(), 1)
	assert_rollback_rejected(rollback_result[0])
	assert_fact("guarded", 100)


# rollback_steps with all-transient timeline returns true (no steps to undo)
func test_rollback_steps_all_transient() -> void:
	set_time(1.0)
	_chronicle.set_fact("temp.a", 1, true, 0.0)
	set_time(2.0)
	_chronicle.set_fact("temp.b", 2, true, 0.0)

	var result = _chronicle.rollback_steps(1)

	assert_rollback_ok(result)
	assert_fact("temp.a", 1)
	assert_fact("temp.b", 2)


# rollback_steps partial — returns false but still executes the rollback
func test_rollback_steps_partial_returns_false() -> void:
	set_time(0.0)
	_chronicle.set_fact("a.key", 1)
	advance_time(1.0)
	_chronicle.set_fact("a.key", 2)
	advance_time(1.0)
	_chronicle.set_fact("a.key", 3)
	# Request 10 steps but only 3 exist
	var result = _chronicle.rollback_steps(10)
	assert_rollback_rejected(result)
	# But the partial rollback should still have executed — all steps undone
	assert_no_fact("a.key")
	assert_game_time(0.0)


# ── Transient preservation ──


# Transient facts survive rollback_to
func test_transient_survives_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("persistent.a", 100)
	_chronicle.set_fact("session.flag", true, true, 0.0)
	set_time(2.0)
	_chronicle.set_fact("persistent.a", 200)

	_chronicle.rollback_to(1.5)

	assert_fact("persistent.a", 100)
	assert_fact("session.flag", true)


# Transient facts skipped in restore map — value unchanged
func test_transient_value_unchanged_by_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("temp.counter", 1, true, 0.0)
	set_time(2.0)
	_chronicle.set_fact("temp.counter", 5, true, 0.0)
	set_time(3.0)
	_chronicle.set_fact("persistent.x", 99)

	_chronicle.rollback_to(1.5)

	# Transient was updated to 5 at time=2.0, which is after target.
	# But transients are preserved as-is — value stays 5.
	assert_fact("temp.counter", 5)
	assert_no_fact("persistent.x")


# Transient facts remain in entity index after rollback
func test_transient_in_entity_index_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.ui_flag", true, true, 0.0)
	set_time(2.0)
	_chronicle.set_fact("player.gold", 200)

	_chronicle.rollback_to(1.5)

	var found: Array[String] = _chronicle.get_fact_keys("player.*")
	assert_eq(found.size(), 2)
	assert_has(found, "player.gold")
	assert_has(found, "player.ui_flag")


# Full rollback to 0 preserves transient facts
func test_full_rollback_preserves_transient() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("a", 1)
	_chronicle.set_fact("temp", true, true, 0.0)

	_chronicle.rollback_to(0.0)

	assert_no_fact("a")
	assert_fact("temp", true)


# ── Serialization interaction ──


# Serialize after rollback produces consistent data
func test_serialize_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)
	set_time(2.0)
	_chronicle.set_fact("player.gold", 200)
	set_time(3.0)
	_chronicle.set_fact("quest.done", true)

	_chronicle.rollback_to(1.5)

	var data: Dictionary = _chronicle.serialize()
	assert_eq(data.game_time, 1.5)
	assert_eq(data.facts["player.gold"], 100)
	assert_does_not_have(data.facts, "quest.done")
	# Timeline should only contain entries at time <= 1.5.
	# Whole-number times (e.g. 1.0) are wire-encoded by the type codec as
	# {"_chronicle_type": "float_special", "v": "whole", "n": <float>};
	# fractional times serialize as a bare float. Extract either shape.
	for entry: Dictionary in data.timeline:
		var raw_time: Variant = entry.time
		var t: float = float(raw_time.get("n", 0.0)) if raw_time is Dictionary else float(raw_time)
		assert_lte(t, 1.5, "timeline entry time %f should be <= 1.5" % t)


# Deserialize then rollback works correctly
func test_deserialize_then_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("a", 10)
	set_time(2.0)
	_chronicle.set_fact("b", 20)

	roundtrip()

	# Play forward
	set_time(3.0)
	_chronicle.set_fact("c", 30)
	set_time(4.0)
	_chronicle.set_fact("a", 99)

	# Rollback to 2.5 — should undo c and a=99
	_chronicle.rollback_to(2.5)

	assert_fact("a", 10)
	assert_fact("b", 20)
	assert_no_fact("c")


# Save-load round-trip after rollback
func test_round_trip_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 1)
	set_time(2.0)
	_chronicle.set_fact("y", 2)
	set_time(3.0)
	_chronicle.set_fact("x", 99)

	_chronicle.rollback_to(2.5)

	# Save
	var data: Dictionary = _chronicle.serialize()
	var path: String = "user://test_rollback_roundtrip.json"
	var err: Error = save_temp(path, data)
	assert_eq(err, OK)

	# Reload
	_chronicle.clear()
	var loaded: Variant = read_file(path)
	assert_true(loaded is Dictionary)
	var ok: bool = _chronicle.deserialize(loaded)
	assert_true(ok)

	assert_fact("x", 1)
	assert_fact("y", 2)
	assert_game_time(2.5)


# ── Companion nodes ──


# Gate re-evaluates after rollback (opens → closes)
func test_gate_closes_after_rollback() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("boss.defeated", true)

	var door := add_node_2d("Door")
	var gate := CompanionFactory.make_gate({
		condition = "boss.defeated",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	door.add_child(gate)

	assert_gate_open(door)

	_chronicle.rollback_to(0.0)

	assert_gate_closed(door)


# Gate re-evaluates after rollback (closed → opens)
func test_gate_opens_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.done", true)
	set_time(2.0)
	_chronicle.erase_fact("quest.done")

	var chest := add_node_2d("Chest")
	var gate := CompanionFactory.make_gate({
		condition = "quest.done",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	chest.add_child(gate)

	assert_gate_closed(chest)

	_chronicle.rollback_to(1.5)

	assert_gate_open(chest)


# Reactor fires during rollback (event-driven via coordinator)
func test_reactor_fires_during_rollback() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("enemy.spawned", true)

	var reactor: Node = add_reactor({watch_pattern = "enemy.*"})

	# Reactor fires once on the new write (it was created after enemy.spawned).
	set_time(2.0)
	_chronicle.set_fact("enemy.count", 5)
	assert_spy_calls(reactor, 1)

	# Rollback — reactor fires via write_rollback for each restored key
	# (enemy.spawned and enemy.count both reverted), adding 2 more calls.
	_chronicle.rollback_to(0.5)

	assert_spy_calls(reactor, 3)


# Watchers still work after rollback for new writes
func test_watchers_fire_post_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("x", 1)

	var events := watch_events("x")

	set_time(2.0)
	_chronicle.set_fact("x", 2)
	events.assert_count(1)

	_chronicle.rollback_to(1.5)
	events.clear()

	# New write after rollback — watcher should fire
	set_time(3.0)
	_chronicle.set_fact("x", 99)
	events.assert_count(1)
	events.assert_event(0, "x", 99, EventCollector.SKIP)


# ── Transient and expiry restoration ──


# Rollback restores transient status when a transient fact was overwritten as non-transient
func test_rollback_restores_transient_status() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.speed", 2.0, true, 0.0)  # transient
	advance_time(1.0)
	_chronicle.set_fact("buff.speed", 3.0)  # non-transient overwrite
	_chronicle.rollback_to(0.5)
	# After rollback, buff.speed should have the transient value 2.0
	assert_fact("buff.speed", 2.0)
	# And it should be transient again — verify by serializing
	var data: Dictionary = _chronicle.serialize()
	# Transient facts are excluded from serialization
	var facts: Dictionary = data.get("facts", {})
	var has_buff: bool = false
	for k: String in facts:
		if "buff" in k and "speed" in k:
			has_buff = true
	assert_false(has_buff, "Transient fact should not appear in serialization after rollback")


# Rollback restores expiry when an expiring fact was overwritten with explicit lifetime=0
func test_rollback_restores_expiry() -> void:
	set_time(0.0)
	_chronicle.set_fact("buff.atk", 10, false, 5.0)  # 5 second lifetime
	advance_time(1.0)
	_chronicle.set_fact("buff.atk", 20, false, 0.0)  # overwrite with explicit lifetime=0 clears expiry
	# buff.atk should no longer have an expiry
	assert_no_expiry("buff.atk")
	_chronicle.rollback_to(0.5)
	# After rollback, expiry should be restored
	assert_fact("buff.atk", 10)
	assert_has_expiry("buff.atk")


# ── Rollback guard / edge cases ──

# NOTE: the former test_50_guard_checks_empty_map_regardless_of_success was DELETED.
# It reimplemented the coordinator's empty-restore-map guard inline as a tautology
# (`{}.is_empty()` after `r._restore_map = {}`), so it could never detect a product
# regression. The real guard path (empty/no-op restore map handled gracefully) is
# already driven by test_empty_timeline_returns_true, test_rollback_steps_empty_timeline,
# and test_rollback_steps_all_transient.


# Zero-step rollback is a no-op: no state_reset, succeeds, reverts nothing
func test_rollback_steps_zero_is_noop() -> void:
	_chronicle.set_fact("a", 1)

	var reset_ev := collect_any_signal(_chronicle, "state_reset")

	var result = _chronicle.rollback_steps(0)

	# Zero-step rollback should be a no-op
	assert_fact("a", 1)
	reset_ev.assert_emission_count(0)
	assert_rollback_ok(result)
	assert_eq(result.steps_reverted, 0, "no-op rollback reverts zero steps")


# Partial rollback exceeding history reverts everything and reports partial
func test_rollback_steps_partial_exceeding_history() -> void:
	_chronicle.set_fact("x", 1)

	# Request more steps than exist
	var result = _chronicle.rollback_steps(100)

	assert_true(result.partial, "should be partial rollback")
	assert_no_fact("x")


# ── R14/R15 bug regression ──


# Rolling back all steps should set the clock to 0.0
func test_rollback_steps_cut_zero_target_time_is_zero() -> void:
	_chronicle.set_game_time(5.0)
	_chronicle.set_fact("a", 1)
	_chronicle.set_game_time(10.0)
	_chronicle.set_fact("b", 2)

	var rolled_ev := collect_any_signal(_chronicle, "state_rolled_back")

	_chronicle.rollback_steps(2)

	# target_time is 0.0 when all steps are rolled back
	rolled_ev.assert_emission_count(1)
	rolled_ev.assert_emission_args(0, [0.0])
	assert_eq(_chronicle.get_game_time(), 0.0,
		"clock should be at 0.0 after rolling back all steps")


# Rollback to before the earliest entry now succeeds (R22 fix)
func test_rollback_to_before_earliest_entry_succeeds() -> void:
	_chronicle.set_game_time(10.0)
	_chronicle.set_fact("a", 1)

	# Rolling back to before the timeline now succeeds — all entries are reverted
	var result = _chronicle.rollback_to(0.0)
	assert_rollback_ok(result)
	assert_no_fact("a")
	assert_game_time(0.0)


# The two rollback methods have consistent return types (RollbackResult)
func test_rollback_return_type_consistency() -> void:
	_chronicle.set_game_time(5.0)
	_chronicle.set_fact("a", 1)

	var result_to = _chronicle.rollback_to(0.0)
	var result_steps = _chronicle.rollback_steps(0)

	# FIXED: both rollback methods return RollbackResult
	assert_true(result_to is Chronicle.RollbackResult,
		"rollback_to returns RollbackResult")
	assert_true(result_steps is Chronicle.RollbackResult,
		"rollback_steps returns RollbackResult — consistent with rollback_to")


# rollback_to should not return junk fields — steps_reverted and requested default to 0
func test_rollback_to_should_not_return_junk_fields() -> void:
	_chronicle.set_fact("a", 1)
	advance_time(1.0)
	_chronicle.set_fact("a", 2)
	advance_time(1.0)
	_chronicle.set_fact("a", 3)

	var result = _chronicle.rollback_to(1.0)
	assert_rollback_ok(result)

	# CORRECT: steps_reverted and requested default to 0 for time-based rollback.
	assert_eq(result.steps_reverted, 0,
		"steps_reverted should be 0 for rollback_to result")
	assert_eq(result.requested, 0,
		"requested should be 0 for rollback_to result")


# get_fact_history should return correct count after rollback + append past old size
func test_fact_history_correct_after_rollback_then_append() -> void:
	for i: int in range(5):
		advance_time(1.0)
		_chronicle.set_fact("x", i)

	# Build the key index by reading history
	var h1: Array = _chronicle.get_fact_history("x")
	assert_eq(h1.size(), 5, "x has 5 history entries before rollback")

	# Rollback to t=2 — removes entries at t>2 (3 entries removed)
	_chronicle.rollback_to(2.0)

	# Append new entries that grow past the original size
	for i: int in range(10):
		advance_time(1.0)
		_chronicle.set_fact("y", i)

	# CORRECT: "y" should have 10 history entries
	var h2: Array = _chronicle.get_fact_history("y")
	assert_eq(h2.size(), 10,
		"get_fact_history should return correct count after rollback + append past old size")
