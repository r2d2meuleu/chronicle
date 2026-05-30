## Scenario tests: multi-stage quest system built on Chronicle.
## Each test simulates real quest gameplay using Chronicle as the backbone.
## Covers linear progression, branching choices, prerequisites, timed objectives,
## watchers, reactors, gates, rollback, save/load, and cross-quest queries.
extends ChronicleTestSuite


# ── Linear Quest Progression ──


# Quest advances through stages 1→2→3→4→done
func test_quest_advances_through_stages() -> void:
	# Start quest at stage 1
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 1)

	# Advance through all stages
	_chronicle.set_fact("quest.main.stage", 2)
	_chronicle.set_fact("quest.main.stage", 3)
	_chronicle.set_fact("quest.main.stage", 4)

	# Complete
	_chronicle.set_fact("quest.main.status", "complete")
	_chronicle.set_fact("quest.main.stage", 5)

	assert_fact("quest.main.status", "complete")
	assert_fact("quest.main.stage", 5)

	# History must contain every stage write (1, 2, 3, 4, 5 = 5 entries)
	assert_history_size("quest.main.stage", 5)
	assert_history_first("quest.main.stage", 1)
	assert_history_last("quest.main.stage", 5)


# Gate opens only at the correct quest stage
func test_gate_opens_at_correct_stage() -> void:
	_chronicle.set_fact("quest.main.stage", 1)

	# Gate requires stage == 3 to reveal the locked chest
	var chest := add_gate("quest.main.stage == 3")
	assert_gate_closed(chest)

	_chronicle.set_fact("quest.main.stage", 2)
	assert_gate_closed(chest)

	_chronicle.set_fact("quest.main.stage", 3)
	assert_gate_open(chest)

	# Advancing past stage 3 closes gate again
	_chronicle.set_fact("quest.main.stage", 4)
	assert_gate_closed(chest)


# Quest completion marks status as "complete"
func test_quest_completion_status() -> void:
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 3)

	# Player finishes final objective
	_chronicle.set_fact("quest.main.status", "complete")

	assert_fact("quest.main.status", "complete")

	assert_history("quest.main.status", ["active", "complete"])


# Completed quest cannot be restarted (guard check via gate)
func test_completed_quest_cannot_restart() -> void:
	_chronicle.set_fact("quest.main.status", "complete")

	# "Start quest" button gate: visible only when quest is NOT complete
	var start_btn := add_gate("quest.main.status != \"complete\"",
		{gate_mode = CompanionFactory.GateMode.HIDE_WHEN_FALSE})
	assert_gate_closed(start_btn)

	# Attempting to set status back to active while complete has no guard in
	# Chronicle itself — the gate simply reflects the current state.
	# The game would prevent this via the gate, but we also verify the query.
	assert_fact("quest.main.status", "complete")


# Quest progress tracked with increment (kill 5 wolves)
func test_kill_counter_increment() -> void:
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.side.wolves.required", 5)
	_chronicle.set_fact("quest.side.wolves.killed", 0)

	# Player kills wolves one by one
	_chronicle.increment_fact("quest.side.wolves.killed")
	_chronicle.increment_fact("quest.side.wolves.killed")
	_chronicle.increment_fact("quest.side.wolves.killed")
	_chronicle.increment_fact("quest.side.wolves.killed")
	_chronicle.increment_fact("quest.side.wolves.killed")

	assert_fact("quest.side.wolves.killed", 5)

	# Gate opens "Turn In" button when wolves == required
	var turn_in := add_gate("quest.side.wolves.killed >= 5")
	assert_gate_open(turn_in)


# ── Branching Quests ──


# Quest branch choice A locks out branch B
func test_branch_choice_a_locks_out_b() -> void:
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 2)

	# Player makes choice A
	_chronicle.set_fact("quest.main.choice", "A")

	# Gate for branch B: visible only if choice != "A"
	var branch_b_path := add_gate("quest.main.choice != \"A\"")
	assert_gate_closed(branch_b_path)

	# Gate for branch A: visible when choice == "A"
	var branch_a_path := add_gate("quest.main.choice == \"A\"")
	assert_gate_open(branch_a_path)

	assert_fact("quest.main.choice", "A")


