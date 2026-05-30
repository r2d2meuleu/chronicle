extends ChronicleTestSuite


# set_facts writes all values to store
func test_set_facts_writes_all() -> void:
	_chronicle.set_facts({
		"player.gold": 100,
		"player.hp": 50,
		"player.name": "Hero",
	})
	assert_fact("player.gold", 100)
	assert_fact("player.hp", 50)
	assert_fact("player.name", "Hero")


# set_facts with empty dictionary is a no-op
func test_set_facts_empty_dict_noop() -> void:
	var events := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_facts({})
	events.assert_count(0)


# fact_changed fires per-key during batch
func test_fact_changed_fires_per_key() -> void:
	var events := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_facts({"a.x": 1, "a.y": 2, "a.z": 3})
	events.assert_count(3)
	events.assert_event(0, "a.x", 1, null)
	events.assert_event(1, "a.y", 2, null)
	events.assert_event(2, "a.z", 3, null)


# (removed — bulk_changed signal no longer exists)


# empty batch is a no-op (no fact_changed)
func test_empty_batch_no_fact_changed() -> void:
	var events := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_facts({})
	events.assert_count(0)


# Watchers fire with consistent state
func test_watchers_see_consistent_state() -> void:
	var gold_when_quest_fires: Array = []
	_chronicle.watch("quest.done", func(_k: String, _v: Variant, _o: Variant) -> void:
		gold_when_quest_fires.append(_chronicle.get_fact("player.gold"))
	)
	_chronicle.set_facts({"quest.done": true, "player.gold": 500})
	assert_eq(gold_when_quest_fires.size(), 1)
	assert_eq(gold_when_quest_fires[0], 500, "gold is 500 when quest.done watcher fires")


# Single-key batch behaves like set_fact
func test_single_key_batch() -> void:
	var events := watch_events("player.gold")
	_chronicle.set_facts({"player.gold": 42})
	events.assert_count(1)
	events.assert_event(0, "player.gold", 42, null)
	assert_fact("player.gold", 42)


# null value erases the key
func test_null_erases_key() -> void:
	_chronicle.set_fact("player.buff", "fire_resist")
	_chronicle.set_facts({"player.buff": null})
	assert_no_fact("player.buff")


# Mixed set + erase in one batch
func test_mixed_set_and_erase() -> void:
	_chronicle.set_fact("old.key", 1)
	_chronicle.set_facts({
		"new.key": 42,
		"old.key": null,
	})
	assert_fact("new.key", 42)
	assert_no_fact("old.key")


# erase_facts convenience method
func test_erase_facts() -> void:
	_chronicle.set_fact("a.x", 1)
	_chronicle.set_fact("a.y", 2)
	_chronicle.set_fact("a.z", 3)
	_chronicle.erase_facts(["a.x", "a.z"] as Array[String])
	assert_no_fact("a.x")
	assert_fact("a.y", 2)
	assert_no_fact("a.z")


# erase_facts with empty array is a no-op
func test_erase_facts_empty_noop() -> void:
	var events := collect_signal(_chronicle, "fact_changed")
	_chronicle.erase_facts([] as Array[String])
	events.assert_count(0)


# erase non-existent key silently skips
func test_erase_nonexistent_key_skips() -> void:
	_chronicle.set_facts({"a.x": 1, "nonexistent.key": null})
	assert_fact("a.x", 1)
	assert_no_fact("nonexistent.key")


# Transient flag applies to all batch entries
func test_transient_batch() -> void:
	_chronicle.set_facts({"t.a": 1, "t.b": 2}, true, 0.0)
	assert_fact("t.a", 1)
	assert_fact("t.b", 2)
	var data: Dictionary = _chronicle.serialize()
	assert_does_not_have(data["facts"], "t.a", "transient key excluded from serialize")
	assert_does_not_have(data["facts"], "t.b", "transient key excluded from serialize")


# Invalid key skipped, valid keys applied (partial validation)
func test_partial_validation_invalid_key() -> void:
	_chronicle.set_facts({
		"good.key": 42,
		"bad*key": 99,
		"another.good": 7,
	})
	assert_fact("good.key", 42)
	assert_no_fact("bad*key")
	assert_fact("another.good", 7)


