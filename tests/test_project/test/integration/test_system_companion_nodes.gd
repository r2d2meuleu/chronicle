extends ChronicleTestSuite

## System tests: all 3 companion nodes (Recorder, Gate, Reactor) working together
## in realistic game scenarios.


# ── Scenario 1: Boss kill -> door opens ──
# A boss Node2D has a "died" signal. A ChronicleRecorder listens for it and
# records "boss.defeated" (ONCE mode). A door Node2D has a ChronicleGate that
# shows the door when "boss.defeated" is true. Emit the signal, verify the
# door becomes visible and the fact is recorded.
func test_scenario_1_boss_kill_door_opens() -> void:
	# -- Boss node with "died" signal --
	var boss := add_node_2d()
	boss.name = "Boss"
	boss.add_user_signal("died")

	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "died",
		fact_key = "boss.defeated",
		value = true,
		record_mode = CompanionFactory.RecordMode.ONCE,
	})
	boss.add_child(recorder)

	# -- Door node with gate --
	var door := add_node_2d()
	door.name = "Door"

	var gate := CompanionFactory.make_gate({
		condition = "boss.defeated",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	door.add_child(gate)

	# Before boss dies: door should be hidden (condition false)
	assert_gate_closed(door)
	assert_no_fact("boss.defeated")

	# Boss dies
	boss.emit_signal("died")

	# After boss dies: fact recorded, door visible
	assert_fact("boss.defeated", true)
	assert_gate_open(door)

	# ONCE mode: second emit should not change anything (already recorded)
	boss.emit_signal("died")
	assert_fact("boss.defeated", true)


# ── Scenario 2: Kill counter with reactor ──
# A spawner node emits "enemy_died". A ChronicleRecorder in INCREMENT mode
# counts kills into "player.kills". An NPC node has a ChronicleReactor watching
# "player.*" that calls _on_kills(key, value) on the NPC. Emit enemy_died 3
# times, verify player.kills == 3 and the NPC method was called 3 times.
func test_scenario_2_kill_counter_with_reactor() -> void:
	# -- Spawner with recorder --
	var spawner := add_signaled_node("enemy_died")
	spawner.name = "Spawner"

	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "enemy_died",
		fact_key = "player.kills",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	})
	spawner.add_child(recorder)

	# -- NPC with reactor --
	var npc := add_node()
	npc.name = "NPC"
	npc.set_script(preload("res://test/support/chronicle_spy_node.gd"))

	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "player.*",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	npc.add_child(reactor)

	# Emit enemy_died 3 times
	spawner.emit_signal("enemy_died")
	spawner.emit_signal("enemy_died")
	spawner.emit_signal("enemy_died")

	# Verify kill count
	assert_fact("player.kills", 3)

	# Verify NPC method was called 3 times
	assert_spy_calls(reactor, 3)

	# Verify each call received incrementing values
	assert_spy_call(reactor, 0, "player.kills", 1)
	assert_spy_call(reactor, 1, EventCollector.SKIP, 2)
	assert_spy_call(reactor, 2, EventCollector.SKIP, 3)


