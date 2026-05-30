extends ChronicleTestSuite


# Reactor with "player.*" pattern fires on set_fact("player.gold", 1)
func test_pattern_match_fires_on_matching_key() -> void:
	var reactor := add_reactor({watch_pattern = "player.*"})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 1)
	events.assert_count(1)
	events.assert_event(0, "player.gold", 1)


# Reactor does NOT fire for non-matching key
func test_no_fire_on_non_matching_key() -> void:
	var reactor := add_reactor({watch_pattern = "player.*"})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("npc.hp", 50)
	events.assert_count(0)


# react_to = CREATION only fires on first write (old_value is null)
func test_creation_fires_on_first_write() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		react_to = CompanionFactory.ReactTo.CREATION,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 10)
	events.assert_count(1)
	events.assert_event(0, "player.gold", 10)


# react_to = CREATION does NOT fire on updates (same key set twice)
func test_creation_does_not_fire_on_update() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		react_to = CompanionFactory.ReactTo.CREATION,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 10)
	events.assert_count(1)

	_chronicle.set_fact("player.gold", 20)
	events.assert_count(1)


# react_to = CHANGE fires when value changes on existing key
func test_change_fires_on_value_change() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		react_to = CompanionFactory.ReactTo.CHANGE,
	})
	var events := collect_signal(reactor, "fact_matched")

	# First write (creation) — should NOT fire for CHANGE
	_chronicle.set_fact("player.gold", 10)
	events.assert_count(0)

	# Second write (change) — should fire
	_chronicle.set_fact("player.gold", 20)
	events.assert_count(1)
	events.assert_event(0, "player.gold", 20)


# react_to = CHANGE does NOT fire on creation (first write)
func test_change_does_not_fire_on_creation() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		react_to = CompanionFactory.ReactTo.CHANGE,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.hp", 100)
	events.assert_count(0)

	# Also verify: setting to same value does NOT fire
	_chronicle.set_fact("player.hp", 100)
	events.assert_count(0)


# react_to = ANY fires on both creation and changes
func test_any_fires_on_both() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 10)
	events.assert_count(1)

	_chronicle.set_fact("player.gold", 20)
	events.assert_count(2)


# one_shot = true disconnects after first match
func test_one_shot_disconnects() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		one_shot = true,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 10)
	events.assert_count(1)

	_chronicle.set_fact("player.gold", 20)
	events.assert_count(1)

	_chronicle.set_fact("player.hp", 100)
	events.assert_count(1)


# target_method called on parent if it exists
func test_target_method_called() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		target_method = "on_fact",
	})

	_chronicle.set_fact("player.gold", 42)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "player.gold", 42, null)


# Missing target_method -> push_warning (no crash)
func test_missing_target_method_warning() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		target_method = "nonexistent_method",
	})
	var events := collect_signal(reactor, "fact_matched")

	# Should not crash, should still emit signal, just warn about missing method
	_chronicle.set_fact("player.gold", 1)
	events.assert_count(1)


# fact_matched signal emitted with correct key/value
func test_fact_matched_signal() -> void:
	var reactor := add_reactor({watch_pattern = "player.*"})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("player.hp", 50)
	events.assert_count(2)
	events.assert_event(0, "player.gold", 100)
	events.assert_event(1, "player.hp", 50)


# Empty watch_pattern -> configuration warning
func test_empty_pattern_warning() -> void:
	var reactor: Node = autofree(CompanionFactory.make_reactor({watch_pattern = ""}))
	assert_has_warning(reactor, "watch_pattern")


# Reactor _exit_tree unwatches from Chronicle
func test_exit_tree_unwatches() -> void:
	var parent := add_node()
	var reactor := CompanionFactory.make_reactor({watch_pattern = "player.*"})
	parent.add_child(reactor)
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 1)
	events.assert_count(1)

	parent.remove_child(reactor)
	reactor.queue_free()

	_chronicle.set_fact("player.gold", 2)
	events.assert_count(1)


