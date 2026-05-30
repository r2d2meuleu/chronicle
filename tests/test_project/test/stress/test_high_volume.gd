extends ChronicleTestSuite


# ── Fact Volume ──


# 500 facts set — all stored and retrievable
func test_500_facts_all_stored_and_retrievable() -> void:
	for i in range(500):
		_chronicle.set_fact("item.%d" % i, i * 10)

	for i in range(500):
		assert_fact("item.%d" % i, i * 10)


# 200 facts via set_facts bulk — all stored correctly
func test_200_facts_via_set_facts_all_stored() -> void:
	var batch: Dictionary = {}
	for i in range(200):
		batch["batch.%d" % i] = i

	_chronicle.set_facts(batch)

	for i in range(200):
		assert_fact("batch.%d" % i, i)


# 500 facts serialize/deserialize roundtrip — all preserved
func test_500_facts_serialize_deserialize_roundtrip() -> void:
	for i in range(500):
		_chronicle.set_fact("item.%d" % i, i * 2)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "deserialize returned true")

	for i in range(500):
		assert_fact("item.%d" % i, i * 2)


# find glob with 500 facts returns correct subset
func test_find_glob_with_500_facts_returns_correct_subset() -> void:
	for i in range(300):
		_chronicle.set_fact("alpha.%d" % i, i)
	for i in range(200):
		_chronicle.set_fact("beta.%d" % i, i)

	var alpha_keys: Array[String] = _chronicle.get_fact_keys("alpha.*")
	var beta_keys: Array[String] = _chronicle.get_fact_keys("beta.*")
	var all_keys: Array[String] = _chronicle.get_fact_keys("*")

	assert_eq(alpha_keys.size(), 300, "find alpha.* returns 300 keys")
	assert_eq(beta_keys.size(), 200, "find beta.* returns 200 keys")
	assert_eq(all_keys.size(), 500, "find * returns all 500 keys")

	# Spot-check membership and exclusion
	assert_has(alpha_keys, "alpha.0")
	assert_has(alpha_keys, "alpha.299")
	assert_does_not_have(alpha_keys, "beta.0")
	assert_has(beta_keys, "beta.0")
	assert_has(beta_keys, "beta.199")
	assert_does_not_have(beta_keys, "alpha.0")


# count with 500 facts matches find.size()
func test_count_matches_find_size_with_500_facts() -> void:
	for i in range(400):
		_chronicle.set_fact("alpha.%d" % i, i)
	for i in range(100):
		_chronicle.set_fact("beta.%d" % i, i)

	var alpha_count: int = _chronicle.count_facts("alpha.*")
	var beta_count: int = _chronicle.count_facts("beta.*")
	var total_count: int = _chronicle.count_facts("*")

	assert_eq(alpha_count, _chronicle.get_fact_keys("alpha.*").size(), "count matches find.size for alpha.*")
	assert_eq(beta_count, _chronicle.get_fact_keys("beta.*").size(), "count matches find.size for beta.*")
	assert_eq(total_count, _chronicle.get_fact_keys("*").size(), "count matches find.size for *")
	assert_eq(alpha_count, 400)
	assert_eq(beta_count, 100)
	assert_eq(total_count, 500)


# erase_facts 200 keys — all removed, others intact
func test_erase_facts_200_keys_all_removed_others_intact() -> void:
	for i in range(300):
		_chronicle.set_fact("keep.%d" % i, i)
	for i in range(200):
		_chronicle.set_fact("drop.%d" % i, i)

	var drop_keys: Array[String] = []
	for i in range(200):
		drop_keys.append("drop.%d" % i)

	_chronicle.erase_facts(drop_keys)

	# All dropped keys must be absent
	for i in range(200):
		assert_no_fact("drop.%d" % i)

	# All kept keys must remain intact
	for i in range(300):
		assert_fact("keep.%d" % i, i)


# ── Watcher Volume ──


# 50 exact watchers on different keys — all fire when their key changes
func test_50_exact_watchers_all_fire_on_their_key() -> void:
	var fired: Array = []
	for i in range(50):
		var key := "target.%d" % i
		_chronicle.watch(key, func(k: String, _v: Variant, _o: Variant) -> void:
			fired.append(k)
		)

	for i in range(50):
		_chronicle.set_fact("target.%d" % i, i)

	assert_eq(fired.size(), 50, "all 50 watchers fired")

	# Every key must appear exactly once
	for i in range(50):
		assert_has(fired, "target.%d" % i)


