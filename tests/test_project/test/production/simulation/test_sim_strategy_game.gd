extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")

const UNIT_COUNT := 500
const REGION_COUNT := 100
const FACTION_COUNT := 8
const BUILDING_COUNT := 200


func _setup_world() -> void:
	for i in UNIT_COUNT:
		_chronicle.set_facts({
			"unit_%d.type" % i: ["infantry", "cavalry", "archer"][i % 3],
			"unit_%d.health" % i: 100,
			"unit_%d.region" % i: i % REGION_COUNT,
			"unit_%d.owner" % i: i % FACTION_COUNT,
		})
	for i in REGION_COUNT:
		_chronicle.set_facts({
			"region_%d.owner" % i: i % FACTION_COUNT,
			"region_%d.population" % i: 1000 + i * 10,
			"region_%d.production" % i: 50 + i,
			"region_%d.morale" % i: 75,
			"region_%d.fortified" % i: i < 10,
		})
	for i in FACTION_COUNT:
		_chronicle.set_facts({
			"faction_%d.gold" % i: 1000,
			"faction_%d.military_power" % i: 100,
			"faction_%d.reputation" % i: 50,
			"faction_%d.alliance" % i: -1,
			"faction_%d.at_war_with" % i: -1,
			"faction_%d.tech_level" % i: 1,
		})
	for i in BUILDING_COUNT:
		_chronicle.set_facts({
			"building_%d.type" % i: ["barracks", "farm", "market"][i % 3],
			"building_%d.region" % i: i % REGION_COUNT,
			"building_%d.operational" % i: true,
		})


# 100 turns of bulk region updates reach the final production values.
func test_turn_processing() -> void:
	_setup_world()
	for turn in 100:
		var updates := {}
		for r in REGION_COUNT:
			updates["region_%d.production" % r] = 50 + r + turn
		_chronicle.set_facts(updates)
	for r in REGION_COUNT:
		assert_fact("region_%d.production" % r, 50 + r + 99)


# Battle damage increments leave each defender at the expected HP.
func test_battle_resolution() -> void:
	_setup_world()
	for i in 200:
		var attacker := i
		var defender := i + 200
		_chronicle.increment_fact("unit_%d.health" % defender, -30)
		_chronicle.increment_fact("unit_%d.health" % attacker, -15)
	for i in 200:
		assert_fact("unit_%d.health" % (i + 200), 70)


# A declaration of war cascades to an allied faction via a watcher.
func test_diplomacy_cascade() -> void:
	_setup_world()
	_chronicle.set_fact("faction_0.alliance", 1)
	_chronicle.set_fact("faction_1.alliance", 0)
	_chronicle.watch("faction_0.at_war_with", func(_k, _v, _o):
		var ally: int = _chronicle.get_fact("faction_0.alliance")
		if ally >= 0:
			_chronicle.set_fact("faction_%d.at_war_with" % ally, _v)
	)
	_chronicle.set_fact("faction_0.at_war_with", 2)
	assert_fact("faction_1.at_war_with", 2)


# End-of-game scoring sees every faction's six facts populated.
func test_end_of_game_scoring() -> void:
	_setup_world()
	for f in FACTION_COUNT:
		var facts = _chronicle.get_facts("faction_%d.*" % f)
		assert_eq(facts.size(), 6, "Each faction should have 6 facts")
		assert_true(facts.values().all(func(v): return v != null), "Every faction fact must be non-null")


# Rolling back to a prior turn restores turn and region state.
func test_turn_rollback() -> void:
	_setup_world()
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	for turn in 10:
		set_time(float(turn) + 1.0)
		_chronicle.set_fact("turn.current", turn)
		for r in 10:
			_chronicle.set_fact("region_%d.production" % r, 50 + r + turn)
	assert_fact("turn.current", 9)
	_chronicle.rollback_to(8.0)
	assert_fact("turn.current", 7)
	assert_fact("region_0.production", 57)


# A mid-game save restores the snapshotted gold, discarding later writes.
func test_save_between_turns() -> void:
	_setup_world()
	for turn in 100:
		_chronicle.set_fact("turn.current", turn)
		_chronicle.set_fact("faction_0.gold", 1000 + turn * 10)
	var snapshot_gold = _chronicle.get_fact("faction_0.gold")
	var data = _chronicle.serialize()
	_chronicle.set_fact("faction_0.gold", 99999)
	_chronicle.clear()
	_chronicle.deserialize(data)
	assert_fact("faction_0.gold", snapshot_gold)