# Branch choice affects downstream gate
func test_branch_choice_affects_downstream_gate() -> void:
	_chronicle.set_fact("quest.main.choice", "B")

	# Branch B unlocks a secret ending gate
	var secret_ending := add_gate("quest.main.choice == \"B\" AND quest.main.status == \"complete\"")
	assert_gate_closed(secret_ending)

	# Complete the quest via branch B
	_chronicle.set_fact("quest.main.status", "complete")
	assert_gate_open(secret_ending)

	# Same gate stays closed for choice A
	_chronicle.set_fact("quest.main.choice", "A")
	assert_gate_closed(secret_ending)


# Multiple independent quests progress without interference
func test_independent_quests_no_interference() -> void:
	# Start two independent quests simultaneously
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 1)
	_chronicle.set_fact("quest.side.rescue.status", "active")
	_chronicle.set_fact("quest.side.rescue.npc_found", false)

	# Advance main quest
	_chronicle.set_fact("quest.main.stage", 2)
	_chronicle.set_fact("quest.main.stage", 3)

	# Complete side quest
	_chronicle.set_fact("quest.side.rescue.npc_found", true)
	_chronicle.set_fact("quest.side.rescue.status", "complete")

	# Main quest is unchanged by side quest
	assert_fact("quest.main.status", "active")
	assert_fact("quest.main.stage", 3)

	# Side quest is complete independently
	assert_fact("quest.side.rescue.status", "complete")
	assert_fact("quest.side.rescue.npc_found", true)


# Quest prerequisites — gate blocks until prerequisite met
func test_quest_prerequisite_gate() -> void:
	_chronicle.set_fact("player.level", 3)

	# Quest B requires: quest A complete AND player.level >= 5
	var quest_b_board := add_gate("quest.a.status == \"complete\" AND player.level >= 5")
	assert_gate_closed(quest_b_board)

	# Level up but quest A still not done
	_chronicle.set_fact("player.level", 5)
	assert_gate_closed(quest_b_board)

	# Complete quest A
	_chronicle.set_fact("quest.a.status", "complete")
	assert_gate_open(quest_b_board)


# Quest with multiple objectives — all required for completion
func test_all_objectives_required_for_completion() -> void:
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.obj.gather_herbs", false)
	_chronicle.set_fact("quest.main.obj.find_cave", false)
	_chronicle.set_fact("quest.main.obj.defeat_boss", false)

	# "Complete" button gate: all three objectives must be done
	var complete_btn := add_gate(
		"quest.main.obj.gather_herbs AND quest.main.obj.find_cave AND quest.main.obj.defeat_boss"
	)
	assert_gate_closed(complete_btn)

	_chronicle.set_fact("quest.main.obj.gather_herbs", true)
	assert_gate_closed(complete_btn)

	_chronicle.set_fact("quest.main.obj.find_cave", true)
	assert_gate_closed(complete_btn)

	# Final objective unlocks completion
	_chronicle.set_fact("quest.main.obj.defeat_boss", true)
	assert_gate_open(complete_btn)


# ── Quest + Watchers ──


# Watcher notifies on quest stage change
func test_watcher_notifies_on_stage_change() -> void:
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 1)

	var stage_events := watch_events("quest.main.stage")

	_chronicle.set_fact("quest.main.stage", 2)
	_chronicle.set_fact("quest.main.stage", 3)

	stage_events.assert_count(2)
	stage_events.assert_event(0, "quest.main.stage", 2, 1)
	stage_events.assert_event(1, "quest.main.stage", 3, 2)


