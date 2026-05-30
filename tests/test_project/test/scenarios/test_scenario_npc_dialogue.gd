extends ChronicleTestSuite

## Scenario tests: NPC dialogue state tracking with companion nodes.
## Simulates a merchant NPC whose greeting flags, relationship level, visit
## counts, quest offers, and dialogue choices are all managed through Chronicle
## facts, gates, reactors, and recorders.


# ── Dialogue State Tracking ───────────────────────────────────────────────────


# First greeting sets greeted flag
func test_first_greeting_sets_greeted_flag() -> void:
	assert_no_fact("npc.merchant.greeted")

	_chronicle.set_fact("npc.merchant.greeted")

	assert_marked("npc.merchant.greeted")
	assert_fact("npc.merchant.greeted", true)


# Subsequent interactions don't reset greeted flag
func test_subsequent_interactions_dont_reset_greeted_flag() -> void:
	_chronicle.set_fact("npc.merchant.greeted")
	assert_fact("npc.merchant.greeted", true)

	# Player talks to merchant two more times
	_chronicle.set_fact("npc.merchant.greeted", true)
	_chronicle.set_fact("npc.merchant.greeted", true)

	# Flag remains true, not reset or flipped
	assert_fact("npc.merchant.greeted", true)
	assert_history("npc.merchant.greeted", [true, true, true])


# Dialogue choice is recorded
func test_dialogue_choice_is_recorded() -> void:
	assert_no_fact("dialogue.merchant.choice")

	_chronicle.set_fact("dialogue.merchant.choice", "accept")

	assert_fact("dialogue.merchant.choice", "accept")


# NPC relationship level increments on positive interactions
func test_relationship_level_increments_on_positive_interactions() -> void:
	_chronicle.set_fact("npc.merchant.relationship", 0)
	assert_fact("npc.merchant.relationship", 0)

	_chronicle.increment_fact("npc.merchant.relationship", 1)
	_chronicle.increment_fact("npc.merchant.relationship", 1)

	assert_fact("npc.merchant.relationship", 2)


# Dialogue branch unlocked by quest state
func test_dialogue_branch_unlocked_by_quest_state() -> void:
	# Quest must be active for merchant to reveal secret passage dialogue
	assert_no_fact("quest.merchant.active")

	var watcher := watch_events("quest.merchant.active")

	_chronicle.set_fact("quest.merchant.active")

	watcher.assert_count(1)
	assert_fact("quest.merchant.active", true)

	# Quest state gates the dialogue branch
	assert_marked("quest.merchant.active")


# ── NPC + Gates ───────────────────────────────────────────────────────────────


# Gate shows dialogue option only when quest is active
func test_gate_shows_dialogue_option_when_quest_active() -> void:
	var option := add_gate("quest.merchant.active AND npc.merchant.greeted")
	assert_gate_closed(option)  # neither condition met

	_chronicle.set_fact("npc.merchant.greeted")
	assert_gate_closed(option)  # only one condition met

	_chronicle.set_fact("quest.merchant.active")
	assert_gate_open(option)  # both met — option visible

	_chronicle.set_fact("quest.merchant.active", false)
	assert_gate_closed(option)  # quest no longer active


# Gate hides option after quest complete
func test_gate_hides_option_after_quest_complete() -> void:
	_chronicle.set_fact("quest.merchant.active")

	var option := add_gate("quest.merchant.active")
	assert_gate_open(option)

	# Quest finishes — mark complete and clear active flag
	_chronicle.set_fact("quest.merchant.active", false)
	_chronicle.set_fact("quest.merchant.complete")

	assert_gate_closed(option)
	assert_marked("quest.merchant.complete")


