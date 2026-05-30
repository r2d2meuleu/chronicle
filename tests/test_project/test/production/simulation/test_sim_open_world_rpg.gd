extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")

const NPC_COUNT := 200
const QUEST_COUNT := 150
const LOCATION_COUNT := 500
const ITEM_COUNT := 300
const STAT_COUNT := 50
const WORLD_FLAG_COUNT := 200


func _setup_world() -> void:
	for i in NPC_COUNT:
		_chronicle.set_facts({
			"npc_%d.alive" % i: true,
			"npc_%d.disposition" % i: 50,
			"npc_%d.location" % i: "town_%d" % (i % 10),
			"npc_%d.quest_giver" % i: i < 50,
			"npc_%d.dialogue_state" % i: "idle",
		})
	for i in QUEST_COUNT:
		_chronicle.set_facts({
			"quest_%d.status" % i: "locked",
			"quest_%d.stage" % i: 0,
			"quest_%d.objectives_complete" % i: 0,
			"quest_%d.reward_claimed" % i: false,
			"quest_%d.started_time" % i: 0.0,
			"quest_%d.prerequisites_met" % i: i < 10,
			"quest_%d.branch_chosen" % i: "none",
			"quest_%d.journal_entry" % i: "",
		})
	for i in LOCATION_COUNT:
		_chronicle.set_facts({
			"location_%d.discovered" % i: i < 5,
			"location_%d.cleared" % i: false,
			"location_%d.fast_travel" % i: i < 2,
		})
	for i in ITEM_COUNT:
		_chronicle.set_facts({
			"item_%d.acquired" % i: false,
			"item_%d.quantity" % i: 0,
		})
	for i in STAT_COUNT:
		_chronicle.set_fact("player.stat_%d" % i, 10)
	for i in WORLD_FLAG_COUNT:
		_chronicle.set_fact("world.flag_%d" % i, false)


# World setup — batch write ~4,550 facts
func test_world_setup() -> void:
	_setup_world()
	var expected_total := NPC_COUNT * 5 + QUEST_COUNT * 8 + LOCATION_COUNT * 3 + ITEM_COUNT * 2 + STAT_COUNT + WORLD_FLAG_COUNT
	assert_fact_count("*", expected_total)
	assert_fact("npc_0.alive", true)
	assert_fact("quest_0.status", "locked")
	assert_fact("location_0.discovered", true)
	assert_fact("player.stat_0", 10)


# Quest progression — advance stages, evaluate prerequisites, toggle NPC states
func test_quest_progression() -> void:
	_setup_world()
	for q in 20:
		_chronicle.set_fact("quest_%d.status" % q, "active")
		_chronicle.set_fact("quest_%d.stage" % q, 1)
		set_time(float(q) + 1.0)
		_chronicle.set_fact("quest_%d.started_time" % q, _chronicle.get_game_time())
		for obj in 3:
			_chronicle.increment_fact("quest_%d.objectives_complete" % q)
		_chronicle.set_fact("quest_%d.status" % q, "complete")
		_chronicle.set_fact("quest_%d.reward_claimed" % q, true)
		_chronicle.set_fact("npc_%d.dialogue_state" % q, "quest_done")
	for q in 20:
		assert_fact("quest_%d.status" % q, "complete")
		assert_fact("quest_%d.objectives_complete" % q, 3)
		assert_fact("quest_%d.reward_claimed" % q, true)
	assert_fact("quest_20.status", "locked")


# Explore 100 locations — verify state correctness
func test_exploration_discovery() -> void:
	_setup_world()
	for loc in range(5, 105):
		_chronicle.set_fact("location_%d.discovered" % loc, true)
		_chronicle.set_fact("location_%d.fast_travel" % loc, true)
	for loc in range(5, 105):
		assert_fact("location_%d.discovered" % loc, true)
		assert_fact("location_%d.fast_travel" % loc, true)
	assert_fact("location_0.discovered", true)
	assert_fact("location_104.discovered", true)
	assert_fact("location_199.discovered", false)