# Reactor triggers NPC dialogue update on quest advance
func test_reactor_updates_npc_on_quest_advance() -> void:
	_chronicle.set_fact("quest.main.stage", 1)

	# NPC watches any quest fact change and updates dialogue
	var npc := add_reactor({watch_pattern = "quest.*", react_to = CompanionFactory.ReactTo.ANY})
	var npc_calls := collect_signal(npc, "fact_matched")

	# Player advances quest stage
	_chronicle.set_fact("quest.main.stage", 2)
	npc_calls.assert_count(1)
	npc_calls.assert_event(0, "quest.main.stage", 2, EventCollector.SKIP)

	# NPC responds to quest status change too
	_chronicle.set_fact("quest.main.status", "active")
	npc_calls.assert_count(2)


# Quest completion triggers achievement watcher
func test_quest_completion_triggers_achievement() -> void:
	_chronicle.set_fact("quest.main.status", "active")

	# Achievement system watches for quest completion
	var achievement_events := watch_events("quest.main.status")

	_chronicle.set_fact("quest.main.status", "complete")

	achievement_events.assert_count(1)
	achievement_events.assert_event(0, "quest.main.status", "complete", "active")


# watch_once fires only when quest is first accepted
func test_watch_once_fires_on_quest_accept() -> void:
	# One-shot watcher: fires when quest becomes active for the first time
	var accept_event := watch_once_events("quest.main.status")

	# Quest accepted
	_chronicle.set_fact("quest.main.status", "active")
	accept_event.assert_count(1)
	accept_event.assert_event(0, "quest.main.status", "active", EventCollector.SKIP)

	# Quest advances — watch_once should NOT fire again
	_chronicle.set_fact("quest.main.status", "complete")
	accept_event.assert_count(1)


# ── Quest + Time ──


# Timed quest objective expires (lifetime fact)
func test_timed_objective_expires() -> void:
	set_time(0.0)
	_chronicle.set_fact("quest.main.status", "active")

	# Timed objective: player must reach the beacon within 30 seconds
	_chronicle.set_fact("quest.main.obj.beacon_active", true, false, 30.0)
	assert_fact("quest.main.obj.beacon_active", true)

	# Collect expiry signal
	var expired_ev := make_collector()
	_chronicle.fact_expired.connect(expired_ev.callback())

	# 20 seconds pass — still active
	advance_time(20.0)
	assert_fact("quest.main.obj.beacon_active", true)

	# Time runs out
	advance_time(11.0)
	assert_no_fact("quest.main.obj.beacon_active")
	expired_ev.assert_count(1)
	expired_ev.assert_event(0, "quest.main.obj.beacon_active", true)


# Quest started_at timestamp is queryable
func test_quest_started_at_timestamp() -> void:
	set_time(5.0)
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.started_at", 5.0)

	set_time(12.0)
	_chronicle.set_fact("quest.main.stage", 2)

	# Query the timestamp directly
	assert_fact("quest.main.started_at", 5.0)

	# Use first_change to locate the earliest quest fact
	var first_entry: Variant = _chronicle.get_first_change("quest.main.*")
	assert_not_null(first_entry, "first_change returns quest entry")
	assert_eq(first_entry.time, 5.0, "quest started at t=5.0")


# changes_since quest start shows all quest progress
func test_changes_since_quest_start() -> void:
	# Non-quest activity before quest start
	set_time(1.0)
	_chronicle.set_fact("player.gold", 100)

	# Quest begins at t=5
	set_time(5.0)
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 1)

	set_time(8.0)
	_chronicle.set_fact("quest.main.stage", 2)

	set_time(12.0)
	_chronicle.set_fact("quest.main.stage", 3)
	_chronicle.set_fact("quest.main.status", "complete")

	# Query changes since quest start — use time just before t=5 because since is exclusive
	var since_start: Array[Dictionary] = _chronicle.get_changes_since(4.999)
	# All 5 quest-related writes at or after t=5
	assert_eq(since_start.size(), 5, "5 quest events since t=5.0")

	# Pre-quest player.gold not included
	var keys_since: Array = []
	for entry: Dictionary in since_start:
		keys_since.append(entry.key)
	assert_does_not_have(keys_since, "player.gold", "player.gold predates quest start")


# ── Quest + Rollback ──