# Multiple gates on different conditions for same NPC
func test_multiple_gates_different_conditions() -> void:
	var greet_option := add_gate("npc.merchant.greeted")
	var quest_option := add_gate("npc.merchant.quest_offered")
	var trade_option := add_gate("player.reputation >= 3")

	# All closed initially
	assert_gate_closed(greet_option)
	assert_gate_closed(quest_option)
	assert_gate_closed(trade_option)

	_chronicle.set_fact("npc.merchant.greeted")
	assert_gate_open(greet_option)
	assert_gate_closed(quest_option)
	assert_gate_closed(trade_option)

	_chronicle.set_fact("npc.merchant.quest_offered")
	assert_gate_open(greet_option)
	assert_gate_open(quest_option)
	assert_gate_closed(trade_option)

	_chronicle.set_fact("player.reputation", 5)
	assert_gate_open(greet_option)
	assert_gate_open(quest_option)
	assert_gate_open(trade_option)


# Gate with compound condition (quest active AND has item)
func test_gate_compound_condition_quest_active_and_has_item() -> void:
	var option := add_gate("quest.merchant.active AND inventory.merchant_key")
	assert_gate_closed(option)

	_chronicle.set_fact("quest.merchant.active")
	assert_gate_closed(option)  # missing inventory.merchant_key

	_chronicle.set_fact("inventory.merchant_key")
	assert_gate_open(option)  # both satisfied

	# Lose the key
	_chronicle.set_fact("inventory.merchant_key", false)
	assert_gate_closed(option)


# Gate with reputation threshold (player.reputation >= 3)
func test_gate_with_reputation_threshold() -> void:
	_chronicle.set_fact("player.reputation", 1)

	var vip_option := add_gate("player.reputation >= 3")
	assert_gate_closed(vip_option)

	_chronicle.set_fact("player.reputation", 3)
	assert_gate_open(vip_option)

	_chronicle.set_fact("player.reputation", 5)
	assert_gate_open(vip_option)

	# Reputation drops — option locked again
	_chronicle.set_fact("player.reputation", 2)
	assert_gate_closed(vip_option)


# ── NPC + Reactors ────────────────────────────────────────────────────────────


# Reactor updates NPC behavior when world state changes
func test_reactor_updates_npc_behavior_on_world_state_change() -> void:
	var reactor := add_reactor({
		watch_pattern = "world.*",
		react_to = CompanionFactory.ReactTo.ANY,
	})

	assert_spy_calls(reactor, 0)

	_chronicle.set_fact("world.time_of_day", "night")
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "world.time_of_day", "night")

	_chronicle.set_fact("world.weather", "rain")
	assert_spy_calls(reactor, 2)
	assert_spy_call(reactor, 1, "world.weather")


# One-shot reactor for first meeting reaction
func test_one_shot_reactor_first_meeting() -> void:
	var reactor := add_reactor({
		watch_pattern = "npc.merchant.greeted",
		react_to = CompanionFactory.ReactTo.CREATION,
		one_shot = true,
	})

	_chronicle.set_fact("npc.merchant.greeted")
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, "npc.merchant.greeted")

	# Second and third visits — reactor is spent, no new calls
	_chronicle.set_fact("npc.merchant.greeted", true)
	_chronicle.set_fact("npc.merchant.greeted", true)
	assert_spy_calls(reactor, 1)


# Reactor watches player reputation changes
func test_reactor_watches_player_reputation_changes() -> void:
	_chronicle.set_fact("player.reputation", 0)

	var reactor := add_reactor({
		watch_pattern = "player.reputation",
		react_to = CompanionFactory.ReactTo.CHANGE,
	})

	# Increase reputation
	_chronicle.set_fact("player.reputation", 1)
	assert_spy_calls(reactor, 1)
	assert_spy_call(reactor, 0, EventCollector.SKIP, 1)

	_chronicle.set_fact("player.reputation", 3)
	assert_spy_calls(reactor, 2)
	assert_spy_call(reactor, 1, EventCollector.SKIP, 3)

	_chronicle.set_fact("player.reputation", 5)
	assert_spy_calls(reactor, 3)
	assert_spy_call(reactor, 2, EventCollector.SKIP, 5)

	# Setting same value again — CHANGE mode should not re-fire
	_chronicle.set_fact("player.reputation", 5)
	assert_spy_calls(reactor, 3)