# 20 glob watchers — all fire for matching key
func test_20_glob_watchers_all_fire_for_matching_key() -> void:
	var counts: Array = []
	for i in range(20):
		counts.append(0)

	for i in range(20):
		var idx := i
		_chronicle.watch("entity.*", func(_k: String, _v: Variant, _o: Variant) -> void:
			counts[idx] += 1
		)

	_chronicle.set_fact("entity.hp", 100)

	for i in range(20):
		assert_eq(counts[i], 1, "glob watcher %d fired once" % i)


# 50 watchers on same key — all receive same event
func test_50_watchers_same_key_all_receive_event() -> void:
	var received_values: Array = []
	for i in range(50):
		_chronicle.watch("shared.value", func(_k: String, v: Variant, _o: Variant) -> void:
			received_values.append(v)
		)

	_chronicle.set_fact("shared.value", 42)

	assert_eq(received_values.size(), 50, "all 50 watchers received the event")
	for v in received_values:
		assert_eq(v, 42, "each watcher received value 42")


# unwatch 30 watchers in sequence — no leak, remaining still work
func test_unwatch_30_watchers_remaining_still_work() -> void:
	var ids: Array = []
	var remaining_count: Array = [0]

	# Register 50 watchers
	for i in range(50):
		var id: int = _chronicle.watch("multi.key", func(_k: String, _v: Variant, _o: Variant) -> void:
			remaining_count[0] += 1
		)
		ids.append(id)

	# Unwatch the first 30
	for i in range(30):
		_chronicle.unwatch(ids[i])

	remaining_count[0] = 0
	_chronicle.set_fact("multi.key", 99)

	assert_eq(remaining_count[0], 20, "exactly 20 remaining watchers fired")


# watch + unwatch cycle 50 times — system stays clean
func test_watch_unwatch_cycle_50_times_system_stays_clean() -> void:
	var final_count: Array = [0]

	# Cycle: register and immediately unwatch 50 times
	for i in range(50):
		var id: int = _chronicle.watch("cycle.key", func(_k: String, _v: Variant, _o: Variant) -> void:
			final_count[0] += 1
		)
		_chronicle.unwatch(id)

	# Register one permanent watcher
	_chronicle.watch("cycle.key", func(_k: String, _v: Variant, _o: Variant) -> void:
		final_count[0] += 1
	)

	_chronicle.set_fact("cycle.key", 1)

	assert_eq(final_count[0], 1, "only the one permanent watcher fired — cycled watchers left no leak")


# ── Timeline Volume ──


# 500 changes to same key — fact_history returns all
func test_500_changes_same_key_fact_history_returns_all() -> void:
	for i in range(500):
		advance_time(0.01)
		_chronicle.set_fact("evolving.key", i)

	assert_history_size("evolving.key", 500)
	assert_history_first("evolving.key", 0)
	assert_history_last("evolving.key", 499)


# changes_since with large timeline returns correct subset
func test_changes_since_large_timeline_returns_correct_subset() -> void:
	set_time(0.0)
	for i in range(200):
		advance_time(0.1)
		_chronicle.set_fact("key.%d" % i, i)

	# Cutoff at t=10.0 — facts 0..99 are before, facts 100..199 are at or after
	var result: Array[Dictionary] = _chronicle.get_changes_since(10.0)

	# Entries 100..199 are clearly >= 10.0 (100 entries); the boundary entry 99 lands at
	# ~10.0 but float accumulation from advance_time(0.1)×100 may drift it just under,
	# so the count is 100 or 101 depending on rounding. Tight range, not an exact pin.
	assert_between(result.size(), 100, 101, "changes_since returns the at-or-after subset (boundary float-sensitive)")
	for entry: Dictionary in result:
		assert_gte(entry.time, 10.0, "all returned entries have time >= 10.0")