# Rollback past quest choice allows different path
func test_rollback_past_choice_allows_different_path() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 2)

	set_time(3.0)
	_chronicle.set_fact("quest.main.choice", "A")
	set_time(4.0)
	_chronicle.set_fact("quest.main.stage", 3)

	# Player regrets choice A and rewinds
	_chronicle.rollback_to(2.5)

	assert_no_fact("quest.main.choice")
	assert_fact("quest.main.stage", 2)

	# Now take choice B
	set_time(5.0)
	_chronicle.set_fact("quest.main.choice", "B")
	assert_fact("quest.main.choice", "B")


# Rollback past quest completion un-completes it
func test_rollback_un_completes_quest() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.main.status", "active")
	set_time(5.0)
	_chronicle.set_fact("quest.main.status", "complete")

	assert_fact("quest.main.status", "complete")

	# Rollback before completion
	_chronicle.rollback_to(3.0)

	assert_fact("quest.main.status", "active")


# Rollback mid-quest restores intermediate stage
func test_rollback_restores_intermediate_stage() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.main.stage", 1)
	set_time(2.0)
	_chronicle.set_fact("quest.main.stage", 2)
	set_time(3.0)
	_chronicle.set_fact("quest.main.stage", 3)
	set_time(4.0)
	_chronicle.set_fact("quest.main.stage", 4)

	# Rollback to between stage 2 and stage 3
	_chronicle.rollback_to(2.5)

	assert_fact("quest.main.stage", 2)

	# History now ends at stage 2
	assert_history_size("quest.main.stage", 2)
	assert_history_last("quest.main.stage", 2)


# Gate updates after quest rollback
func test_gate_updates_after_rollback() -> void:
	set_time(0.0)
	_chronicle.set_fact("quest.main.stage", 1)
	set_time(1.0)
	_chronicle.set_fact("quest.main.stage", 3)

	# Gate open when stage >= 3
	var next_area := add_gate("quest.main.stage >= 3")
	assert_gate_open(next_area)

	# Rollback to t=0.5 — stage reverts to 1 (the value at t=0)
	_chronicle.rollback_to(0.5)

	assert_gate_closed(next_area)

	# Advance again, gate re-opens
	set_time(2.0)
	_chronicle.set_fact("quest.main.stage", 3)
	assert_gate_open(next_area)


# ── Quest System Queries ──


# Find all active quests
func test_find_all_active_quests() -> void:
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.side.rescue.status", "active")
	_chronicle.set_fact("quest.side.bounty.status", "complete")
	_chronicle.set_fact("quest.side.explore.status", "active")

	# Use find to get all quest keys then filter by value
	var all_quest_keys: Array[String] = _chronicle.get_fact_keys("quest.*")
	var active_count: int = 0
	for key: String in all_quest_keys:
		if _chronicle.get_fact(key) == "active":
			active_count += 1

	assert_eq(active_count, 3, "3 quests are currently active")


# Find all completed quests
func test_find_all_completed_quests() -> void:
	_chronicle.set_fact("quest.main.status", "complete")
	_chronicle.set_fact("quest.side.rescue.status", "complete")
	_chronicle.set_fact("quest.side.bounty.status", "active")
	_chronicle.set_fact("quest.daily.log.status", "complete")

	var all_quest_keys: Array[String] = _chronicle.get_fact_keys("quest.*")
	var completed: Array[String] = []
	for key: String in all_quest_keys:
		if _chronicle.get_fact(key) == "complete":
			completed.append(key)

	assert_eq(completed.size(), 3, "3 completed quests")
	assert_has(completed, "quest.main.status")
	assert_has(completed, "quest.side.rescue.status")
	assert_has(completed, "quest.daily.log.status")


