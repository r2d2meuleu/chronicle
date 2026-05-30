extends ChronicleTestSuite

## Integration tests: rollback (rollback_to, rollback_steps) interacting with
## gates, signals, timeline, lifetime/transient, reactors, and serialization.


# ── Rollback + Gates ──


# Gate opened by fact, rollback removes fact, gate closes
func test_rollback_past_gate_trigger_closes_gate() -> void:
	var target := add_gate("quest.done")

	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("quest.done", true)
	assert_gate_open(target)

	set_time(10.0)
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	assert_gate_closed(target)
	assert_no_fact("quest.done")


# Inverted gate (SHOW_WHEN_FALSE) — rollback past trigger reopens it
func test_rollback_past_trigger_reopens_inverted_gate() -> void:
	var target := add_gate("enemy.alive", {
		gate_mode = CompanionFactory.GateMode.SHOW_WHEN_FALSE,
	})

	# Initially: enemy.alive is false/missing => SHOW_WHEN_FALSE => gate open
	assert_gate_open(target)

	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("enemy.alive", true)
	# Now enemy.alive is true => SHOW_WHEN_FALSE => gate closed
	assert_gate_closed(target)

	set_time(10.0)
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	# After rollback, enemy.alive is gone => condition false => SHOW_WHEN_FALSE => gate open
	assert_gate_open(target)
	assert_no_fact("enemy.alive")


# Gate with QUEUE_FREE mode — rollback does not crash (node already freed)
func test_rollback_with_queue_free_gate_target_freed() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(2.0)
	_chronicle.set_fact("pickup.collected", true)

	var target := add_gate("pickup.collected", {
		gate_mode = CompanionFactory.GateMode.QUEUE_FREE_WHEN_TRUE,
	})

	# Gate triggered QUEUE_FREE immediately on _ready (condition already true)
	assert_true(target.is_queued_for_deletion())

	# Rollback past the time the fact was set — should not crash even though target is deleted
	set_time(10.0)
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	assert_no_fact("pickup.collected")


# Gate with compound condition — partial rollback changes truth value
func test_gate_compound_condition_after_partial_rollback() -> void:
	var target := add_gate("quest.a AND quest.b")

	set_time(5.0)
	_chronicle.set_fact("quest.a", true)
	# Only a is set: gate still closed
	assert_gate_closed(target)

	set_time(10.0)
	_chronicle.set_fact("quest.b", true)
	# Both a and b set: gate open
	assert_gate_open(target)

	# Partial rollback to t=7: erases quest.b but keeps quest.a
	var ok = _chronicle.rollback_to(7.0)
	assert_rollback_ok(ok)
	assert_fact("quest.a", true)
	assert_no_fact("quest.b")
	# Compound condition now false: gate closes
	assert_gate_closed(target)


# Multiple gates on different conditions all update after rollback
func test_multiple_gates_update_on_rollback() -> void:
	var target_a := add_gate("door.a.open")
	var target_b := add_gate("door.b.open")
	var target_c := add_gate("door.c.open")

	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("door.a.open", true)
	_chronicle.set_fact("door.b.open", true)
	_chronicle.set_fact("door.c.open", true)

	assert_gate_open(target_a)
	assert_gate_open(target_b)
	assert_gate_open(target_c)

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	assert_gate_closed(target_a)
	assert_gate_closed(target_b)
	assert_gate_closed(target_c)
	assert_no_fact("door.a.open")
	assert_no_fact("door.b.open")
	assert_no_fact("door.c.open")


# ── Rollback + Signals ──


# state_rolled_back signal emits with correct target_time
func test_state_rolled_back_signal_emits_target_time() -> void:
	set_time(2.0)
	_chronicle.set_fact("signal.setup", 0)
	set_time(10.0)
	_chronicle.set_fact("signal.test", 1)

	var rolled_back := collect_any_signal(_chronicle, "state_rolled_back")

	var ok = _chronicle.rollback_to(5.0)
	assert_rollback_ok(ok)
	rolled_back.assert_emission_args(0, [5.0])


# state_reset signal fires after rollback
func test_state_reset_fires_after_rollback() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("bulk.check", true)

	var reset_events := collect_any_signal(_chronicle, "state_reset")

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	reset_events.assert_emission_count(1)


# fact_changed fires per-key during rollback with null value for erasures
func test_fact_changed_emitted_during_rollback() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("change.a", 1)
	_chronicle.set_fact("change.b", 2)

	var col := collect_signal(_chronicle, "fact_changed")

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)
	# change.a and change.b are erased by rollback — fact_changed fires with null for each
	col.assert_count(2)


# ── Rollback + Timeline ──