# Reactor with CREATION mode — only fires for new facts
func test_reactor_creation_mode_only_fires_for_new_facts() -> void:
	var reactor := add_reactor({
		watch_pattern = "npc.merchant.*",
		react_to = CompanionFactory.ReactTo.CREATION,
	})

	# New facts — each should fire
	_chronicle.set_fact("npc.merchant.greeted")
	_chronicle.set_fact("npc.merchant.relationship", 0)
	_chronicle.set_fact("npc.merchant.visits", 1)
	assert_spy_calls(reactor, 3)

	# Updates to existing facts — should not fire again
	_chronicle.set_fact("npc.merchant.relationship", 1)
	_chronicle.set_fact("npc.merchant.relationship", 2)
	_chronicle.set_fact("npc.merchant.visits", 2)
	assert_spy_calls(reactor, 3)


# ── NPC + Recorders ───────────────────────────────────────────────────────────


# Recorder logs "dialogue_started" signal as fact
func test_recorder_logs_dialogue_started_signal() -> void:
	var npc_node := add_recorder({
		trigger_signal = "dialogue_started",
		fact_key = "npc.merchant.greeted",
		value = true,
		record_mode = CompanionFactory.RecordMode.ONCE,
	})

	assert_no_fact("npc.merchant.greeted")
	npc_node.emit_signal("dialogue_started")
	assert_fact("npc.merchant.greeted", true)

	# ONCE: further emits don't change anything
	npc_node.emit_signal("dialogue_started")
	assert_fact("npc.merchant.greeted", true)
	assert_history_size("npc.merchant.greeted", 1)


# Recorder increments visit count on "npc_visited" signal
func test_recorder_increments_visit_count_on_signal() -> void:
	var npc_node := add_recorder({
		trigger_signal = "visited",
		fact_key = "npc.merchant.visits",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	})

	npc_node.emit_signal("visited")
	npc_node.emit_signal("visited")
	npc_node.emit_signal("visited")

	assert_fact("npc.merchant.visits", 3)


# Recorder ONCE mode — first interaction only
func test_recorder_once_mode_first_interaction_only() -> void:
	var npc_node := add_recorder({
		trigger_signal = "interacted",
		fact_key = "npc.merchant.first_contact",
		value = "contact_made",
		record_mode = CompanionFactory.RecordMode.ONCE,
	})

	npc_node.emit_signal("interacted")
	assert_fact("npc.merchant.first_contact", "contact_made")

	# Subsequent emits don't overwrite
	npc_node.emit_signal("interacted")
	npc_node.emit_signal("interacted")
	assert_fact("npc.merchant.first_contact", "contact_made")
	assert_history_size("npc.merchant.first_contact", 1)


# ── NPC + Serialization ───────────────────────────────────────────────────────


# NPC state (greet flags, relationship, visits) survives save/load
func test_npc_state_survives_save_load() -> void:
	_chronicle.set_fact("npc.merchant.greeted")
	_chronicle.set_fact("npc.merchant.relationship", 2)
	_chronicle.set_fact("npc.merchant.visits", 3)
	_chronicle.set_fact("npc.merchant.quest_offered")

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	assert_no_fact("npc.merchant.greeted")
	assert_no_fact("npc.merchant.relationship")

	var ok: bool = _chronicle.deserialize(data)
	assert_true(ok)

	assert_fact("npc.merchant.greeted", true)
	assert_fact("npc.merchant.relationship", 2)
	assert_fact("npc.merchant.visits", 3)
	assert_fact("npc.merchant.quest_offered", true)


# Dialogue history queryable after load
func test_dialogue_history_queryable_after_load() -> void:
	set_time(1.0)
	_chronicle.set_fact("dialogue.merchant.choice", "greet")
	set_time(2.0)
	_chronicle.set_fact("dialogue.merchant.choice", "ask_quest")
	set_time(3.0)
	_chronicle.set_fact("dialogue.merchant.choice", "accept")

	roundtrip()

	assert_history("dialogue.merchant.choice", ["greet", "ask_quest", "accept"])

	# first_change returns earliest entry, last_change returns most recent
	assert_eq(_chronicle.get_first_change("dialogue.merchant.*").value, "greet",
		"first_change returns earliest value")
	assert_eq(_chronicle.get_last_change("dialogue.merchant.*").value, "accept",
		"last_change returns most recent value")


