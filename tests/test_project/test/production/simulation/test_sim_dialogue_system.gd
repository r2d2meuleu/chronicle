extends ChronicleTestSuite


func _setup_world() -> void:
	for i in 100:
		_chronicle.set_facts({
			"npc_%d.trust" % i: 0,
			"npc_%d.met" % i: false,
			"npc_%d.conversation_count" % i: 0,
		})
	for i in 50:
		_chronicle.set_fact("story.flag_%d" % i, false)
	for i in 30:
		_chronicle.set_fact("player.attr_%d" % i, 10)
	for i in 200:
		_chronicle.set_fact("dialogue.option_%d" % i, false)


# Building 500 expression gates across the dialogue tree compiles and evaluates correctly.
func test_dialogue_tree_setup() -> void:
	_setup_world()
	var targets: Array[Node2D] = []
	for i in 100:
		targets.append(add_gate("npc_%d.met" % (i % 100)))
	for i in range(100, 250):
		targets.append(add_gate("npc_%d.trust >= %d AND player.attr_0 >= 5" % [i % 100, (i % 10) + 1]))
	for i in range(250, 400):
		targets.append(add_gate(
			"npc_%d.trust >= 3 AND story.flag_%d AND NOT story.flag_%d AND player.attr_%d >= 8"
			% [i % 100, i % 50, (i + 1) % 50, i % 30]
		))
	for i in range(400, 500):
		targets.append(add_gate("npc_%d.trust >= 5 AND story.flag_0 AND story.flag_1 AND player.attr_0 >= 10 AND player.attr_1 >= 10 AND NOT story.flag_49 AND npc_%d.met AND npc_%d.conversation_count >= 3" % [i % 100, i % 100, i % 100]))
	assert_eq(targets.size(), 500)
	# Representative gate from each tier — all conditions are unmet on the default world,
	# so a working expression compiler holds every gate closed.
	# targets[0]   tier1 (i=0):   npc_0.met
	# targets[100] tier2 (i=100): npc_0.trust >= 1 AND player.attr_0 >= 5
	# targets[250] tier3 (i=250): npc_50.trust >= 3 AND story.flag_0 AND NOT story.flag_1 AND player.attr_10 >= 8
	# targets[400] tier4 (i=400): npc_0.trust >= 5 AND ... AND npc_0.conversation_count >= 3
	for idx in [0, 100, 250, 400]:
		assert_gate_closed(targets[idx])
	# Satisfy tiers 1-3 (leaving story.flag_1 false, which tier3 requires; player.attr_10
	# defaults to 10 >= 8); a broken compound compiler would mis-evaluate one of these.
	_chronicle.set_fact("npc_0.met", true)
	_chronicle.set_fact("npc_0.trust", 10)
	_chronicle.set_fact("npc_50.trust", 10)
	_chronicle.set_fact("story.flag_0", true)
	assert_gate_open(targets[0])
	assert_gate_open(targets[100])
	assert_gate_open(targets[250])
	# Tier4 stays closed: conversation_count (0) < 3 and story.flag_1 is still false.
	assert_gate_closed(targets[400])


# Meeting an NPC and raising trust opens its conversation gate.
func test_conversation_flow() -> void:
	_setup_world()
	var gates: Array[Node2D] = []
	for i in 10:
		gates.append(add_gate("npc_%d.met AND npc_%d.trust >= 3" % [i, i]))
	for i in 10:
		assert_gate_closed(gates[i])
	for i in 10:
		_chronicle.set_fact("npc_%d.met" % i, true)
		_chronicle.set_fact("npc_%d.trust" % i, 5)
	for i in 10:
		assert_gate_open(gates[i])


# Trust thresholds open/close gates as the level climbs.
func test_trust_progression() -> void:
	_setup_world()
	var gate_3 := add_gate("npc_0.trust >= 3")
	var gate_7 := add_gate("npc_0.trust >= 7")
	assert_gate_closed(gate_3)
	assert_gate_closed(gate_7)
	for level in 11:
		_chronicle.set_fact("npc_0.trust", level)
		if level >= 3:
			assert_gate_open(gate_3)
		else:
			assert_gate_closed(gate_3)
		if level >= 7:
			assert_gate_open(gate_7)
		else:
			assert_gate_closed(gate_7)


# Setting story flags one by one opens only the matching branch gate.
func test_story_branch_explosion() -> void:
	_setup_world()
	var gates: Array[Node2D] = []
	for i in 20:
		gates.append(add_gate("story.flag_%d" % i))
	for i in 20:
		assert_gate_closed(gates[i])
	for i in 20:
		_chronicle.set_fact("story.flag_%d" % i, true)
		assert_gate_open(gates[i])
		for j in range(i + 1, 20):
			assert_gate_closed(gates[j])


# BETWEEN expression gates open only within their range as the attr changes.
func test_expression_with_between() -> void:
	_setup_world()
	var gates: Array[Node2D] = []
	for i in 50:
		var low := (i % 10) + 1
		var high := low + 5
		gates.append(add_gate("player.attr_0 BETWEEN %d AND %d" % [low, high]))
	for level in 21:
		_chronicle.set_fact("player.attr_0", level)
		for g_idx in 50:
			var low := (g_idx % 10) + 1
			var high := low + 5
			if level >= low and level <= high:
				assert_gate_open(gates[g_idx])
			else:
				assert_gate_closed(gates[g_idx])


# Dialogue gate state survives a save roundtrip.
func test_save_load_dialogue_state() -> void:
	_setup_world()
	var targets: Array[Node2D] = []
	for i in 50:
		_chronicle.set_fact("npc_%d.met" % i, true)
		targets.append(add_gate("npc_%d.met" % i))
	for t in targets:
		assert_gate_open(t)
	roundtrip()
	for t in targets:
		assert_gate_open(t)
