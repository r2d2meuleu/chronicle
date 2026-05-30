extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")
const MemoryTracker := preload("res://test/production/support/memory_tracker.gd")


func _setup_persistent_state() -> void:
	for i in 2000:
		_chronicle.set_fact("world.fact_%d" % i, i)


func _run_scene_transition(scene_idx: int) -> Array[int]:
	var ids: Array[int] = []
	var watcher_count := 50 + (scene_idx % 50)
	for i in watcher_count:
		ids.append(_chronicle.watch("scene_%d.*" % scene_idx, func(_k, _v, _o): pass))
	for i in 30:
		_chronicle.set_fact("scene_%d.obj_%d" % [scene_idx, i], scene_idx)
	for frame in 100:
		advance_time(0.016)
		_chronicle.flush_expiry()
	for wid in ids:
		_chronicle.unwatch(wid)
	var scene_keys = _chronicle.get_fact_keys("scene_%d.*" % scene_idx)
	for key in scene_keys:
		_chronicle.erase_fact(key)
	return ids


# 100 scene transitions clean up all scene watchers and keep persistent facts.
func test_100_scene_transitions() -> void:
	_setup_persistent_state()
	var baseline := MemoryTracker.snapshot()
	for scene in 100:
		_run_scene_transition(scene)
	assert_eq(_chronicle.get_stats().watcher_count, 0, "All scene watchers should be cleaned up")
	assert_fact("world.fact_0", 0)
	assert_fact("world.fact_1999", 1999)


# Repeated companion-node create/free cycles leave no leaked watchers.
func test_companion_node_lifecycle() -> void:
	_setup_persistent_state()
	for scene in 50:
		var nodes: Array[Node] = []
		for g in 10:
			var target := add_gate("world.fact_%d" % (scene * 10 + g))
			nodes.append(target)
		for r in 5:
			var reactor := add_reactor({watch_pattern = "scene_%d.*" % scene})
			nodes.append(reactor)
		_chronicle.set_fact("scene_%d.trigger" % scene, true)
		for frame in 50:
			advance_time(0.016)
			_chronicle.flush_expiry()
		for node in nodes:
			node.queue_free()
		await get_tree().process_frame
	_chronicle.set_auto_advancing(true)
	for frame in 65:
		await get_tree().process_frame
	assert_eq(_chronicle.get_stats().watcher_count, 0)


# Frequent watcher register/unregister churn does not destabilize glob buckets.
func test_glob_bucket_rebuild_frequency() -> void:
	_setup_persistent_state()
	for scene in 100:
		var ids: Array[int] = []
		for i in 20:
			ids.append(_chronicle.watch("scene_%d.*" % scene, func(_k, _v, _o): pass))
		_chronicle.set_fact("scene_%d.test" % scene, true)
		for wid in ids:
			_chronicle.unwatch(wid)
		_chronicle.erase_fact("scene_%d.test" % scene)
	# Correctness: after 100 churn cycles, no watchers leak and only the
	# persistent world facts remain (scene facts were erased each cycle).
	assert_watcher_count(0)
	assert_fact_count("*", 2000)
	assert_fact_count("scene_*", 0)
	assert_fact("world.fact_0", 0)
	assert_fact("world.fact_1999", 1999)


# Watch IDs stay strictly monotonic across heavy register/unwatch churn.
func test_watch_id_monotonicity() -> void:
	_setup_persistent_state()
	var all_ids: Array[int] = []
	for scene in 200:
		var ids: Array[int] = []
		for i in 50:
			var wid = _chronicle.watch("mono_%d.key_%d" % [scene, i], func(_k, _v, _o): pass)
			ids.append(wid)
			all_ids.append(wid)
		for wid in ids:
			_chronicle.unwatch(wid)
	for i in range(1, all_ids.size()):
		assert_gt(all_ids[i], all_ids[i - 1], "IDs must be strictly monotonic at index %d" % i)


# Pruning invalid (freed-node) watchers under churn stays stable.
func test_prune_invalid_under_churn() -> void:
	_setup_persistent_state()
	const SpyNode := preload("res://test/support/chronicle_spy_node.gd")
	for scene in 50:
		var nodes: Array[Node] = []
		for i in 100:
			var node := add_node("prunable_%d_%d" % [scene, i])
			node.set_script(SpyNode)
			nodes.append(node)
			# Bound method on the node: the Callable goes invalid when the node
			# is freed, which is exactly what prune_invalid() detects.
			_chronicle.watch("prune.key", node.on_fact)
		assert_watcher_count(100)
		for i in range(0, 100, 2):
			nodes[i].queue_free()
		_chronicle.set_auto_advancing(true)
		for frame in 65:
			await get_tree().process_frame
		# Correctness: the 50 watchers bound to freed nodes are pruned (their
		# Callables are now invalid), leaving only the 50 still-live ones.
		assert_watcher_count(50)
		# Firing the key must not crash, and exactly the 50 surviving live nodes
		# record the call (the pruned freed-node watchers do not fire).
		_chronicle.set_fact("prune.key", true)
		var fired := 0
		for i in range(1, 100, 2):
			if is_instance_valid(nodes[i]) and (nodes[i].calls as Array).size() == 1:
				fired += 1
		assert_eq(fired, 50,
			"Exactly 50 live-node watchers should fire after pruning (scene %d)" % scene)
		_chronicle.erase_fact("prune.key")
		_chronicle.unwatch_all()
		assert_watcher_count(0)
	# Persistent state is untouched by 50 cycles of prune churn.
	assert_fact_count("world.*", 2000)
	assert_fact("world.fact_0", 0)


# Persistent global watchers keep firing after many transient scene watchers churn.
func test_mixed_persistent_and_scene_watchers() -> void:
	_setup_persistent_state()
	var global_fire_count := [0]
	var global_ids: Array[int] = []
	for i in 20:
		global_ids.append(_chronicle.watch("world.fact_%d" % i, func(_k, _v, _o): global_fire_count[0] += 1))
	for scene in 50:
		var scene_ids: Array[int] = []
		for i in 50:
			scene_ids.append(_chronicle.watch("scene_%d.*" % scene, func(_k, _v, _o): pass))
		_chronicle.set_fact("scene_%d.event" % scene, true)
		for wid in scene_ids:
			_chronicle.unwatch(wid)
		_chronicle.erase_fact("scene_%d.event" % scene)
	global_fire_count[0] = 0
	_chronicle.set_fact("world.fact_0", 9999)
	# Only the single watcher registered on world.fact_0 matches this write, so it
	# fires exactly once — proving persistent watchers survive the scene churn.
	assert_eq(global_fire_count[0], 1, "world.fact_0 watcher should fire exactly once after 50 scene transitions")
	for wid in global_ids:
		_chronicle.unwatch(wid)