# Active gates update correctly after deserialize
func test_gates_update_correctly_after_deserialize() -> void:
	_chronicle.set_fact("npc.merchant.greeted")
	_chronicle.set_fact("player.reputation", 5)

	var data: Dictionary = _chronicle.serialize()
	_chronicle.clear()

	# Gates built before deserialize should re-evaluate after facts are loaded
	var greet_gate := add_gate("npc.merchant.greeted")
	var rep_gate := add_gate("player.reputation >= 3")

	# Before deserialization: no facts, both gates closed
	assert_gate_closed(greet_gate)
	assert_gate_closed(rep_gate)

	_chronicle.deserialize(data)

	assert_gate_open(greet_gate)
	assert_gate_open(rep_gate)


# All NPC relationships preserved across save/load
func test_all_npc_relationships_preserved_across_save_load() -> void:
	_chronicle.set_fact("npc.merchant.relationship", 2)
	_chronicle.set_fact("npc.blacksmith.relationship", 4)
	_chronicle.set_fact("npc.innkeeper.relationship", 1)
	_chronicle.set_fact("npc.guard.relationship", 0)

	roundtrip()

	assert_facts({
		"npc.merchant.relationship": 2,
		"npc.blacksmith.relationship": 4,
		"npc.innkeeper.relationship": 1,
		"npc.guard.relationship": 0,
	})

	# Pattern query still works post-load
	var all_relationships: Array[String] = _chronicle.get_fact_keys("npc.*.relationship")
	assert_eq(all_relationships.size(), 4, "all four NPC relationships queryable by pattern")


# ── NPC + Rollback ────────────────────────────────────────────────────────────


# Rollback forgets dialogue choice
func test_rollback_forgets_dialogue_choice() -> void:
	set_time(1.0)
	_chronicle.set_fact("npc.merchant.greeted")

	set_time(2.0)
	_chronicle.set_fact("dialogue.merchant.choice", "accept")
	assert_fact("dialogue.merchant.choice", "accept")

	# Rollback to just before the dialogue choice was made
	_chronicle.rollback_to(1.5)

	assert_no_fact("dialogue.merchant.choice")
	assert_marked("npc.merchant.greeted")  # greeted survives (set before rollback point)


# Rollback un-greets NPC (resets relationship)
func test_rollback_ungreets_npc_resets_relationship() -> void:
	set_time(0.5)
	_chronicle.set_fact("player.reputation", 1)

	set_time(1.0)
	_chronicle.set_fact("npc.merchant.greeted")
	_chronicle.set_fact("npc.merchant.relationship", 0)

	set_time(2.0)
	_chronicle.set_fact("npc.merchant.relationship", 2)

	assert_fact("npc.merchant.greeted", true)
	assert_fact("npc.merchant.relationship", 2)

	# Rollback to before the greeting happened
	_chronicle.rollback_to(0.8)

	assert_no_fact("npc.merchant.greeted")
	assert_no_fact("npc.merchant.relationship")
	assert_fact("player.reputation", 1)


# Gate updates after rollback changes NPC state
func test_gate_updates_after_rollback_changes_npc_state() -> void:
	var quest_option := add_gate("npc.merchant.greeted AND npc.merchant.quest_offered")

	set_time(1.0)
	_chronicle.set_fact("npc.merchant.greeted")

	set_time(2.0)
	_chronicle.set_fact("npc.merchant.quest_offered")

	assert_gate_open(quest_option)

	# Rollback past the quest offer — greeted still present, quest_offered gone
	_chronicle.rollback_to(1.5)

	assert_gate_closed(quest_option)
	assert_marked("npc.merchant.greeted")
	assert_no_fact("npc.merchant.quest_offered")