# Timeline is truncated after rollback (entries past target removed)
func test_timeline_truncated_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("timeline.a", 1)
	set_time(2.0)
	_chronicle.set_fact("timeline.b", 2)
	set_time(3.0)
	_chronicle.set_fact("timeline.c", 3)

	# Before rollback: 3 entries
	var before: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(before.size(), 3)

	var ok = _chronicle.rollback_to(1.5)
	assert_rollback_ok(ok)

	# After rollback: only entry at t=1.0 survives (t=2, t=3 truncated)
	var after: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(after.size(), 1)
	assert_eq(after[0].key as String, "timeline.a")


# set_fact after rollback creates new timeline from rollback point
func test_set_after_rollback_creates_new_timeline() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("branch.original", true)

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	set_time(3.0)
	_chronicle.set_fact("branch.new", 42)

	# get_changes_between uses half-open interval (since, until] — exclusive lower bound.
	# anchor at t=0 is excluded by (0.0, ...]. Only branch.new at t=3 is included.
	var all: Array[Dictionary] = _chronicle.get_changes_between(0.0, _chronicle.get_game_time())
	assert_eq(all.size(), 1, "only branch.new at t=3 included — anchor at t=0 excluded by (0, ...]")
	assert_eq(all[0].key as String, "branch.new")
	assert_eq(all[0].value, 42)
	assert_no_fact("branch.original")


# fact_history reflects rolled-back state
func test_fact_history_reflects_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("history.key", 10)
	set_time(2.0)
	_chronicle.set_fact("history.key", 20)
	set_time(3.0)
	_chronicle.set_fact("history.key", 30)

	# Full history: 3 entries
	assert_history("history.key", [10, 20, 30], [1.0, 2.0, 3.0])

	# Rollback past t=2: removes the 20 and 30 entries
	var ok = _chronicle.rollback_to(1.5)
	assert_rollback_ok(ok)

	# Only the t=1 entry remains
	assert_history("history.key", [10], [1.0])
	assert_fact("history.key", 10)


# ── Rollback + Lifetime/Transient ──


# Transient facts NOT affected by rollback
func test_rollback_does_not_affect_transient_facts() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("persistent.key", 99)
	# Transient fact set AFTER the persistent one
	_chronicle.set_fact("transient.key", "volatile", true, 0.0)

	assert_fact("persistent.key", 99)
	assert_fact("transient.key", "volatile")

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	# Persistent fact is gone (was after rollback point)
	assert_no_fact("persistent.key")
	# Transient fact is untouched by rollback
	assert_fact("transient.key", "volatile")


# Rollback to before expiration restores expired fact (timeline entry exists)
func test_rollback_restores_expired_lifetime_fact() -> void:
	set_time(1.0)
	_chronicle.set_fact("buff.speed", 2.0, false, 5.0)
	assert_fact("buff.speed", 2.0)

	# Expire the fact by advancing time past the lifetime
	advance_time(6.0)
	assert_no_fact("buff.speed")

	# Rollback to t=1.5 — transient marker cleaned on erase, so rollback restores the fact
	var ok = _chronicle.rollback_to(1.5)
	assert_rollback_ok(ok)
	assert_fact("buff.speed", 2.0)


# Persistent fact set, then rollback — fact is erased
func test_rollback_erases_facts_set_after_target() -> void:
	set_time(0.0)
	_chronicle.set_fact("base.value", 1)

	set_time(5.0)
	_chronicle.set_fact("later.value", 100)
	_chronicle.set_fact("base.value", 999)

	assert_fact("later.value", 100)
	assert_fact("base.value", 999)

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	assert_no_fact("later.value")
	# base.value was first set at t=0, so it's restored to that state
	assert_fact("base.value", 1)


# ── Rollback + Reactors ──


# Reactor's watch still active after rollback (it uses the watch system)
func test_reactor_still_watches_after_rollback() -> void:
	var reactor := add_reactor({
		watch_pattern = "unit.health",
		react_to = CompanionFactory.ReactTo.ANY,
	})

	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("unit.health", 100)

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	# Rollback fires reactor (event-driven via coordinator), then new write fires it again
	_chronicle.set_fact("unit.health", 50)
	assert_spy_calls(reactor, 3)
	assert_spy_call(reactor, 2, EventCollector.SKIP, 50)


# One-shot reactor resets on rollback — fires again after re-registration
func test_one_shot_reactor_resets_after_rollback() -> void:
	var reactor := add_reactor({
		watch_pattern = "chest.opened",
		react_to = CompanionFactory.ReactTo.ANY,
		one_shot = true,
	})

	_chronicle.set_fact("anchor", 0)
	set_time(5.0)
	_chronicle.set_fact("chest.opened", true)
	assert_spy_calls(reactor, 1)

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	# state_reset re-registers the reactor, _has_fired is reset — fires again
	_chronicle.set_fact("chest.opened", true)
	assert_spy_calls(reactor, 2)