# One-shot CREATION reactor fires on state reset (deserialize)
func test_one_shot_creation_reactor_fires_on_state_reset() -> void:
	_chronicle.set_fact("quest.started", true)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	var reactor := add_reactor({
		watch_pattern = "quest.*",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.CREATION,
		one_shot = true,
	})
	_chronicle.deserialize(data)
	assert_spy_calls(reactor, 1)


# Reactor survives clear() — re-registers its watch so it can react again
func test_reactor_survives_clear() -> void:
	var reactor := add_reactor({watch_pattern = "x", react_to = CompanionFactory.ReactTo.ANY})
	await get_tree().process_frame
	_chronicle.set_fact("x", 1)
	var spy := reactor.get_parent()
	assert_spy_calls(reactor, 1)
	spy.calls.clear()
	_chronicle.clear()
	_chronicle.set_fact("x", 2)
	assert_spy_calls(reactor, 1)


# CHANGE reactor does NOT fire on state_reset (no old value to compare)
func test_reactor_change_mode_no_fire_on_state_reset() -> void:
	var reactor := add_reactor({watch_pattern = "quest.*", react_to = CompanionFactory.ReactTo.CHANGE})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("quest.started", true)
	var save_data: Dictionary = _chronicle.serialize()
	_chronicle.clear()
	events.clear()

	_chronicle.deserialize(save_data)
	events.assert_count(0)


# set_filter blocks matching
func test_set_filter_blocks() -> void:
	var reactor := add_reactor({watch_pattern = "score", react_to = CompanionFactory.ReactTo.ANY})
	reactor.set_filter(func(_k, v, _o): return v > 50)
	_chronicle.set_fact("score", 10)
	_chronicle.set_fact("score", 100)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, EventCollector.SKIP, 100)


# ── Merged from test/audit/test_r16_a10_nodes.gd — Reactor bug regression tests ──

# CHANGE mode drops null transition (erase) — use ERASURE for deletions
func test_reactor_change_drops_null_transition() -> void:
	var reactor := add_reactor({
		watch_pattern = "score",
		react_to = CompanionFactory.ReactTo.CHANGE,
	})

	_chronicle.set_fact("score", 10)
	# Creation — CHANGE should not fire
	assert_spy_calls(reactor, 0)

	# Change value → should fire
	_chronicle.set_fact("score", 20)
	assert_spy_calls(reactor, 1)

	# Erase (value becomes null) — CHANGE mode filters this out on line 104
	# because `value == null` is checked. This means CHANGE never sees erasures.
	# If this is intentional (ERASURE handles it), this test documents the behavior.
	_chronicle.erase_fact("score")
	# CHANGE mode has `if value == null: return` — so erase is filtered.
	# This is the documented behavior: use ERASURE for deletions.
	assert_spy_calls(reactor, 1)


# One-shot reactor fires exactly once during state_reset replay with multiple matching facts
func test_one_shot_reactor_state_reset_replay() -> void:
	# Set up two facts before reactor exists
	_chronicle.set_fact("item.sword", true)
	_chronicle.set_fact("item.shield", true)
	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	# Create one-shot CREATION reactor
	var reactor := add_reactor({
		watch_pattern = "item.*",
		react_to = CompanionFactory.ReactTo.CREATION,
		one_shot = true,
	})
	var spy: Node = reactor.get_parent()

	# Deserialize triggers state_reset → replay existing facts
	_chronicle.deserialize(data)

	# One-shot should fire exactly once despite two matching facts
	assert_spy_calls(reactor, 1)

	# After one-shot fired, new facts should NOT trigger
	spy.calls.clear()
	_chronicle.set_fact("item.potion", true)
	assert_spy_calls(reactor, 0)


# Reactor fires both its fact_matched signal and its target_method (each once)
func test_reactor_signal_and_method_both_fire() -> void:
	var parent: Node = autoqfree(Node.new())
	parent.set_script(preload("res://test/support/chronicle_spy_node.gd"))
	get_tree().root.add_child(parent)

	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "order.test",
		target_method = "on_fact",
	})
	parent.add_child(reactor)

	var signal_events := collect_signal(reactor, "fact_matched")
	_chronicle.set_fact("order.test", 42)

	# Both paths fire exactly once for the single matching write.
	signal_events.assert_count(1)
	signal_events.assert_event(0, "order.test", 42)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "order.test", 42, null)