# first_change with many entries finds correct earliest
func test_first_change_with_many_entries_finds_earliest() -> void:
	set_time(1.0)
	_chronicle.set_fact("record.first", "earliest")
	for i in range(1, 100):
		advance_time(0.1)
		_chronicle.set_fact("record.item.%d" % i, i)

	var first_entry: Variant = _chronicle.get_first_change("record.*")
	assert_not_null(first_entry, "first_change returns a result")
	assert_eq(first_entry.key as String, "record.first", "first_change returns the earliest key set")
	assert_eq(first_entry.value, "earliest", "first_change value is correct")
	assert_eq(first_entry.time, 1.0, "first_change time is 1.0")


# first_change with many entries finds correct latest
func test_last_change_with_many_entries_finds_latest() -> void:
	for i in range(99):
		_chronicle.set_fact("record.item.%d" % i, i)
		advance_time(0.1)

	set_time(100.0)
	_chronicle.set_fact("record.last", "latest")

	var last_entry: Variant = _chronicle.get_last_change("record.*")
	assert_not_null(last_entry, "last_change returns a result")
	assert_eq(last_entry.key as String, "record.last", "last_change returns the most recent key set")
	assert_eq(last_entry.value, "latest", "last_change value is correct")
	assert_eq(last_entry.time, 100.0, "last_change time is 100.0")


# rollback_steps(50) with large timeline restores correct state
func test_rollback_steps_50_large_timeline_restores_correctly() -> void:
	set_time(1.0)
	# Write 100 distinct keys at increasing times
	for i in range(100):
		advance_time(0.1)
		_chronicle.set_fact("step.%d" % i, i * 10)

	# Rollback 50 steps — should undo the last 50 writes (steps 50..99)
	var result = _chronicle.rollback_steps(50)
	assert_rollback_ok(result)

	# First 50 facts must still exist with correct values
	for i in range(50):
		assert_fact("step.%d" % i, i * 10)

	# Last 50 facts must have been removed
	for i in range(50, 100):
		assert_no_fact("step.%d" % i)


# ── Bulk Operations at Scale ──


# set_facts 100 keys with 20 watchers active — all fire correctly
func test_set_facts_100_keys_with_20_watchers_all_fire() -> void:
	var all_fired: Array = []
	for i in range(20):
		var idx := i
		_chronicle.watch("bulk.*", func(k: String, _v: Variant, _o: Variant) -> void:
			all_fired.append({watcher = idx, key = k})
		)

	var batch: Dictionary = {}
	for i in range(100):
		batch["bulk.%d" % i] = i

	_chronicle.set_facts(batch)

	# Each of the 100 keys must have fired all 20 watchers
	assert_eq(all_fired.size(), 100 * 20, "20 watchers * 100 keys = 2000 firings")

	# Verify facts are stored correctly
	for i in range(100):
		assert_fact("bulk.%d" % i, i)


# rapid increment 100 times — correct accumulated total
func test_rapid_increment_100_times_correct_total() -> void:
	_chronicle.set_fact("counter.score", 0)

	for i in range(100):
		_chronicle.increment_fact("counter.score", 5)

	assert_fact("counter.score", 500)


# rapid mark/unmark cycle 50 times — final state correct
func test_rapid_mark_unmark_cycle_final_state_correct() -> void:
	for i in range(50):
		_chronicle.set_fact("toggle.flag")
		_chronicle.erase_fact("toggle.flag")

	# After 50 cycles of mark/erase, the fact should not exist
	assert_no_fact("toggle.flag")

	# Verify with one final mark — it should stick
	_chronicle.set_fact("toggle.flag")
	assert_fact("toggle.flag", true)


# bulk set then bulk erase — state is clean
func test_bulk_set_then_bulk_erase_state_is_clean() -> void:
	var batch: Dictionary = {}
	for i in range(200):
		batch["temp.%d" % i] = i * 3

	_chronicle.set_facts(batch)
	assert_fact_count("temp.*", 200)

	var keys_to_erase: Array[String] = []
	for i in range(200):
		keys_to_erase.append("temp.%d" % i)

	_chronicle.erase_facts(keys_to_erase)

	assert_fact_count("temp.*", 0)
	for i in range(200):
		assert_no_fact("temp.%d" % i)


# ── Combined Pressure ──


