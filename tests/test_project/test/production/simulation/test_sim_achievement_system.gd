extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


func _setup_stats() -> void:
	for i in 200:
		_chronicle.set_fact("stats.counter_%d" % i, 0)
	for i in 100:
		_chronicle.set_fact("milestone.flag_%d" % i, false)


# Registering 500+ achievement watchers tracks the expected watcher count.
func test_achievement_registration() -> void:
	_setup_stats()
	var watcher_ids: Array[int] = []
	for ach in 500:
		var pattern := "stats.counter_%d" % (ach % 200)
		var wid = _chronicle.watch(pattern, func(_k, _v, _o): pass)
		watcher_ids.append(wid)
		if ach % 2 == 0:
			var wid2 = _chronicle.watch("stats.*", func(_k, _v, _o): pass)
			watcher_ids.append(wid2)
	# 500 per-counter watchers + one extra for each of the 250 even achievements = 750.
	assert_eq(watcher_ids.size(), 750, "500 base + 250 even-achievement watchers")
	assert_eq(_chronicle.get_stats().watcher_count, watcher_ids.size())


# Incrementing a stat fans out to all watchers on that key.
func test_stat_increment_fanout() -> void:
	_setup_stats()
	var fire_count := [0]
	for i in 50:
		_chronicle.watch("stats.counter_0", func(_k, _v, _o): fire_count[0] += 1)
	_chronicle.increment_fact("stats.counter_0")
	assert_eq(fire_count[0], 50, "All 50 watchers should fire")
	assert_fact("stats.counter_0", 1)


# A stat threshold cascades through achievement and milestone unlocks.
func test_cascade_unlock() -> void:
	_setup_stats()
	_chronicle.watch("stats.counter_0", func(_k, v, _o):
		if v is int and v >= 100:
			_chronicle.set_fact("achievement.century", true)
	)
	_chronicle.watch("achievement.century", func(_k, v, _o):
		if v == true:
			_chronicle.set_fact("milestone.flag_0", true)
	)
	for i in 100:
		_chronicle.increment_fact("stats.counter_0")
	assert_fact("stats.counter_0", 100)
	assert_fact("achievement.century", true)
	assert_fact("milestone.flag_0", true)


# Overlapping glob/exact watchers each fire their full count on one write.
func test_overlapping_glob_patterns() -> void:
	_setup_stats()
	var broad_fired := [0]
	var entity_fired := [0]
	var exact_fired := [0]
	for i in 200:
		_chronicle.watch("stats.*", func(_k, _v, _o): broad_fired[0] += 1)
	for i in 100:
		_chronicle.watch("stats.counter_0", func(_k, _v, _o): entity_fired[0] += 1)
	for i in 50:
		_chronicle.watch("stats.counter_0", func(_k, _v, _o): exact_fired[0] += 1)
	_chronicle.set_fact("stats.counter_0", 42)
	assert_eq(exact_fired[0], 50)
	assert_eq(entity_fired[0], 100)
	assert_eq(broad_fired[0], 200)


# Unlocked achievements survive a save roundtrip and watchers rebind.
func test_achievement_save_integrity() -> void:
	_setup_stats()
	for i in 100:
		_chronicle.set_fact("achievement.unlocked_%d" % i, true)
	roundtrip()
	var events := watch_events("achievement.*")
	for i in 100:
		assert_fact("achievement.unlocked_%d" % i, true)
	_chronicle.set_fact("achievement.unlocked_0", false)
	events.assert_count(1)


# A bulk stat update fires the watcher once per entry and writes all values.
func test_bulk_stat_update() -> void:
	_setup_stats()
	var events := watch_events("stats.*")
	var batch := {}
	for i in 50:
		batch["stats.counter_%d" % i] = 100
	_chronicle.set_facts(batch)
	events.assert_count(50)
	for i in 50:
		assert_fact("stats.counter_%d" % i, 100)


# Scene-change watcher cleanup zeroes the count and re-registers with fresh IDs.
func test_watcher_cleanup_on_scene_change() -> void:
	_setup_stats()
	var ids: Array[int] = []
	for i in 1000:
		ids.append(_chronicle.watch("stats.counter_%d" % (i % 200), func(_k, _v, _o): pass))
	assert_eq(_chronicle.get_stats().watcher_count, 1000)
	for wid in ids:
		_chronicle.unwatch(wid)
	assert_eq(_chronicle.get_stats().watcher_count, 0)
	var new_ids: Array[int] = []
	for i in 1000:
		new_ids.append(_chronicle.watch("stats.counter_%d" % (i % 200), func(_k, _v, _o): pass))
	assert_eq(_chronicle.get_stats().watcher_count, 1000)
	for i in new_ids.size():
		assert_gt(new_ids[i], ids[-1], "New IDs should be strictly greater than old IDs")