# ── Full Playthrough ──────────────────────────────────────────────────────────


# Full NPC interaction: approach, greet, quest offered, accept, leave (10+ ops)
func test_full_npc_interaction_approach_greet_quest_accept_leave() -> void:
	# -- Stage gates for each dialogue phase --
	var greet_option := add_gate("npc.merchant.greeted")
	var quest_option := add_gate("npc.merchant.greeted AND npc.merchant.quest_offered")
	var accept_option := add_gate("dialogue.merchant.choice == \"accept\" AND npc.merchant.quest_offered")

	# Reactor records relationship changes
	var reactor := add_reactor({
		watch_pattern = "npc.merchant.relationship",
		react_to = CompanionFactory.ReactTo.ANY,
	})

	# Recorder for visit count
	var merchant_node := add_recorder({
		trigger_signal = "approached",
		fact_key = "npc.merchant.visits",
		record_mode = CompanionFactory.RecordMode.INCREMENT,
		amount = 1.0,
	})

	set_time(1.0)

	# Player approaches merchant
	merchant_node.emit_signal("approached")
	assert_fact("npc.merchant.visits", 1)

	# Player initiates first dialogue — greet
	_chronicle.set_fact("npc.merchant.greeted")
	assert_gate_open(greet_option)

	# Reputation matters
	_chronicle.set_fact("player.reputation", 2)

	# Merchant offers quest
	_chronicle.set_fact("npc.merchant.quest_offered")
	assert_gate_open(quest_option)

	# Player builds relationship
	_chronicle.set_fact("npc.merchant.relationship", 0)
	_chronicle.increment_fact("npc.merchant.relationship", 1)
	assert_spy_calls(reactor, 2)

	# Player accepts quest
	_chronicle.set_fact("dialogue.merchant.choice", "accept")
	assert_gate_open(accept_option)

	# Reputation bumped by accepting quest
	_chronicle.set_fact("player.reputation", 3)

	# Relationship improves from acceptance
	_chronicle.increment_fact("npc.merchant.relationship", 1)
	assert_fact("npc.merchant.relationship", 2)

	# Player leaves — visit recorded
	merchant_node.emit_signal("approached")
	assert_fact("npc.merchant.visits", 2)

	set_time(2.0)

	# Verify complete final state
	assert_facts({
		"npc.merchant.greeted": true,
		"npc.merchant.quest_offered": true,
		"npc.merchant.relationship": 2,
		"npc.merchant.visits": 2,
		"dialogue.merchant.choice": "accept",
		"player.reputation": 3,
	})

	# Reactor was called for each relationship change: creation (0), +1->1, +1->2
	assert_spy_calls(reactor, 3)

	# All quest-related gates in expected state
	assert_gate_open(greet_option)
	assert_gate_open(quest_option)
	assert_gate_open(accept_option)

	# Serialize — full state captured
	var data: Dictionary = _chronicle.serialize()
	assert_has(data, "facts")


# Multiple NPCs maintain independent state
func test_multiple_npcs_maintain_independent_state() -> void:
	# Three NPCs, each tracked independently
	_chronicle.set_fact("npc.merchant.greeted")
	_chronicle.set_fact("npc.merchant.relationship", 3)
	_chronicle.set_fact("npc.merchant.visits", 5)

	_chronicle.set_fact("npc.blacksmith.greeted")
	_chronicle.set_fact("npc.blacksmith.relationship", 1)
	_chronicle.set_fact("npc.blacksmith.visits", 1)

	# Guard not yet met
	assert_no_fact("npc.guard.greeted")
	assert_no_fact("npc.guard.relationship")

	# Modifying merchant does not affect blacksmith
	_chronicle.increment_fact("npc.merchant.relationship", 1)
	assert_fact("npc.merchant.relationship", 4)
	assert_fact("npc.blacksmith.relationship", 1)

	# Meeting the guard
	_chronicle.set_fact("npc.guard.greeted")
	_chronicle.set_fact("npc.guard.relationship", 0)

	# Each NPC queryable by pattern
	var merchants: Array[String] = _chronicle.get_fact_keys("npc.merchant.*")
	var blacksmiths: Array[String] = _chronicle.get_fact_keys("npc.blacksmith.*")
	var guards: Array[String] = _chronicle.get_fact_keys("npc.guard.*")
	assert_eq(merchants.size(), 3, "merchant has greeted, relationship, visits")
	assert_eq(blacksmiths.size(), 3, "blacksmith has greeted, relationship, visits")
	assert_eq(guards.size(), 2, "guard has greeted, relationship")

	# Count all greeted NPCs
	var greeted: Array[String] = _chronicle.get_fact_keys("npc.*.greeted")
	assert_eq(greeted.size(), 3, "three NPCs greeted in total")