# ── Merged from test/audit/test_r17_a10_nodes.gd — Reactor audit tests ──

# One-shot reactor re-arms after state_reset (world is new)
func test_one_shot_reactor_rearms_after_state_reset() -> void:
	var reactor := add_reactor({
		watch_pattern = "item.sword",
		react_to = CompanionFactory.ReactTo.CREATION,
		one_shot = true,
	})
	var spy: Node = reactor.get_parent()

	# Fire the one-shot
	_chronicle.set_fact("item.sword", true)
	assert_spy_calls(reactor, 1)

	# A second write should NOT fire
	_chronicle.erase_fact("item.sword")
	_chronicle.set_fact("item.sword", true)
	assert_spy_calls(reactor, 1)

	# After state_reset, one-shot should be re-armed
	_chronicle.clear()
	spy.calls.clear()
	_chronicle.set_fact("item.sword", true)
	assert_spy_calls(reactor, 1)


# set_filter with CREATION mode suppresses events that fail filter predicate
func test_set_filter_with_creation_mode() -> void:
	var reactor := add_reactor({
		watch_pattern = "score.*",
		react_to = CompanionFactory.ReactTo.CREATION,
	})
	# Only pass facts whose initial value is > 0
	reactor.set_filter(func(_k: String, v: Variant, _o: Variant) -> bool: return v > 0)

	_chronicle.set_fact("score.player", 0)   # CREATION but filtered out (0 not > 0)
	assert_spy_calls(reactor, 0)

	_chronicle.set_fact("score.enemy", 10)   # CREATION and passes filter
	assert_spy_calls(reactor, 1)


# ── R15 bug regression ───────────────────────


# Reactor still fires after clear() re-registers its watch
func test_reactor_fires_after_clear_and_new_fact() -> void:
	# Set a fact, then clear (triggers state_reset)
	_chronicle.set_fact("data.x", 10)

	var reactor := add_reactor({
		watch_pattern = "data.*",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
		one_shot = false,
	})
	var spy: Node = reactor.get_parent()

	spy.calls.clear()
	_chronicle.set_fact("data.x", 20)   # change → fires (old 10)
	_chronicle.clear()                  # state destroyed; nothing to replay
	_chronicle.set_fact("data.x", 30)   # creation after clear → fires (old null)

	# Exactly the two live writes fire; clear() replays nothing.
	assert_spy_calls(reactor, 2)
	assert_spy_call(reactor, 0, "data.x", 20, 10)
	assert_spy_call(reactor, 1, "data.x", 30, null)


# react_to = ERASURE fires ONLY when a fact is erased (value null), not on
# creation or change.
func test_erasure_fires_only_on_erase() -> void:
	var reactor := add_reactor({
		watch_pattern = "item.*",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ERASURE,
	})

	# Creation — must NOT fire.
	_chronicle.set_fact("item.sword", 1)
	assert_spy_calls(reactor, 0)

	# Change — must NOT fire.
	_chronicle.set_fact("item.sword", 2)
	assert_spy_calls(reactor, 0)

	# Erasure — MUST fire, with value null.
	_chronicle.erase_fact("item.sword")
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "item.sword", null)


# reset() re-arms a one_shot reactor so it can fire again after firing once
func test_reset_rearms_one_shot_reactor() -> void:
	var reactor := add_reactor({
		watch_pattern = "player.*",
		one_shot = true,
	})
	var events := collect_signal(reactor, "fact_matched")

	_chronicle.set_fact("player.gold", 10)
	events.assert_count(1)

	# Already disarmed — a second match does NOT fire.
	_chronicle.set_fact("player.hp", 5)
	events.assert_count(1)

	# reset() re-arms; the next match fires again.
	reactor.reset()
	_chronicle.set_fact("player.mana", 3)
	events.assert_count(2)