# Quest history shows all state changes
func test_quest_history_shows_all_changes() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.main.status", "active")
	set_time(3.0)
	_chronicle.set_fact("quest.main.status", "active")  # Re-affirm (same value → still recorded)
	set_time(5.0)
	_chronicle.set_fact("quest.main.status", "failed")
	set_time(7.0)
	_chronicle.set_fact("quest.main.status", "active")  # Retry after rollback scenario
	set_time(9.0)
	_chronicle.set_fact("quest.main.status", "complete")

	assert_history("quest.main.status",
		["active", "active", "failed", "active", "complete"],
		[1.0, 3.0, 5.0, 7.0, 9.0]
	)


# Count completed quests for achievement threshold
func test_count_completed_quests_for_achievement() -> void:
	# Set quest.completed_count directly
	_chronicle.set_fact("quest.completed_count", 0)

	# Simulate quest completions via increment
	_chronicle.increment_fact("quest.completed_count")
	_chronicle.increment_fact("quest.completed_count")
	_chronicle.increment_fact("quest.completed_count")

	assert_fact("quest.completed_count", 3)

	# Achievement: "Quest Master" unlocks at 3 completions
	var achievement_gate := add_gate("quest.completed_count >= 3")
	assert_gate_open(achievement_gate)

	# Also verify a higher threshold stays closed
	var legendary_gate := add_gate("quest.completed_count >= 10")
	assert_gate_closed(legendary_gate)


# ── Full Playthrough ──


# Multi-quest playthrough: start, progress, branch, complete (20+ ops)
func test_multi_quest_full_playthrough() -> void:
	set_time(1.0)
	# Begin main quest
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 1)
	_chronicle.set_fact("quest.main.started_at", 1.0)

	set_time(2.0)
	# Accept side quest
	_chronicle.set_fact("quest.side.rescue.status", "active")
	_chronicle.set_fact("quest.side.rescue.npc_found", false)

	set_time(3.0)
	# Progress main quest
	_chronicle.set_fact("quest.main.stage", 2)
	_chronicle.set_fact("quest.main.obj.gather_herbs", true)

	set_time(4.0)
	# Complete side quest
	_chronicle.set_fact("quest.side.rescue.npc_found", true)
	_chronicle.set_fact("quest.side.rescue.status", "complete")
	_chronicle.increment_fact("quest.completed_count")

	set_time(5.0)
	# Main quest branch decision
	_chronicle.set_fact("quest.main.stage", 3)
	_chronicle.set_fact("quest.main.choice", "A")

	set_time(6.0)
	# Final main quest stage
	_chronicle.set_fact("quest.main.stage", 4)
	_chronicle.set_fact("quest.main.obj.defeat_boss", true)

	set_time(7.0)
	# Complete main quest
	_chronicle.set_fact("quest.main.status", "complete")
	_chronicle.increment_fact("quest.completed_count")

	# Verify final state
	assert_facts({
		"quest.main.status": "complete",
		"quest.main.stage": 4,
		"quest.main.choice": "A",
		"quest.main.obj.gather_herbs": true,
		"quest.main.obj.defeat_boss": true,
		"quest.side.rescue.status": "complete",
		"quest.side.rescue.npc_found": true,
		"quest.completed_count": 2,
	})

	# The playthrough performs a deterministic 16 fact writes.
	var full_timeline: Array[Dictionary] = _chronicle.get_changes_since(0.0)
	assert_eq(full_timeline.size(), 16, "playthrough generated exactly 16 timeline entries")

	# find returns all 9 distinct quest facts written above
	var all_quest_keys: Array[String] = _chronicle.get_fact_keys("quest.*")
	assert_eq(all_quest_keys.size(), 9, "9 distinct quest facts exist")