# Invalid value type skipped, valid entries applied
func test_partial_validation_invalid_type() -> void:
	var bad_node: Node = autofree(Node.new())
	_chronicle.set_facts({
		"good.key": 42,
		"bad.type": bad_node,
		"another.good": 7,
	})
	assert_fact("good.key", 42)
	assert_no_fact("bad.type")
	assert_fact("another.good", 7)


# Timeline entries are per-key with sequential ticks
func test_timeline_per_key_entries() -> void:
	_chronicle.set_facts({"t.a": 1, "t.b": 2, "t.c": 3})
	assert_history("t.a", [1])
	assert_history("t.b", [2])
	assert_history("t.c", [3])


# All batch entries share same game_clock time
func test_batch_entries_same_time() -> void:
	_chronicle.set_game_time(5.0)
	_chronicle.set_facts({"t.a": 1, "t.b": 2})
	var all: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	var times: Array = []
	for entry: Dictionary in all:
		times.append(entry.time)
	assert_eq(times[times.size() - 1], 5.0)
	assert_eq(times[times.size() - 2], 5.0)


# Gate re-evaluates once with consistent state (not N times)
func test_gate_consistent_state() -> void:
	var parent := add_node_2d("GateTarget")
	var gate: Node = CompanionFactory.make_gate({
		condition = "quest.done AND player.gold >= 100",
	})
	parent.add_child(gate)
	autoqfree(gate)

	assert_gate_closed(parent)

	_chronicle.set_facts({"quest.done": true, "player.gold": 500})
	assert_gate_open(parent)


# Gate does NOT open with partial batch that doesn't satisfy condition
func test_gate_partial_batch() -> void:
	var parent := add_node_2d("GateTarget2")
	var gate: Node = CompanionFactory.make_gate({
		condition = "quest.done AND player.gold >= 100",
	})
	parent.add_child(gate)
	autoqfree(gate)

	_chronicle.set_facts({"quest.done": true, "player.gold": 50})
	assert_gate_closed(parent)


