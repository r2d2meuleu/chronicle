extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# 100 exact watchers on one key — baseline fan-out
func test_exact_fanout_100() -> void:
	_run_exact_fanout(100)


# 1000 exact watchers — production scale
func test_exact_fanout_1000() -> void:
	_run_exact_fanout(1000)


# 5000 exact watchers — enterprise ceiling
func test_exact_fanout_5000() -> void:
	_run_exact_fanout(5000)


func _run_exact_fanout(count: int) -> void:
	var fire_counts: Array[int] = []
	fire_counts.resize(count)
	fire_counts.fill(0)
	for i in count:
		var idx := i
		_chronicle.watch("fanout.target", func(_k, _v, _o): fire_counts[idx] += 1)
	_chronicle.set_fact("fanout.target", 42)
	for i in count:
		assert_eq(fire_counts[i], 1, "Watcher %d should fire exactly once" % i)


# 500 glob watchers on entity pattern
func test_glob_fanout_500() -> void:
	_run_glob_fanout(500)


# 1000 glob watchers — scaling wall test
func test_glob_fanout_1000() -> void:
	_run_glob_fanout(1000)


func _run_glob_fanout(count: int) -> void:
	var fired := [0]
	for i in count:
		_chronicle.watch("player.*", func(_k, _v, _o): fired[0] += 1)
	_chronicle.set_fact("player.health", 100)
	assert_eq(fired[0], count, "All %d glob watchers should fire" % count)


# Any-entity glob penalty — watchers on "*.locked" scanned on every dispatch
func test_any_entity_glob_penalty() -> void:
	var wild_fired := [0]
	for i in 500:
		_chronicle.watch("*.locked", func(_k, _v, _o): wild_fired[0] += 1)
	_chronicle.set_fact("player.gold", 100)
	assert_eq(wild_fired[0], 0, "*.locked watchers should NOT fire for player.gold")
	_chronicle.set_fact("chest.locked", true)
	assert_eq(wild_fired[0], 500, "All *.locked watchers should fire for chest.locked")


# Entity bucket isolation — only matching entity bucket fires
func test_entity_bucket_isolation() -> void:
	var player_fired := [0]
	var enemy_fired := [0]
	for i in 500:
		_chronicle.watch("player.*", func(_k, _v, _o): player_fired[0] += 1)
		_chronicle.watch("enemy.*", func(_k, _v, _o): enemy_fired[0] += 1)
	_chronicle.set_fact("player.x", 10)
	assert_eq(player_fired[0], 500)
	assert_eq(enemy_fired[0], 0, "Enemy watchers should NOT fire for player.x")


# Cascade depth limit triggers deferred queue
func test_cascade_depth_limit() -> void:
	var chain_fired: Array[bool] = []
	chain_fired.resize(10)
	chain_fired.fill(false)
	for i in 10:
		var idx := i
		var next_key := "chain.step_%d" % (i + 1) if i < 9 else ""
		_chronicle.watch("chain.step_%d" % i, func(_k, _v, _o):
			chain_fired[idx] = true
			if not next_key.is_empty():
				_chronicle.set_fact(next_key, true)
		)
	_chronicle.set_fact("chain.step_0", true)
	for i in 10:
		assert_true(chain_fired[i], "Chain step %d should have fired" % i)


# Depth-1 callback writes all execute inline — no deferral at low depth
func test_inline_writes_from_callback() -> void:
	var fired_count := [0]
	_chronicle.watch("trigger.key", func(_k, _v, _o):
		for i in 100:
			_chronicle.set_fact("inline.item_%d" % i, true)
		fired_count[0] += 1
	)
	_chronicle.set_fact("trigger.key", true)
	assert_eq(fired_count[0], 1)
	var stored := 0
	for i in 100:
		if _chronicle.has_fact("inline.item_%d" % i):
			stored += 1
	assert_eq(stored, 100, "All 100 writes from depth-1 callback should execute inline")


# Prune invalid watchers at scale — uses real frames for prune_invalid cycle
func test_prune_invalid_at_scale() -> void:
	const SpyNode := preload("res://test/support/chronicle_spy_node.gd")
	_chronicle.set_auto_advancing(true)
	var nodes: Array[Node] = []
	for i in 5000:
		var node := add_node("watcher_%d" % i)
		node.set_script(SpyNode)
		nodes.append(node)
		# Bind the callback to the node so freeing the node invalidates it (drives prune).
		_chronicle.watch("prune.key", node.on_fact)
	for i in range(0, 5000, 2):
		nodes[i].queue_free()
	for j in 65:
		await get_tree().process_frame
	_chronicle.set_fact("prune.key", true)
	var stats = _chronicle.get_stats()
	assert_lt(stats.watcher_count, 5000, "Dead watchers should be pruned")


# Watch/unwatch churn — no leaked IDs
func test_watch_unwatch_churn() -> void:
	var all_ids: Array[int] = []
	for cycle in 100:
		var ids: Array[int] = []
		for i in 100:
			var wid = _chronicle.watch("churn.key_%d" % (i % 10), func(_k, _v, _o): pass)
			ids.append(wid)
			all_ids.append(wid)
		for wid in ids:
			_chronicle.unwatch(wid)
	assert_eq(_chronicle.get_stats().watcher_count, 0, "All watchers should be unwatched")
	for i in range(1, all_ids.size()):
		assert_gt(all_ids[i], all_ids[i - 1], "Watch IDs must be strictly monotonic")


# Batch and sequential writes each fire the glob watcher once per changed key
func test_batch_and_sequential_each_fire_once_per_changed_key() -> void:
	var batch_events := watch_events("batch.*")
	var entries := {}
	for i in 100:
		entries["batch.key_%d" % i] = i
	_chronicle.set_facts(entries)
	batch_events.assert_count(100)
	var seq_events := watch_events("seq.*")
	for i in 100:
		_chronicle.set_fact("seq.key_%d" % i, i)
	seq_events.assert_count(100)