# Combat — kill 50 NPCs, increment counters, check gates
func test_combat_encounter() -> void:
	_setup_world()
	_chronicle.set_fact("player.kills", 0)
	var kill_gate := add_gate("player.kills >= 25")
	assert_gate_closed(kill_gate)
	for npc in 50:
		_chronicle.set_fact("npc_%d.alive" % npc, false)
		_chronicle.increment_fact("player.kills")
	assert_fact("player.kills", 50)
	for npc in 50:
		assert_fact("npc_%d.alive" % npc, false)
	assert_fact("npc_50.alive", true)
	assert_gate_open(kill_gate)


# Inventory management — acquire/drop/trade items
func test_inventory_management() -> void:
	_setup_world()
	for i in 200:
		_chronicle.set_fact("item_%d.acquired" % i, true)
		_chronicle.set_fact("item_%d.quantity" % i, (i % 10) + 1)
	for i in range(0, 50):
		_chronicle.erase_fact("item_%d.acquired" % i)
		_chronicle.erase_fact("item_%d.quantity" % i)
	var trade_batch := {}
	for i in range(50, 60):
		trade_batch["item_%d.quantity" % i] = 99
	_chronicle.set_facts(trade_batch)
	for i in range(50, 60):
		assert_fact("item_%d.quantity" % i, 99)
	assert_no_fact("item_0.acquired")
	assert_fact("item_100.acquired", true)


# Save/load midgame — serialize ~8k facts, roundtrip
func test_save_load_midgame() -> void:
	_setup_world()
	for q in 20:
		_chronicle.set_fact("quest_%d.status" % q, "complete")
	for npc in 30:
		_chronicle.set_fact("npc_%d.alive" % npc, false)
	var pre_save_count = _chronicle.count_facts("*")
	var data = _chronicle.serialize()
	_chronicle.clear()
	assert_fact_count("*", 0)
	_chronicle.deserialize(data)
	assert_fact_count("*", pre_save_count)
	assert_fact("quest_0.status", "complete")
	assert_fact("quest_20.status", "locked")
	assert_fact("npc_0.alive", false)
	assert_fact("npc_30.alive", true)
	assert_fact("player.stat_0", 10)


# Rollback a quest branch decision
func test_rollback_quest_decision() -> void:
	_setup_world()
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	set_time(10.0)
	_chronicle.set_fact("quest_0.branch_chosen", "none")
	set_time(11.0)
	_chronicle.set_fact("quest_0.branch_chosen", "path_a")
	_chronicle.set_fact("quest_0.stage", 5)
	for i in 500:
		set_time(11.0 + float(i) * 0.01)
		_chronicle.set_fact("progress.step_%d" % (i % 50), i)
	_chronicle.rollback_to(10.5)
	assert_fact("quest_0.branch_chosen", "none")
	assert_fact("quest_0.stage", 0)


# Full session — all phases in sequence
func test_full_session() -> void:
	_setup_world()
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	set_time(1.0)
	for q in 10:
		_chronicle.set_fact("quest_%d.status" % q, "active")
		_chronicle.increment_fact("quest_%d.objectives_complete" % q)
	set_time(2.0)
	for loc in range(5, 30):
		_chronicle.set_fact("location_%d.discovered" % loc, true)
	set_time(3.0)
	for npc in 10:
		_chronicle.set_fact("npc_%d.alive" % npc, false)
		_chronicle.increment_fact("player.kills", 1)
	set_time(4.0)
	for i in 50:
		_chronicle.set_fact("item_%d.acquired" % i, true)
	roundtrip()
	assert_fact("quest_0.status", "active")
	assert_fact("location_10.discovered", true)
	assert_fact("npc_0.alive", false)
	assert_fact("player.kills", 10)
	assert_fact("item_0.acquired", true)
