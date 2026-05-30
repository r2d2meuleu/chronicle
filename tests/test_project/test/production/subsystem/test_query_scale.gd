extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# get_facts("*") at 10k — full store deep copy
func test_get_facts_wildcard_10k() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 2000, 5)
	var all_facts = _chronicle.get_facts("*")
	assert_eq(all_facts.size(), 10000)


# get_facts("*") at 50k
func test_get_facts_wildcard_50k() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 10000, 5)
	var all_facts = _chronicle.get_facts("*")
	assert_eq(all_facts.size(), 50000)


# Entity filter returns only matching entity
func test_entity_filter_efficiency() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 100, 100)
	var keys = _chronicle.get_fact_keys("entity_50.*")
	assert_eq(keys.size(), 100)
	for key in keys:
		assert_true(key.begins_with("entity_50."))


# count_facts should be cheaper than get_facts().size()
func test_count_vs_get_facts() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 10000, 5)
	var count_time = ScaleHelper.time_callable(func(): _chronicle.count_facts("*"))
	var get_time = ScaleHelper.time_callable(func(): _chronicle.get_facts("*").size())
	gut.p("count_facts: %.0f us, get_facts().size(): %.0f us" % [count_time, get_time])
	assert_fact_count("*", 50000)


# get_fact_history with interleaved writes triggers key index rebuild
func test_fact_history_rebuild_cost() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 10000)
	for i in 5000:
		set_time(float(i) * 0.01)
		_chronicle.set_fact("history.target", i)
	var history = _chronicle.get_fact_history("history.target")
	assert_eq(history.size(), 5000)
	assert_eq(history[0].value, 0)
	assert_eq(history[-1].value, 4999)
	for write_idx in 100:
		_chronicle.set_fact("history.other_%d" % write_idx, write_idx)
		var h = _chronicle.get_fact_history("history.target")
		assert_eq(h.size(), 5000)


# get_first_change linear scan — match at timeline end
func test_first_change_linear_scan() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	for i in 49999:
		set_time(float(i) * 0.001)
		_chronicle.set_fact("common.k_%d" % (i % 100), i)
	set_time(49.999)
	_chronicle.set_fact("rare.needle", true)
	var first = _chronicle.get_first_change("rare.*")
	assert_not_null(first)
	assert_eq(first.key, "rare.needle")


# changes_since with bisect at various time points
func test_changes_since_bisect() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	for i in 50000:
		set_time(float(i) * 0.001)
		_chronicle.set_fact("bisect.k_%d" % (i % 200), i)
	for fraction in [0.1, 0.25, 0.5, 0.75, 0.9]:
		var since_time = 50.0 * fraction
		var changes = _chronicle.get_changes_since(since_time)
		assert_gt(changes.size(), 0, "changes_since(%.1f) should return matching entries" % since_time)
		for entry in changes:
			assert_gte(entry.time, since_time, "Entry time must be >= since_time")


# Leading wildcard penalty — "*.locked" scans all keys
func test_leading_wildcard_penalty() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 10000, 5)
	for i in 100:
		_chronicle.set_fact("lock_%d.locked" % i, true)
	var entity_time = ScaleHelper.time_callable(func(): _chronicle.get_fact_keys("entity_0.*"))
	var wild_time = ScaleHelper.time_callable(func(): _chronicle.get_fact_keys("*.locked"))
	gut.p("entity_0.*: %.0f us, *.locked: %.0f us" % [entity_time, wild_time])
	var locked = _chronicle.get_fact_keys("*.locked")
	assert_eq(locked.size(), 100)