# ── Rollback + Serialization ──


# serialize() after rollback reflects rolled-back state
func test_serialize_after_rollback_reflects_state() -> void:
	set_time(1.0)
	_chronicle.set_fact("save.level", 1)
	set_time(5.0)
	_chronicle.set_fact("save.level", 2)
	_chronicle.set_fact("save.score", 9000)

	var ok = _chronicle.rollback_to(2.0)
	assert_rollback_ok(ok)

	var data: Dictionary = _chronicle.serialize()
	assert_has(data, "facts")

	# save.level should be 1 (the t=1 value), save.score should be absent
	assert_has(data["facts"], "save.level")
	assert_does_not_have(data["facts"], "save.score")


# Rollback then save then load — consistent state
func test_rollback_save_load_consistent() -> void:
	set_time(1.0)
	_chronicle.set_fact("rsl.a", 10)
	set_time(5.0)
	_chronicle.set_fact("rsl.a", 20)
	_chronicle.set_fact("rsl.b", 99)

	var ok = _chronicle.rollback_to(2.0)
	assert_rollback_ok(ok)

	# Serialize the rolled-back state
	var data: Dictionary = _chronicle.serialize()
	var path: String = "user://chronicle_test_rollback_save_load.json"
	var err: Error = save_temp(path, data)
	assert_eq(err, OK)

	# Load into a fresh Chronicle instance
	var loaded: Variant = read_file(path)
	assert_not_null(loaded)

	var c2: Node = add_child_autoqfree(Chronicle.new())
	var load_ok: bool = c2.deserialize(loaded)
	assert_true(load_ok)

	# Verify restored state matches rolled-back state
	assert_eq(c2.get_fact("rsl.a"), 10)
	assert_false(c2.has_fact("rsl.b"), "rsl.b was set after rollback target and should be absent")


# Deserialize into fresh Chronicle then rollback works
func test_deserialize_then_rollback_works() -> void:
	# Set up state with a timeline spanning t=0..t=10
	set_time(2.0)
	_chronicle.set_fact("dtr.x", 1)
	set_time(8.0)
	_chronicle.set_fact("dtr.x", 2)
	_chronicle.set_fact("dtr.y", 99)

	var data: Dictionary = _chronicle.serialize()

	# Load into a second chronicle
	var c2: Node = add_child_autoqfree(Chronicle.new())
	var load_ok: bool = c2.deserialize(data)
	assert_true(load_ok)

	# Rollback within that second chronicle
	var rb_ok = c2.rollback_to(3.0)
	assert_rollback_ok(rb_ok)

	# State should match what was recorded at t=2
	assert_eq(c2.get_fact("dtr.x"), 1)
	assert_false(c2.has_fact("dtr.y"), "dtr.y was set at t=8 and should be absent after rollback to t=3")
	assert_eq(c2.get_game_time(), 3.0)


# ── Rollback Steps ──


# rollback_steps(1) reverts last persistent write
func test_rollback_steps_reverts_last_write() -> void:
	set_time(1.0)
	_chronicle.set_fact("step.val", 10)
	set_time(2.0)
	_chronicle.set_fact("step.val", 20)

	var result = _chronicle.rollback_steps(1)
	assert_rollback_ok(result)

	# Last write (val=20) reverted; val should be 10
	assert_fact("step.val", 10)


# rollback_steps skips transient entries in timeline
func test_rollback_steps_skips_transient() -> void:
	set_time(1.0)
	_chronicle.set_fact("perm.first", 1)
	set_time(2.0)
	_chronicle.set_fact("perm.second", 2)
	# Transient fact — does not count as a persistent step
	_chronicle.set_fact("transient.temp", "skip_me", true, 0.0)

	# rollback_steps(1) should revert only perm.second (the last persistent entry)
	var result = _chronicle.rollback_steps(1)
	assert_rollback_ok(result)

	assert_fact("perm.first", 1)
	assert_no_fact("perm.second")
	# Transient fact is unaffected
	assert_fact("transient.temp", "skip_me")


# rollback_steps(0) is a no-op (returns true)
func test_rollback_steps_zero_is_noop() -> void:
	set_time(5.0)
	_chronicle.set_fact("noop.val", 42)

	var result = _chronicle.rollback_steps(0)
	assert_rollback_ok(result)

	# State unchanged
	assert_fact("noop.val", 42)
	assert_game_time(5.0)