# ── Scenario 3: Gate with compound condition ──
# A gate requires "player.gold >= 100 AND quest.done". We progressively set
# facts and verify the gate opens only when BOTH conditions are met.
func test_scenario_3_gate_compound_condition() -> void:
	# Set initial gold
	_chronicle.set_fact("player.gold", 50)

	# -- Gate target --
	var chest := add_node_2d()
	chest.name = "Chest"

	var gate := CompanionFactory.make_gate({
		condition = "player.gold >= 100 AND quest.done",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	chest.add_child(gate)

	# gold=50, quest.done missing -> both fail -> hidden
	assert_gate_closed(chest)

	# Set quest.done but gold still < 100
	_chronicle.set_fact("quest.done", true)
	assert_gate_closed(chest)

	# Set gold to 150 -> both conditions met -> visible
	_chronicle.set_fact("player.gold", 150)
	assert_gate_open(chest)

	# Drop gold below threshold -> gate closes again
	_chronicle.set_fact("player.gold", 50)
	assert_gate_closed(chest)

	# Raise gold back, unmark quest -> still closed
	_chronicle.set_fact("player.gold", 200)
	assert_gate_open(chest)
	_chronicle.set_fact("quest.done", false)
	assert_gate_closed(chest)


# ── Scenario 4: One-shot reactor ──
# A reactor with one_shot=true fires on the first matching fact set, then
# ignores all subsequent matches.
func test_scenario_4_one_shot_reactor() -> void:
	var npc := add_node()
	npc.name = "Narrator"
	npc.set_script(preload("res://test/support/chronicle_spy_node.gd"))

	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "player.defeated.*",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
		one_shot = true,
	})
	npc.add_child(reactor)

	# Also track via signal for extra verification
	var signal_log := collect_signal(reactor, "fact_matched")

	# First fact: reactor fires
	_chronicle.set_fact("player.defeated.boss_a", true)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "player.defeated.boss_a")
	signal_log.assert_count(1)

	# Second fact: reactor does NOT fire (one_shot consumed)
	_chronicle.set_fact("player.defeated.boss_b", true)
	assert_spy_calls(reactor, 1)
	signal_log.assert_count(1)

	# Third fact: still consumed
	_chronicle.set_fact("player.defeated.boss_c", true)
	assert_spy_calls(reactor, 1)

	# Verify the reactor is spent: set another matching fact and confirm no new signal
	var extra_log := collect_signal(reactor, "fact_matched")
	_chronicle.set_fact("player.defeated.boss_d", true)
	extra_log.assert_count(0)