# Save mid-quest, load, continue from saved state
func test_save_midquest_load_continue() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 2)
	_chronicle.set_fact("quest.main.choice", "B")
	_chronicle.set_fact("player.gold", 250)

	# Save mid-quest
	var save_data: Dictionary = _chronicle.serialize()
	assert_has(save_data, "facts")
	assert_has(save_data, "timeline")

	# Simulate game quit — clear everything
	_chronicle.clear()
	assert_no_fact("quest.main.status")
	assert_no_fact("quest.main.stage")

	# Reload
	var ok: bool = _chronicle.deserialize(save_data)
	assert_true(ok, "deserialization succeeded")

	# Quest state fully restored
	assert_fact("quest.main.status", "active")
	assert_fact("quest.main.stage", 2)
	assert_fact("quest.main.choice", "B")
	assert_fact("player.gold", 250)

	# Continue: advance to stage 3
	set_time(5.0)
	_chronicle.set_fact("quest.main.stage", 3)
	assert_fact("quest.main.stage", 3)

	# History reflects pre-save (stage 2) + post-load (stage 3) writes
	var stage_history: Array[Dictionary] = _chronicle.get_fact_history("quest.main.stage")
	assert_eq(stage_history.size(), 2, "history includes the pre-save and post-load stages")


# Quest chain: completing quest A unlocks quest B
func test_quest_chain_a_unlocks_b() -> void:
	_chronicle.set_fact("quest.a.status", "active")
	_chronicle.set_fact("quest.a.stage", 1)

	# Quest B board is gated on quest A completion
	var quest_b_board := add_gate("quest.a.status == \"complete\"")
	assert_gate_closed(quest_b_board)

	# Also track gate with reactor pattern
	var unlock_events := watch_events("quest.a.status")

	# Complete quest A
	_chronicle.set_fact("quest.a.status", "complete")
	assert_gate_open(quest_b_board)
	unlock_events.assert_count(1)
	unlock_events.assert_event(0, "quest.a.status", "complete", "active")

	# Now start quest B
	_chronicle.set_fact("quest.b.status", "active")
	_chronicle.set_fact("quest.b.stage", 1)

	assert_fact("quest.b.status", "active")
	assert_fact("quest.a.status", "complete")


# Failed quest retry after rollback
func test_failed_quest_retry_after_rollback() -> void:
	set_time(1.0)
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 3)

	set_time(5.0)
	# Quest fails (player ran out of time or died)
	_chronicle.set_fact("quest.main.status", "failed")

	assert_fact("quest.main.status", "failed")

	# Player uses in-game rewind (rollback) to before the failure
	_chronicle.rollback_to(3.0)

	assert_fact("quest.main.status", "active")
	assert_fact("quest.main.stage", 3)
	assert_game_time(3.0)

	# Player tries again successfully
	set_time(6.0)
	_chronicle.set_fact("quest.main.status", "complete")
	assert_fact("quest.main.status", "complete")


# Parallel quests do not interfere with each other
func test_parallel_quests_no_interference() -> void:
	# Three quests running simultaneously
	_chronicle.set_fact("quest.main.stage", 1)
	_chronicle.set_fact("quest.side.rescue.status", "active")
	_chronicle.set_fact("quest.daily.log.status", "active")
	_chronicle.set_fact("quest.daily.log.entries", 0)

	# All three advance independently
	_chronicle.set_fact("quest.main.stage", 2)
	_chronicle.increment_fact("quest.daily.log.entries")

	_chronicle.set_fact("quest.side.rescue.status", "complete")

	_chronicle.set_fact("quest.main.stage", 3)
	_chronicle.increment_fact("quest.daily.log.entries")
	_chronicle.increment_fact("quest.daily.log.entries")

	_chronicle.set_fact("quest.daily.log.status", "complete")

	# Each quest has correct independent final state
	assert_fact("quest.main.stage", 3)
	assert_fact("quest.side.rescue.status", "complete")
	assert_fact("quest.daily.log.status", "complete")
	assert_fact("quest.daily.log.entries", 3)

	# Stage history is clean — only main quest stage writes
	var stage_hist: Array[Dictionary] = _chronicle.get_fact_history("quest.main.stage")
	assert_eq(stage_hist.size(), 3, "main stage has exactly 3 history entries")
	for entry: Dictionary in stage_hist:
		assert_eq(entry.key, "quest.main.stage", "all stage history entries are for main stage")