# rollback_steps on empty timeline is a successful no-op
func test_rollback_steps_empty_timeline_is_successful_noop() -> void:
	# Clear leaves an empty timeline
	_chronicle.clear()

	var result = _chronicle.rollback_steps(1)
	assert_rollback_ok(result)
	assert_false(result.partial)
	assert_eq(result.steps_reverted, 0)


# ── Multi-Operation Sequences ──


# Set → rollback → set again produces correct timeline
func test_set_rollback_set_correct_timeline() -> void:
	set_time(1.0)
	_chronicle.set_fact("seq.key", "first")
	set_time(5.0)
	_chronicle.set_fact("seq.key", "second")

	# Rollback to before the second write
	var ok = _chronicle.rollback_to(2.0)
	assert_rollback_ok(ok)
	assert_fact("seq.key", "first")

	# Now write a new value — this should fork the timeline from t=2
	set_time(3.0)
	_chronicle.set_fact("seq.key", "third")
	assert_fact("seq.key", "third")

	# Timeline should contain only the two surviving entries: "first" at t=1, "third" at t=3
	assert_history("seq.key", ["first", "third"])


# Multiple rollbacks in sequence (rollback twice)
func test_multiple_rollbacks_in_sequence() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(2.0)
	_chronicle.set_fact("multi.rb", 1)
	set_time(5.0)
	_chronicle.set_fact("multi.rb", 2)
	set_time(8.0)
	_chronicle.set_fact("multi.rb", 3)

	# First rollback: revert to t=6
	var ok1 = _chronicle.rollback_to(6.0)
	assert_rollback_ok(ok1)
	assert_fact("multi.rb", 2)
	assert_game_time(6.0)

	# Second rollback: revert to t=3
	var ok2 = _chronicle.rollback_to(3.0)
	assert_rollback_ok(ok2)
	assert_fact("multi.rb", 1)
	assert_game_time(3.0)

	# Third rollback: revert to t=0
	var ok3 = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok3)
	assert_no_fact("multi.rb")
	assert_game_time(0.0)


# rollback_to(0) with anchor at t=0 — restores to initial state
func test_rollback_to_zero_restores_empty() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("zero.a", 1)
	_chronicle.set_fact("zero.b", 2)

	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	assert_no_fact("zero.a")
	assert_no_fact("zero.b")
	assert_game_time(0.0)
	# Anchor fact at t=0 survives rollback — verify via fact existence
	assert_fact("anchor", 0)


# Rollback after set_facts (bulk) operation
func test_rollback_after_bulk_set_facts() -> void:
	set_time(2.0)
	_chronicle.set_fact("pre.existing", true)

	set_time(5.0)
	_chronicle.set_facts({
		"bulk.alpha": 1,
		"bulk.beta": 2,
		"bulk.gamma": 3,
	})

	assert_fact("bulk.alpha", 1)
	assert_fact("bulk.beta", 2)
	assert_fact("bulk.gamma", 3)

	var ok = _chronicle.rollback_to(3.0)
	assert_rollback_ok(ok)

	# All bulk-written facts were at t=5, so they're all gone
	assert_no_fact("bulk.alpha")
	assert_no_fact("bulk.beta")
	assert_no_fact("bulk.gamma")
	# Pre-existing fact at t=2 survives
	assert_fact("pre.existing", true)


# Gate + Reactor together — both update correctly after rollback
func test_gate_and_reactor_update_after_rollback() -> void:
	# Gate shows battle UI when combat is active
	var battle_ui := add_gate("combat.active")

	# Reactor logs combat fact changes
	var reactor := add_reactor({
		watch_pattern = "combat.*",
		react_to = CompanionFactory.ReactTo.ANY,
	})

	_chronicle.set_fact("anchor", 0)
	set_time(3.0)
	_chronicle.set_fact("combat.active", true)
	_chronicle.set_fact("combat.enemy_hp", 100)
	assert_gate_open(battle_ui)
	# Reactor should have fired twice (active + enemy_hp)
	assert_spy_calls(reactor, 2)

	# Rollback past the combat facts — reactor fires during rollback (event-driven)
	var ok = _chronicle.rollback_to(0.0)
	assert_rollback_ok(ok)

	# Gate re-evaluates: combat.active gone => gate closed
	assert_gate_closed(battle_ui)
	assert_no_fact("combat.active")
	assert_no_fact("combat.enemy_hp")

	# Reactor fired during rollback (2 keys restored) + new write = calls_before + 2 + 1
	_chronicle.set_fact("combat.active", true)
	assert_spy_calls(reactor, 5)
	assert_gate_open(battle_ui)