# ── Scenario 5: Serialize/deserialize with gates ──
# Set up facts and gates, serialize the state, then simulate a "game reload":
# remove gates, clear Chronicle, deserialize, re-add gates. Verify the gates
# re-evaluate to the correct state from the restored facts.
func test_scenario_5_serialize_deserialize_with_gates() -> void:
	# -- Phase A: Set up facts --
	_chronicle.set_fact("player.gold", 200)
	_chronicle.set_fact("quest.done", true)
	_chronicle.set_fact("boss.defeated", true)

	# -- Phase B: Create gates and verify they evaluate correctly --
	var door := add_node_2d()
	door.name = "Door"

	var gate_door := CompanionFactory.make_gate({
		condition = "boss.defeated",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	door.add_child(gate_door)

	var shop := add_node_2d()
	shop.name = "Shop"

	var gate_shop := CompanionFactory.make_gate({
		condition = "player.gold >= 100 AND quest.done",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	shop.add_child(gate_shop)

	assert_gate_open(door)
	assert_gate_open(shop)

	# -- Phase C: Serialize --
	var save_data: Dictionary = _chronicle.serialize()
	assert_has(save_data, "facts")
	assert_has(save_data, "version")

	# -- Phase D: Simulate game reload --
	# Remove old nodes from tree (simulates scene being freed on quit)
	# autofree() handles the actual freeing; remove from tree manually to simulate reload
	get_tree().root.remove_child(door)
	get_tree().root.remove_child(shop)

	# Clear Chronicle (simulates fresh start — this wipes all watchers too)
	_chronicle.clear()
	assert_no_fact("boss.defeated")

	# -- Phase E: Deserialize (restores facts) --
	var ok: bool = _chronicle.deserialize(save_data)
	assert_true(ok)
	assert_fact("boss.defeated", true)
	assert_fact("player.gold", 200)
	assert_fact("quest.done", true)

	# -- Phase F: Re-create scene (simulates loading scene after deserialize) --
	var door2 := add_node_2d()
	door2.name = "Door2"

	var gate_door2 := CompanionFactory.make_gate({
		condition = "boss.defeated",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	door2.add_child(gate_door2)

	var shop2 := add_node_2d()
	shop2.name = "Shop2"

	var gate_shop2 := CompanionFactory.make_gate({
		condition = "player.gold >= 100 AND quest.done",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	shop2.add_child(gate_shop2)

	# Gates should evaluate on _ready using restored facts
	assert_gate_open(door2)
	assert_gate_open(shop2)

	# -- Phase G: Verify gates are live (respond to new changes) --
	_chronicle.set_fact("boss.defeated", false)
	assert_gate_closed(door2)

	_chronicle.set_fact("boss.defeated", true)
	assert_gate_open(door2)


# ── Scenario 6: Quest completion with bulk ops ──
# A spawner emits "quest_complete". A recorder records "quest.reward_given" on
# that signal. The quest reward itself uses set_facts to atomically set multiple
# facts. A gate on a compound condition opens correctly with consistent state.
func test_scenario_6_quest_completion_with_bulk_ops() -> void:
	# -- Spawner with recorder --
	var spawner := add_signaled_node("quest_complete")
	spawner.name = "QuestSpawner"

	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "quest_complete",
		fact_key = "quest.reward_given",
		value = true,
		record_mode = CompanionFactory.RecordMode.ONCE,
	})
	spawner.add_child(recorder)

	# -- Reactor that atomically grants quest rewards via set_facts --
	var reward_reactor := CompanionFactory.make_reactor({
		watch_pattern = "quest.reward_given",
		react_to = CompanionFactory.ReactTo.CREATION,
	})
	var reward_parent := add_node("RewardReactor")
	reward_parent.add_child(reward_reactor)

	# When reward_given is recorded, grant rewards atomically
	var reward_events := collect_signal(reward_reactor, "fact_matched")
	reward_reactor.fact_matched.connect(func(_key: String, _value: Variant, _old_value: Variant) -> void:
		_chronicle.set_facts({
			"player.gold": 500,
			"player.xp": 1000,
			"quest.dragon.status": "complete",
			"inventory.dragon_scale": true,
		})
	)

	# -- Gate on compound condition (requires both gold and quest status) --
	var treasure_room := add_node_2d("TreasureRoom")
	var gate := CompanionFactory.make_gate({
		condition = "quest.dragon.status == \"complete\" AND player.gold >= 400",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	treasure_room.add_child(gate)

	# Before quest complete: gate closed
	assert_gate_closed(treasure_room)

	# Emit quest_complete -> recorder writes quest.reward_given -> reactor fires -> set_facts
	spawner.emit_signal("quest_complete")

	# Verify: recorder recorded the fact
	assert_fact("quest.reward_given", true)

	# Verify: reactor fired exactly once
	reward_events.assert_count(1)

	# Verify: all reward facts set atomically
	assert_fact("player.gold", 500)
	assert_fact("player.xp", 1000)
	assert_fact("quest.dragon.status", "complete")
	assert_fact("inventory.dragon_scale", true)

	# Verify: gate opened (compound condition met from consistent set_facts)
	assert_gate_open(treasure_room)

	# Second emit should not trigger again (recorder is ONCE, reactor is CREATION)
	spawner.emit_signal("quest_complete")
	reward_events.assert_count(1)


# ── Scenario 7: Bulk erase during level transition with gates ──
# Set level1 facts. A gate on "level1.door.unlocked" is open.
# Bulk erase level1 facts + set level2 facts. Gate on level1 closes,
# gate on level2 opens.
func test_scenario_7_bulk_erase_level_transition_with_gates() -> void:
	# -- Phase A: Set up level1 facts --
	_chronicle.set_fact("level1.door.unlocked", true)
	_chronicle.set_fact("level1.enemies", 3)
	_chronicle.set_fact("level1.chest.opened", true)

	# -- Gate on level1 condition --
	var level1_door := add_node_2d("Level1Door")
	var gate_l1 := CompanionFactory.make_gate({
		condition = "level1.door.unlocked",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	level1_door.add_child(gate_l1)

	# -- Gate on level2 condition --
	var level2_portal := add_node_2d("Level2Portal")
	var gate_l2 := CompanionFactory.make_gate({
		condition = "level2.started AND level2.weather == \"rain\"",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	level2_portal.add_child(gate_l2)

	# Before transition: level1 gate open, level2 gate closed
	assert_gate_open(level1_door)
	assert_gate_closed(level2_portal)

	# -- Phase B: Bulk erase level1 + set level2 atomically --
	_chronicle.set_facts({
		"level1.door.unlocked": null,
		"level1.enemies": null,
		"level1.chest.opened": null,
		"level2.started": true,
		"level2.weather": "rain",
	})

	# After transition: level1 gate closed, level2 gate open
	assert_gate_closed(level1_door)
	assert_gate_open(level2_portal)

	# Verify: level1 facts erased
	assert_no_fact("level1.door.unlocked")
	assert_no_fact("level1.enemies")
	assert_no_fact("level1.chest.opened")

	# Verify: level2 facts present
	assert_fact("level2.started", true)
	assert_fact("level2.weather", "rain")

	# Verify: entity index reflects the transition
	assert_eq(_chronicle.get_fact_keys("level1.*").size(), 0)
	assert_eq(_chronicle.get_fact_keys("level2.*").size(), 2)


# ── Scenario 8: Strategy game undo with rollback ──
# Player moves units (persistent facts). Player hits undo via rollback_steps.
# Gate on "player.moved" closes after rollback. Facts restored.
func test_scenario_8_strategy_game_undo() -> void:
	# -- Phase A: Player moves --
	set_time(1.0)
	_chronicle.set_fact("unit.a.x", 0)
	_chronicle.set_fact("unit.a.y", 0)
	set_time(2.0)
	_chronicle.set_fact("unit.a.x", 5)
	_chronicle.set_fact("unit.a.y", 3)
	set_time(3.0)
	_chronicle.set_fact("player.moved", true)

	# -- Gate shows "end turn" button when player has moved --
	var end_turn := add_node_2d("EndTurnButton")
	var gate := CompanionFactory.make_gate({
		condition = "player.moved",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	end_turn.add_child(gate)

	assert_gate_open(end_turn)
	assert_fact("unit.a.x", 5)

	# -- Phase B: Player hits undo (rollback last 3 entries: player.moved, y, x) --
	_chronicle.rollback_steps(3)

	# Gate should close (player.moved no longer exists)
	assert_gate_closed(end_turn)
	# Unit position restored
	assert_fact("unit.a.x", 0)
	assert_fact("unit.a.y", 0)
	assert_no_fact("player.moved")


# ── Scenario 9: Puzzle rewind with rollback_to ──
# Player places pieces (facts), then rollback_to rewinds to checkpoint.
# Gates on puzzle completion re-evaluate correctly.
func test_scenario_9_puzzle_rewind() -> void:
	# -- Phase A: Checkpoint at time 5.0 --
	set_time(5.0)
	_chronicle.set_fact("puzzle.piece1", "placed")
	_chronicle.set_fact("puzzle.piece2", "placed")

	# -- Phase B: Player makes wrong moves --
	set_time(10.0)
	_chronicle.set_fact("puzzle.piece3", "wrong_spot")
	_chronicle.set_fact("puzzle.piece1", "moved")
	set_time(15.0)
	_chronicle.set_fact("puzzle.stuck", true)

	# -- Gate on stuck condition --
	var hint := add_node_2d("HintOverlay")
	var gate := CompanionFactory.make_gate({
		condition = "puzzle.stuck",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	hint.add_child(gate)
	assert_gate_open(hint)

	# -- Phase C: Rewind to checkpoint --
	_chronicle.rollback_to(5.0)

	# Hint overlay hidden (puzzle.stuck gone)
	assert_gate_closed(hint)
	# Pieces back to checkpoint state
	assert_fact("puzzle.piece1", "placed")
	assert_fact("puzzle.piece2", "placed")
	assert_no_fact("puzzle.piece3")
	assert_no_fact("puzzle.stuck")
	assert_game_time(5.0)


# ── Scenario 10: Combat log — temporal range query for damage dealt ──
# Player takes damage over time. Use changes_between to query damage events
# in a time window. Use fact_changes_between for a specific key.
func test_scenario_10_combat_log_temporal_range() -> void:
	set_time(1.0)
	_chronicle.set_fact("combat.hit1", 15)
	set_time(3.0)
	_chronicle.set_fact("player.hp", 85)
	set_time(5.0)
	_chronicle.set_fact("combat.hit2", 25)
	set_time(7.0)
	_chronicle.set_fact("player.hp", 60)
	set_time(9.0)
	_chronicle.set_fact("combat.hit3", 10)
	set_time(11.0)
	_chronicle.set_fact("player.hp", 50)

	# get_changes_between uses half-open interval (since, until] — exclusive lower bound.
	# (3.0, 9.0] excludes hp@3, includes hit2@5, hp@7, hit3@9 = 3 events.
	var window: Array[Dictionary] = _chronicle.get_changes_between(3.0, 9.0)
	assert_eq(window.size(), 3, "(3,9] has 3 events: hit2@5, hp@7, hit3@9 — hp@3 excluded")

	# Query only player.hp changes in window
	var hp_changes: Array[Dictionary] = _chronicle.get_fact_changes_between("player.hp", 0.0, 12.0)
	assert_eq(hp_changes.size(), 3, "player.hp changed 3 times total")
	assert_eq(hp_changes[0].value, 85)
	assert_eq(hp_changes[1].value, 60)
	assert_eq(hp_changes[2].value, 50)

	# Full range covers all entries
	var full: Array[Dictionary] = _chronicle.get_changes_between(0.0, 12.0)
	assert_eq(full.size(), 6, "[0,12] covers all 6 entries")


# ── Scenario 11: Replay scrubber with gate ──
# Record game events over time. Use temporal range queries to inspect a window.
# Gate controls visibility based on checkpoint. Rollback + query verifies consistency.
func test_scenario_11_replay_scrubber_with_rollback() -> void:
	# -- Record events --
	set_time(2.0)
	_chronicle.set_fact("level.started", true)
	set_time(5.0)
	_chronicle.set_fact("checkpoint.reached", true)
	set_time(8.0)
	_chronicle.set_fact("boss.phase", 1)
	set_time(12.0)
	_chronicle.set_fact("boss.phase", 2)
	set_time(15.0)
	_chronicle.set_fact("boss.defeated", true)

	# -- Gate on boss.defeated --
	var victory := add_node_2d("VictoryBanner")
	var gate := CompanionFactory.make_gate({
		condition = "boss.defeated",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	victory.add_child(gate)
	assert_gate_open(victory)

	# -- Query full timeline --
	var all: Array[Dictionary] = _chronicle.get_changes_between(0.0, 20.0)
	assert_eq(all.size(), 5, "5 events in full timeline")

	# -- Rollback to checkpoint --
	_chronicle.rollback_to(5.0)
	assert_gate_closed(victory)

	# -- Query after rollback --
	var after: Array[Dictionary] = _chronicle.get_changes_between(0.0, 20.0)
	assert_eq(after.size(), 2, "only 2 events survive rollback to t=5")
	assert_eq(after[0].key as String, "level.started")
	assert_eq(after[1].key as String, "checkpoint.reached")

	# -- fact_changes_between for boss.phase after rollback --
	var boss: Array[Dictionary] = _chronicle.get_fact_changes_between("boss.phase", 0.0, 20.0)
	assert_eq(boss.size(), 0, "boss.phase entries removed by rollback")


# ── Scenario 12: Position tracking — value types with Gate, Reactor, and serialize roundtrip ──
# Player position is stored as Vector2. A Gate opens when player reaches safe zone.
# A Reactor tracks position changes. Verifies serialize roundtrip and rollback
# restore Vector2 values correctly.
func test_scenario_12_position_tracking_with_value_types() -> void:
	# -- Set up: Gate opens when player reaches safe zone --
	var safe_indicator := add_node_2d("SafeIndicator")
	var gate := CompanionFactory.make_gate({
		condition = "player.in_safe_zone",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	safe_indicator.add_child(gate)
	assert_gate_closed(safe_indicator)

	# -- Reactor tracks position changes --
	var spy_node := add_node("SpyNode")
	spy_node.set_script(preload("res://test/support/chronicle_spy_node.gd"))
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "player.pos",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	spy_node.add_child(reactor)

	# -- Player moves, position stored as Vector2 --
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(50, 50))
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, EventCollector.SKIP, Vector2(50, 50))

	set_time(2.0)
	_chronicle.set_fact("player.pos", Vector2(200, 300))
	_chronicle.set_fact("player.in_safe_zone", true)
	assert_gate_open(safe_indicator)
	assert_spy_calls(reactor, 2)

	# -- Serialize and restore --
	var data: Dictionary = _chronicle.serialize()
	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(data)
	assert_true(c2.get_fact("player.pos") is Vector2)
	assert_eq(c2.get_fact("player.pos"), Vector2(200, 300))

	# -- Query timeline for position changes --
	var pos_changes: Array[Dictionary] = _chronicle.get_fact_changes_between("player.pos", 0.0, 5.0)
	assert_eq(pos_changes.size(), 2)
	assert_eq(pos_changes[0].value, Vector2(50, 50))
	assert_eq(pos_changes[1].value, Vector2(200, 300))

	# -- Rollback to before safe zone --
	_chronicle.rollback_to(1.0)
	assert_gate_closed(safe_indicator)
	assert_fact("player.pos", Vector2(50, 50))


# ── Scenario 13: Color palette with packed arrays and recorder ──
# Packed arrays (PackedColorArray, PackedVector2Array) survive a full file roundtrip.
# A Recorder captures the palette_changed signal. Verifies serialize → file → load → deserialize
# preserves type identity for packed array facts.
func test_scenario_13_color_palette_with_packed_arrays() -> void:
	# -- Recorder captures palette changes --
	var palette_node := add_signaled_node("palette_changed", [])
	var recorder := CompanionFactory.make_recorder({
		trigger_signal = "palette_changed",
		fact_key = "palette.updated",
		value = true,
		record_mode = CompanionFactory.RecordMode.ALWAYS,
	})
	palette_node.add_child(recorder)

	# -- Store color palette as PackedColorArray --
	_chronicle.set_fact("palette.colors", PackedColorArray([Color.RED, Color.GREEN, Color.BLUE]))
	_chronicle.set_fact("ui.positions", PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]))

	# -- Trigger recorder --
	palette_node.emit_signal("palette_changed")
	assert_fact("palette.updated", true)

	# -- Serialize, write to file, load back --
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_test_scenario_13.json"
	save_temp(save_path, data)
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)

	# -- Verify packed arrays survived full file roundtrip --
	var colors: Variant = c2.get_fact("palette.colors")
	assert_true(colors is PackedColorArray, "should survive file roundtrip as PackedColorArray")
	assert_eq(colors.size(), 3)
	assert_eq(colors[0], Color.RED)
	assert_eq(colors[2], Color.BLUE)

	var positions: Variant = c2.get_fact("ui.positions")
	assert_true(positions is PackedVector2Array, "should survive file roundtrip as PackedVector2Array")
	assert_eq(positions.size(), 3)
	assert_eq(positions[0], Vector2(0, 0))


# ── Scenario 14: Speed buff with lifetime — Gate and Reactor cycle ──
# Player picks up a speed buff with 5s lifetime. Gate opens when buff is active.
# Reactor logs buff changes. After expiry, gate closes. Player re-picks up buff,
# gate reopens. Verify full cycle including fact_expired signal.
func test_scenario_14_speed_buff_lifetime_with_gate_reactor() -> void:
	# -- Gate on buff condition --
	var hud := add_node_2d("SpeedHUD")
	var gate := CompanionFactory.make_gate({
		condition = "player.speed_buff",
		gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE,
	})
	hud.add_child(gate)
	assert_gate_closed(hud)

	# -- Reactor tracks buff changes --
	var spy := add_node("BuffSpy")
	spy.set_script(preload("res://test/support/chronicle_spy_node.gd"))
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "player.speed_buff",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	spy.add_child(reactor)

	# -- Collect fact_expired signals --
	var expired_events: EventCollector = make_collector()
	_chronicle.fact_expired.connect(expired_events.callback())

	# Phase 1: Pick up buff
	set_time(1.0)
	_chronicle.set_fact("player.speed_buff", 1.5, false, 5.0)
	assert_gate_open(hud)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, EventCollector.SKIP, 1.5)

	# Phase 2: Buff expires
	advance_time(5.1)
	assert_gate_closed(hud)
	assert_spy_calls(reactor, 2)
	assert_spy_call(reactor, 1, EventCollector.SKIP, null)
	expired_events.assert_count(1)
	expired_events.assert_event(0, "player.speed_buff", 1.5)

	# Phase 3: Pick up buff again
	_chronicle.set_fact("player.speed_buff", 2.0, false, 3.0)
	assert_gate_open(hud)
	assert_spy_calls(reactor, 3)

	# Phase 4: Second expiry
	advance_time(3.1)
	assert_gate_closed(hud)
	expired_events.assert_count(2)

	# Phase 5: Verify not serialized (transient by lifetime)
	var data: Dictionary = _chronicle.serialize()
	var has_buff: bool = false
	for k: String in data["facts"]:
		if "speed_buff" in k:
			has_buff = true
	assert_false(has_buff, "lifetime buff not serialized")


# ── Scenario 15: Combo system with increment + lifetime decay ──
# Player builds a combo counter (increment) with a 3s decay timer (lifetime).
# Each hit resets the decay timer by re-setting with lifetime.
# After 3s without hitting, combo expires. Reactor tracks changes.
func test_scenario_15_combo_system_increment_with_lifetime() -> void:
	# -- Reactor tracks combo changes --
	var spy := add_node("ComboSpy")
	spy.set_script(preload("res://test/support/chronicle_spy_node.gd"))
	var reactor := CompanionFactory.make_reactor({
		watch_pattern = "player.combo",
		target_method = "on_fact",
		react_to = CompanionFactory.ReactTo.ANY,
	})
	spy.add_child(reactor)

	# Hit 1: Start combo with lifetime
	set_time(1.0)
	_chronicle.set_fact("player.combo", 1, false, 3.0)
	assert_fact("player.combo", 1)

	# Hit 2: Increment counter, then reset timer
	set_time(2.0)
	_chronicle.increment_fact("player.combo")
	assert_fact("player.combo", 2)
	# increment preserves timer — reset it explicitly
	_chronicle.set_fact("player.combo", 2, false, 3.0)
	assert_gt(_chronicle.get_expiry_remaining("player.combo"), 2.5)

	# Hit 3: Increment and reset again
	set_time(3.0)
	_chronicle.increment_fact("player.combo")
	_chronicle.set_fact("player.combo", 3, false, 3.0)
	assert_fact("player.combo", 3)

	# No more hits — combo decays after 3s
	advance_time(3.1)
	assert_no_fact("player.combo")

	# Reactor saw 4 value-changing events: creation (1), increment→2, increment→3,
	# and expiry (null). The same-value timer resets are suppressed.
	assert_spy_calls(reactor, 4)
	assert_spy_call(reactor, 3, EventCollector.SKIP, null)