# Quest with expression condition: level >= 5 AND has_key
func test_quest_expression_level_and_key() -> void:
	_chronicle.set_fact("player.level", 3)
	_chronicle.set_fact("quest.main.status", "active")

	# Boss lair requires: level >= 5 AND player has the dungeon key
	var boss_lair := add_gate("player.level >= 5 AND player.has_dungeon_key")
	assert_gate_closed(boss_lair)

	# Level up but no key
	_chronicle.set_fact("player.level", 6)
	assert_gate_closed(boss_lair)

	# Get the key but level insufficient (test reset)
	_chronicle.set_fact("player.level", 3)
	_chronicle.set_fact("player.has_dungeon_key", true)
	assert_gate_closed(boss_lair)

	# Both conditions met
	_chronicle.set_fact("player.level", 5)
	assert_gate_open(boss_lair)

	# Losing the key closes access
	_chronicle.set_fact("player.has_dungeon_key", false)
	assert_gate_closed(boss_lair)


# Full quest lifecycle with reactor and gate integration
func test_full_quest_lifecycle_reactor_gate() -> void:
	set_time(1.0)

	# -- Gates: control NPC dialogue triggers and area access --
	# Dialogue trigger: NPC talks when quest is active
	var npc_dialogue := add_gate("quest.main.status == \"active\"")

	# Reward room: opens only on completion
	var reward_room := add_gate("quest.main.status == \"complete\"")

	assert_gate_closed(npc_dialogue)
	assert_gate_closed(reward_room)

	# -- Reactor: NPC log tracks all quest changes --
	var quest_log := add_reactor({watch_pattern = "quest.main.*", react_to = CompanionFactory.ReactTo.ANY})
	var log_events := collect_signal(quest_log, "fact_matched")

	# -- Quest accepted --
	set_time(2.0)
	_chronicle.set_fact("quest.main.status", "active")
	_chronicle.set_fact("quest.main.stage", 1)
	_chronicle.set_fact("quest.main.started_at", 2.0)

	assert_gate_open(npc_dialogue)
	assert_gate_closed(reward_room)
	log_events.assert_count(3)

	# -- Timed bonus objective: collect all gems within 20s --
	_chronicle.set_fact("quest.main.obj.gems_bonus", true, false, 20.0)
	assert_fact("quest.main.obj.gems_bonus", true)

	# -- Progress through stages --
	set_time(5.0)
	_chronicle.set_fact("quest.main.stage", 2)
	set_time(8.0)
	_chronicle.set_fact("quest.main.stage", 3)
	set_time(10.0)
	_chronicle.set_fact("quest.main.choice", "A")

	# -- Check that timed bonus is still active --
	assert_fact("quest.main.obj.gems_bonus", true)

	# -- Quest completed --
	set_time(15.0)
	_chronicle.set_fact("quest.main.stage", 4)
	_chronicle.set_fact("quest.main.status", "complete")
	_chronicle.increment_fact("quest.completed_count")

	# Gate state flips on completion
	assert_gate_closed(npc_dialogue)
	assert_gate_open(reward_room)

	# Reactor logged every quest.main.* write:
	# status, stage, started_at, gems_bonus, stage×2 (t=5,8), choice, stage, status, count = 9.
	log_events.assert_count(9)

	# -- Verify timeline -- use time just before quest start because since is exclusive
	var quest_events: Array[Dictionary] = _chronicle.get_changes_since(1.999)
	assert_eq(quest_events.size(), 10, "exactly 10 entries since quest start")

	# -- Verify fact_history for stage --
	assert_history_size("quest.main.stage", 4)
	assert_history_first("quest.main.stage", 1)
	assert_history_last("quest.main.stage", 4)

	# -- Save and reload -- verify complete state persists
	roundtrip()

	assert_fact("quest.main.status", "complete")
	assert_fact("quest.main.stage", 4)
	assert_fact("quest.main.choice", "A")
	assert_fact("quest.main.started_at", 2.0)
	assert_fact("quest.completed_count", 1)

	# Bonus objective was a lifetime (transient) fact — not serialized
	assert_no_fact("quest.main.obj.gems_bonus")