# 200 facts + 20 watchers + serialize/deserialize — all correct after
func test_200_facts_20_watchers_serialize_deserialize_all_correct() -> void:
	var watcher_fires: Array = [0]
	for i in range(20):
		_chronicle.watch("world.*", func(_k: String, _v: Variant, _o: Variant) -> void:
			watcher_fires[0] += 1
		)

	for i in range(200):
		_chronicle.set_fact("world.%d" % i, i + 1)

	assert_eq(watcher_fires[0], 200 * 20, "20 watchers * 200 facts = 4000 firings before roundtrip")

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "deserialize returned true")

	for i in range(200):
		assert_fact("world.%d" % i, i + 1)

	assert_fact_count("world.*", 200)


# Full session simulation: 100 mixed operations in sequence
func test_full_session_simulation_100_mixed_operations() -> void:
	set_time(0.0)
	var op_count: Array = [0]

	_chronicle.watch("sim.*", func(_k: String, _v: Variant, _o: Variant) -> void:
		op_count[0] += 1
	)

	for i in range(100):
		advance_time(0.1)
		var op: int = i % 5
		match op:
			0:
				_chronicle.set_fact("sim.hp", 100 - i)
			1:
				_chronicle.set_fact("sim.score", i * 10)
			2:
				_chronicle.set_fact("sim.active")
			3:
				_chronicle.increment_fact("sim.kills", 1)
			4:
				_chronicle.set_fact("sim.level", i / 5)

	# All writes stored — verify final values
	assert_fact("sim.hp", 5)       # last set at i=95: 100-95
	assert_fact("sim.score", 960)  # last set at i=96: 96*10
	assert_marked("sim.active")    # marked at i=2,7,...,97
	assert_fact("sim.kills", 20)   # incremented 20 times (i=3,8,...,98)
	assert_fact("sim.level", 19)   # last set at i=99: 99/5

	# Watcher fires for each write that changes the value (same-value writes are suppressed)
	assert_eq(op_count[0], 81, "watcher fired for all value-changing operations")


# 50 facts with timeline at capacity — rollback still works
func test_50_facts_timeline_capacity_rollback_still_works() -> void:
	# Record a checkpoint at t=5.0
	set_time(5.0)
	for i in range(50):
		_chronicle.set_fact("anchor.%d" % i, i * 2)

	# Add more facts after the checkpoint
	for i in range(50):
		advance_time(0.1)
		_chronicle.set_fact("extra.%d" % i, i * 3)

	# Rollback to the checkpoint
	var ok = _chronicle.rollback_to(5.0)
	assert_rollback_ok(ok)

	# Anchor facts must be restored
	for i in range(50):
		assert_fact("anchor.%d" % i, i * 2)

	# Extra facts must be gone
	for i in range(50):
		assert_no_fact("extra.%d" % i)


# Multiple entities (10) with 50 facts each — queries return correct subsets
func test_multiple_entities_10_with_50_facts_each_correct_subsets() -> void:
	for entity_id in range(10):
		for attr_id in range(50):
			_chronicle.set_fact("e%d.attr.%d" % [entity_id, attr_id], entity_id * 1000 + attr_id)

	# Each entity should have exactly 50 facts
	for entity_id in range(10):
		var entity_keys: Array[String] = _chronicle.get_fact_keys("e%d.*" % entity_id)
		assert_eq(entity_keys.size(), 50, "entity %d has 50 facts" % entity_id)

		# Spot-check values in this entity
		assert_fact("e%d.attr.0" % entity_id, entity_id * 1000)
		assert_fact("e%d.attr.49" % entity_id, entity_id * 1000 + 49)

	# Total must be 500
	assert_fact_count("*", 500)


# ── Companion Nodes at Scale ──


# 10 gates on different conditions — all update when facts change
func test_10_gates_different_conditions_all_update() -> void:
	var targets: Array = []
	for i in range(10):
		var target := add_gate("gate.cond.%d" % i)
		targets.append(target)

	# All gates should be closed initially (conditions are false)
	for i in range(10):
		assert_gate_closed(targets[i])

	# Independence: setting only gate.cond.0 true opens gate 0 and leaves the
	# other nine closed — each gate reacts only to its own condition.
	_chronicle.set_fact("gate.cond.0", true)
	assert_gate_open(targets[0])
	for i in range(1, 10):
		assert_gate_closed(targets[i])

	# Set the remaining conditions true — each matching gate opens in turn.
	for i in range(1, 10):
		_chronicle.set_fact("gate.cond.%d" % i, true)
		assert_gate_open(targets[i])

	# With every condition now true, all gates must be open.
	for i in range(10):
		assert_gate_open(targets[i])