# Reactor fires per-key for matching pattern in batch
func test_reactor_fires_per_key() -> void:
	var parent := add_node("ReactorParent")
	var reactor: Node = CompanionFactory.make_reactor({
		watch_pattern = "quest.*",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	parent.add_child(reactor)
	autoqfree(reactor)

	var events := collect_signal(reactor, "fact_matched")
	_chronicle.set_facts({"quest.a": 1, "quest.b": 2, "quest.c": 3})
	events.assert_count(3)


# One-shot reactor fires once during batch
func test_one_shot_reactor_fires_once() -> void:
	var parent := add_node("OneShotParent")
	var reactor: Node = CompanionFactory.make_reactor({
		watch_pattern = "quest.*",
		react_to = CompanionFactory.ReactTo.ANY,
		one_shot = true,
	})
	parent.add_child(reactor)
	autoqfree(reactor)

	var events := collect_signal(reactor, "fact_matched")
	_chronicle.set_facts({"quest.a": 1, "quest.b": 2, "quest.c": 3})
	events.assert_count(1)
	events.assert_event(0, "quest.a", 1)


# watch_once fires once during batch with multiple matching keys
func test_watch_once_fires_once_in_batch() -> void:
	var events := watch_once_events("player.*")
	_chronicle.set_facts({"player.gold": 100, "player.hp": 50, "player.name": "Hero"})
	events.assert_count(1)
	events.assert_event(0, "player.gold")


# Exact watcher on two keys fires for both
func test_exact_watcher_two_keys_batch() -> void:
	var events := watch_events(["player.gold", "player.hp"])
	_chronicle.set_facts({"player.gold": 100, "player.hp": 50})
	events.assert_count(2)
	events.assert_keys(["player.gold", "player.hp"])


# Glob watcher fires per matching key
func test_glob_watcher_per_key() -> void:
	var events := watch_events("player.*")
	_chronicle.set_facts({"player.gold": 100, "player.hp": 50, "enemy.hp": 999})
	events.assert_count(2)
	events.assert_keys(["player.gold", "player.hp"])


# Cascade: watcher calls set_fact during batch dispatch
func test_cascade_set_fact_during_dispatch() -> void:
	_chronicle.watch("a.x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("a.cascade", 999)
	)
	var cascade_events := watch_events("a.cascade")
	_chronicle.set_facts({"a.x": 1, "a.y": 2})
	assert_fact("a.x", 1)
	assert_fact("a.y", 2)
	assert_fact("a.cascade", 999)
	cascade_events.assert_count(1)


# Cascade overwrite: watcher overwrites a batch key
func test_cascade_overwrite_batch_key() -> void:
	_chronicle.watch("a.x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_fact("a.y", 999)
	)
	var y_events := watch_events("a.y")
	_chronicle.set_facts({"a.x": 1, "a.y": 2})
	assert_fact("a.x", 1)
	assert_fact("a.y", 999)
	# y_events should fire once from the cascade (value=999, old=2),
	# NOT a second stale dispatch from the batch
	y_events.assert_count(1)
	y_events.assert_event(0, "a.y", 999, 2)


# Nested set_facts from watcher
func test_nested_set_facts() -> void:
	_chronicle.watch("a.x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_facts({"b.inner1": 10, "b.inner2": 20})
	)
	var inner_events := watch_events("b.*")
	_chronicle.set_facts({"a.x": 1, "a.y": 2})
	assert_fact("a.x", 1)
	assert_fact("a.y", 2)
	assert_fact("b.inner1", 10)
	assert_fact("b.inner2", 20)
	inner_events.assert_count(2)


# Nested set_facts overwrites outer pending key
func test_nested_set_facts_overwrites_outer() -> void:
	_chronicle.watch("a.x", func(_k: String, _v: Variant, _o: Variant) -> void:
		_chronicle.set_facts({"a.y": 999})
	)
	var y_events := watch_events("a.y")
	_chronicle.set_facts({"a.x": 1, "a.y": 2})
	assert_fact("a.y", 999)
	# y watcher fires once from inner set_facts, outer dispatch skipped
	y_events.assert_count(1)
	y_events.assert_event(0, "a.y", 999, 2)


# set_facts at cascade depth >= MAX defers entire batch
func test_batch_deferred_at_max_depth() -> void:
	# Build chain to reach depth 7
	for i in range(1, 8):
		var current_level: int = i
		var next_key: String = "chain.%d" % (current_level + 1)
		_chronicle.watch("chain.%d" % current_level, func(_k: String, _v: Variant, _o: Variant) -> void:
			if current_level == 7:
				_chronicle.set_facts({"deferred.a": 100, "deferred.b": 200})
			else:
				_chronicle.set_fact(next_key, current_level + 1)
		)

	_chronicle.set_fact("chain.1", 1)

	# The set_facts at depth 7 triggers at depth 8 (the cascade watcher for chain.7
	# fires at depth 7, and the watcher increments depth to 8 before calling set_facts).
	# At depth >= MAX_CASCADE_DEPTH, set_facts defers the batch.
	# After all cascades unwind, deferred queue drains and facts appear.
	assert_true(_chronicle.has_fact("deferred.a"), "deferred.a applied after queue drain")
	assert_eq(_chronicle.get_fact("deferred.a"), 100)
	assert_true(_chronicle.has_fact("deferred.b"), "deferred.b applied after queue drain")
	assert_eq(_chronicle.get_fact("deferred.b"), 200)


# Deep-copy isolation on batch write
func test_batch_deep_copy_isolation() -> void:
	var data: Dictionary = {"hp": 100}
	_chronicle.set_facts({"player.stats": data})
	data["hp"] = 0
	assert_fact("player.stats", {"hp": 100})


# Bulk-written facts survive serialize/deserialize roundtrip
func test_serialize_roundtrip() -> void:
	_chronicle.set_facts({"s.gold": 100, "s.name": "Hero", "s.alive": true})

	var c2 := serialize_into_new()
	assert_eq(c2.get_fact("s.gold"), 100)
	assert_eq(c2.get_fact("s.name"), "Hero")
	# Deliberate assert_eq(..., true): verifies the bool survives the roundtrip as a
	# real bool, not as a truthy non-bool.
	assert_eq(c2.get_fact("s.alive"), true, "s.alive survives roundtrip as bool true")


# Erase via batch shows in timeline as null value
func test_erase_in_timeline() -> void:
	_chronicle.set_fact("t.key", 42)
	_chronicle.set_facts({"t.key": null})
	assert_history("t.key", [42, null])


# Batch with all invalid keys is a no-op (no signals)
func test_all_invalid_keys_noop() -> void:
	var events := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_facts({"bad*key": 1, "": 2, "also*bad": 3})
	events.assert_count(0)


# Batch updates existing values (old_value correct)
func test_batch_updates_existing() -> void:
	_chronicle.set_fact("u.key", 10)
	var events := watch_events("u.key")
	_chronicle.set_facts({"u.key": 20})
	events.assert_count(1)
	events.assert_event(0, "u.key", 20, 10)


# Entity index updated correctly after batch
func test_entity_index_after_batch() -> void:
	_chronicle.set_facts({"player.a": 1, "player.b": 2, "enemy.c": 3})
	var player_keys: Array[String] = _chronicle.get_fact_keys("player.*")
	var enemy_keys: Array[String] = _chronicle.get_fact_keys("enemy.*")
	assert_eq(player_keys.size(), 2)
	assert_eq(enemy_keys.size(), 1)
	assert_has(player_keys, "player.a")
	assert_has(player_keys, "player.b")
	assert_has(enemy_keys, "enemy.c")


# Erase via batch cleans entity index
func test_erase_cleans_entity_index() -> void:
	_chronicle.set_facts({"e.a": 1, "e.b": 2})
	assert_eq(_chronicle.get_fact_keys("e.*").size(), 2)
	_chronicle.set_facts({"e.a": null, "e.b": null})
	assert_eq(_chronicle.get_fact_keys("e.*").size(), 0)


# Quest completion — bulk write with watchers on multiple patterns
func test_quest_completion_bulk_with_watchers() -> void:
	# Set up: watcher on "quest.*", watcher on "player.gold", gate on compound condition
	var quest_events := watch_events("quest.*")
	var gold_events := watch_events("player.gold")

	var parent := add_node_2d("QuestGateTarget")
	var gate: Node = CompanionFactory.make_gate({
		condition = "quest.dragon.status == \"complete\" AND player.gold >= 400",
	})
	parent.add_child(gate)
	autoqfree(gate)

	assert_gate_closed(parent)

	# Action: atomic bulk write
	_chronicle.set_facts({
		"quest.dragon.status": "complete",
		"player.gold": 500,
		"player.xp": 200,
		"npc.grateful": true,
	})

	# Verify: quest watcher fires once (for quest.dragon.status)
	quest_events.assert_count(1)
	quest_events.assert_event(0, "quest.dragon.status", "complete", null)

	# Verify: gold watcher fires once
	gold_events.assert_count(1)
	gold_events.assert_event(0, "player.gold", 500, null)

	# Verify: gate opens (both conditions met atomically)
	assert_gate_open(parent)

	# Verify: all facts present
	assert_fact("quest.dragon.status", "complete")
	assert_fact("player.gold", 500)
	assert_fact("player.xp", 200)
	assert_fact("npc.grateful", true)


# Level transition — bulk erase + set in one batch
func test_level_transition_bulk_erase_and_set() -> void:
	# Set up: level1 facts
	_chronicle.set_fact("level1.chest", "gold")
	_chronicle.set_fact("level1.enemies", 5)

	var level_events := watch_events(["level1.*", "level2.*"])

	# Action: erase level1 facts + set level2 facts in one batch
	_chronicle.set_facts({
		"level1.chest": null,
		"level1.enemies": null,
		"level2.start": true,
		"level2.weather": "rain",
	})

	# Verify: level1 facts erased
	assert_no_fact("level1.chest")
	assert_no_fact("level1.enemies")

	# Verify: level2 facts set
	assert_fact("level2.start", true)
	assert_fact("level2.weather", "rain")

	# Verify: watcher fired for each change (2 erases + 2 creates = 4)
	level_events.assert_count(4)

	# Verify: entity index correct
	assert_eq(_chronicle.get_fact_keys("level1.*").size(), 0)
	assert_eq(_chronicle.get_fact_keys("level2.*").size(), 2)


# Combat resolution — bulk write with reactor and one-shot reactor
func test_combat_resolution_with_reactors() -> void:
	# Set up: reactor on "combat.*" (ANY)
	var combat_parent := add_node("CombatReactorParent")
	var reactor_any: Node = CompanionFactory.make_reactor({
		watch_pattern = "combat.*",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	combat_parent.add_child(reactor_any)
	autoqfree(reactor_any)

	var any_events := collect_signal(reactor_any, "fact_matched")

	# Set up: one-shot reactor on "combat.*" (CREATION)
	var oneshot_parent := add_node("OneShotReactorParent")
	var reactor_oneshot: Node = CompanionFactory.make_reactor({
		watch_pattern = "combat.*",
		react_to = CompanionFactory.ReactTo.CREATION,
		one_shot = true,
	})
	oneshot_parent.add_child(reactor_oneshot)
	autoqfree(reactor_oneshot)

	var oneshot_events := collect_signal(reactor_oneshot, "fact_matched")

	# Action: bulk write combat results
	_chronicle.set_facts({
		"combat.result": "victory",
		"combat.damage": 50,
		"combat.loot": "sword",
	})

	# Verify: ANY reactor fires 3 times
	any_events.assert_count(3)

	# Verify: one-shot CREATION reactor fires once (first key, then spent)
	oneshot_events.assert_count(1)
	oneshot_events.assert_event(0, "combat.result", "victory")

	# Verify: all facts present
	assert_fact("combat.result", "victory")
	assert_fact("combat.damage", 50)
	assert_fact("combat.loot", "sword")


# Batch followed by individual write — verifies no state leakage
func test_batch_then_individual_no_leakage() -> void:
	var z_events := watch_events("a.z")
	var all_events := collect_signal(_chronicle, "fact_changed")

	# Action: batch write, then individual write
	_chronicle.set_facts({"a.x": 1, "a.y": 2})
	_chronicle.set_fact("a.z", 3)

	# Verify: all 3 facts present
	assert_fact("a.x", 1)
	assert_fact("a.y", 2)
	assert_fact("a.z", 3)

	# Verify: individual write's watcher fires normally
	z_events.assert_count(1)
	z_events.assert_event(0, "a.z", 3, null)

	# Verify: fact_changed fired 3 times total (2 batch + 1 individual)
	all_events.assert_count(3)


# Multiple sequential batches
func test_multiple_sequential_batches() -> void:
	var all_events := collect_signal(_chronicle, "fact_changed")

	# Action: three sequential batches
	_chronicle.set_facts({"batch1.a": 1})
	_chronicle.set_facts({"batch2.b": 2})
	_chronicle.set_facts({"batch3.c": 3})

	# Verify: all 3 facts present
	assert_fact("batch1.a", 1)
	assert_fact("batch2.b", 2)
	assert_fact("batch3.c", 3)

	# Verify: fact_changed fired 3 times (once per fact)
	all_events.assert_count(3)


# set_facts with explicit lifetime=0 clears expiry on existing expiring fact
func test_set_facts_lifetime_zero_clears_expiry() -> void:
	_chronicle.set_fact("timed.fact", "val", false, 10.0)
	assert_gt(_chronicle.get_expiry_remaining("timed.fact"), 0.0, "expiry is active before clear")
	# Must pass lifetime=0.0 explicitly — default is KEEP_LIFETIME which preserves expiry
	_chronicle.set_facts({"timed.fact": "updated"}, false, 0.0)
	assert_eq(_chronicle.get_expiry_remaining("timed.fact"), Chronicle.EXPIRY_NONE)


# set_facts returns the number of facts written
func test_set_facts_returns_written_count() -> void:
	assert_eq(_chronicle.set_facts({"sf.a": 1, "sf.b": 2, "sf.c": 3}), 3,
		"set_facts should return the number of facts written")
	assert_eq(_chronicle.set_facts({}), 0, "set_facts({}) writes nothing and returns 0")