# NPC vendor: buy/sell with gold + inventory integration
func test_npc_vendor_buy_sell_with_gold_and_inventory() -> void:
	# Starting state: player has gold, empty inventory
	_chronicle.set_fact("player.gold", 100)
	_chronicle.set_fact("npc.merchant.greeted", true)

	# Gate: buy option only available when greeted and has gold
	var buy_option := add_gate("npc.merchant.greeted AND player.gold >= 10")
	var sell_option := add_gate("npc.merchant.greeted AND inventory.sword")

	assert_gate_open(buy_option)
	assert_gate_closed(sell_option)  # no sword yet

	# Player buys a sword (costs 40 gold)
	_chronicle.set_fact("player.gold", 60)
	_chronicle.set_fact("inventory.sword")

	assert_gate_open(buy_option)   # still has gold
	assert_gate_open(sell_option)  # now has sword

	# Player sells sword back (+20 gold refund)
	_chronicle.set_fact("player.gold", 80)
	_chronicle.set_fact("inventory.sword", false)

	assert_gate_open(buy_option)
	assert_gate_closed(sell_option)  # sword gone

	# Player runs out of gold — can't buy
	_chronicle.set_fact("player.gold", 5)
	assert_gate_closed(buy_option)

	# Final state
	assert_fact("player.gold", 5)
	assert_fact("inventory.sword", false)

	# Relationship improved for both trades
	_chronicle.set_fact("npc.merchant.relationship", 2)
	assert_fact("npc.merchant.relationship", 2)


# Dialogue tree with 3 branches — all paths produce valid state
func test_dialogue_tree_three_branches_all_paths_valid() -> void:
	# Gates react to dialogue choice changes
	var accepted_gate := add_gate("dialogue.merchant.choice == \"accept\"")
	var declined_gate := add_gate("dialogue.merchant.choice == \"decline\"")

	# ── Branch A: Accept ──
	_chronicle.set_fact("npc.merchant.greeted")
	_chronicle.set_fact("npc.merchant.quest_offered")
	_chronicle.set_fact("dialogue.merchant.choice", "accept")

	assert_gate_open(accepted_gate)
	assert_gate_closed(declined_gate)
	assert_fact("dialogue.merchant.choice", "accept")

	# ── Branch B: Change choice to Decline ──
	_chronicle.set_fact("dialogue.merchant.choice", "decline")

	assert_gate_closed(accepted_gate)
	assert_gate_open(declined_gate)
	assert_fact("dialogue.merchant.choice", "decline")

	# ── Branch C: Ask for info then accept ──
	_chronicle.set_fact("dialogue.merchant.choice", "ask_info")
	_chronicle.set_fact("dialogue.merchant.info_received")

	assert_gate_closed(accepted_gate)
	assert_gate_closed(declined_gate)
	assert_marked("dialogue.merchant.info_received")

	# Finally accept after deliberation
	_chronicle.set_fact("dialogue.merchant.choice", "accept")

	assert_gate_open(accepted_gate)
	assert_gate_closed(declined_gate)

	# Full history shows the deliberation path
	assert_history("dialogue.merchant.choice", ["accept", "decline", "ask_info", "accept"])