# 5 reactors watching same pattern — all receive events
func test_5_reactors_watching_same_pattern_all_receive_events() -> void:
	var reactors: Array = []
	var event_collectors: Array = []

	for i in range(5):
		var reactor := add_reactor({watch_pattern = "signal.*"})
		reactors.append(reactor)
		var collector := collect_signal(reactor, "fact_matched")
		event_collectors.append(collector)

	# Fire 10 facts matching the pattern
	for i in range(10):
		_chronicle.set_fact("signal.%d" % i, i)

	# Each reactor must have received all 10 events
	for i in range(5):
		var collector: EventCollector = event_collectors[i]
		collector.assert_count(10)


# Gates + reactors with bulk state change — all update correctly
func test_gates_and_reactors_bulk_state_change_all_update() -> void:
	# Set up 5 gates for 5 conditions
	var targets: Array = []
	for i in range(5):
		var target := add_gate("bulk.cond.%d" % i)
		targets.append(target)

	# Set up 3 reactors watching bulk.*
	var reactors: Array = []
	var collectors: Array = []
	for i in range(3):
		var reactor := add_reactor({watch_pattern = "bulk.*"})
		reactors.append(reactor)
		collectors.append(collect_signal(reactor, "fact_matched"))

	# All gates must be closed before bulk set
	for i in range(5):
		assert_gate_closed(targets[i])

	# Bulk-set all 5 conditions true
	var batch: Dictionary = {}
	for i in range(5):
		batch["bulk.cond.%d" % i] = true
	_chronicle.set_facts(batch)

	# All gates must now be open
	for i in range(5):
		assert_gate_open(targets[i])

	# Each reactor must have received 5 events (one per bulk key)
	for i in range(3):
		var collector: EventCollector = collectors[i]
		collector.assert_count(5)


# 10 recorders all fire for same signal
func test_10_recorders_all_fire_for_same_signal() -> void:
	var parents: Array = []
	for i in range(10):
		var parent := add_recorder({
			trigger_signal = "did_something",
			fact_key = "recorder.%d.count" % i,
			value = true,
			record_mode = CompanionFactory.RecordMode.ONCE,
		})
		parents.append(parent)

	# Emit the signal on each parent — all recorders must capture it
	for i in range(10):
		var parent: Node = parents[i]
		parent.emit_signal("did_something")

	# Each recorder must have stored its corresponding fact
	for i in range(10):
		assert_fact("recorder.%d.count" % i, true)


# Companion nodes survive rapid state changes (20 changes in sequence)
func test_companion_nodes_survive_rapid_state_changes() -> void:
	var target := add_gate("rapid.flag")
	var reactor := add_reactor({watch_pattern = "rapid.*"})
	var reactor_events := collect_signal(reactor, "fact_matched")

	# Alternate the condition true/false 20 times
	for i in range(20):
		_chronicle.set_fact("rapid.flag", i % 2 == 0)

	# After 20 alternations, the final value should be false (i=19 is odd => false)
	assert_fact("rapid.flag", false)
	assert_gate_closed(target)

	# Reactor must have fired for each of the 20 changes
	reactor_events.assert_count(20)


# Large state with companions — serialize/deserialize all still work
func test_large_state_with_companions_serialize_deserialize_works() -> void:
	# Set up 5 gates and load state into Chronicle
	var targets: Array = []
	for i in range(5):
		var target := add_gate("persist.cond.%d" % i)
		targets.append(target)

	# Populate 100 facts including the 5 gate conditions
	for i in range(100):
		_chronicle.set_fact("persist.data.%d" % i, i * 7)
	for i in range(5):
		_chronicle.set_fact("persist.cond.%d" % i, true)

	# All gates must be open
	for i in range(5):
		assert_gate_open(targets[i])

	# Serialize and deserialize
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok, "deserialize returned true")

	# All 100 data facts must survive the roundtrip
	for i in range(100):
		assert_fact("persist.data.%d" % i, i * 7)

	# All 5 gate conditions must survive the roundtrip
	for i in range(5):
		assert_fact("persist.cond.%d" % i, true)

	# All gates must still be open after deserialization
	for i in range(5):
		assert_gate_open(targets[i])
