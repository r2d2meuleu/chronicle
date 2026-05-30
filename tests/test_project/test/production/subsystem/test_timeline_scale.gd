extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# Fill timeline to exact capacity, verify boundary entries accessible
func test_fill_to_cap() -> void:
	var cap := 10000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	for i in cap:
		set_time(float(i))
		_chronicle.set_fact("fill.key_%d" % (i % 100), i)
	var first = _chronicle.get_first_change("*")
	var last = _chronicle.get_last_change("*")
	assert_not_null(first)
	assert_not_null(last)
	assert_eq(last.value, cap - 1)


# Overflow drops oldest entries silently
func test_overflow_silent_drop() -> void:
	var cap := 5000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	for i in cap + 1000:
		set_time(float(i) * 0.01)
		_chronicle.set_fact("overflow.k_%d" % (i % 200), i)
	var first = _chronicle.get_first_change("*")
	assert_not_null(first)
	# 6000 writes at t = i*0.01, cap 5000: the oldest ~1000 entries drop, so the
	# earliest surviving entry is index ~1000 at t ~= 10.0. Pin a tight lower bound.
	assert_gte(first.time, 9.0, "Oldest entries should have been dropped (earliest survivor ~t=10.0)")
	var last = _chronicle.get_last_change("*")
	assert_eq(last.value, cap + 999)


# Resize cap under load preserves newest entries
func test_cap_resize_under_load() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 10000)
	for i in 10000:
		set_time(float(i) * 0.001)
		_chronicle.set_fact("resize.k_%d" % (i % 50), i)
	ScaleHelper.setup_timeline_cap(_chronicle, 5000)
	var changes = _chronicle.get_changes_since(0.0)
	assert_lte(changes.size(), 5000, "Timeline should be capped at new size")
	var last = _chronicle.get_last_change("*")
	assert_eq(last.value, 9999, "Newest entry should survive resize")
	ScaleHelper.setup_timeline_cap(_chronicle, 20000)
	_chronicle.set_fact("resize.after", true)
	assert_fact("resize.after", true)


# Binary search (bisect) accuracy at cap with wrapped buffer
func test_bisect_accuracy_at_cap() -> void:
	var cap := 10000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	for i in cap:
		set_time(float(i) * 0.1)
		_chronicle.set_fact("bisect.k_%d" % (i % 100), i)
	var mid_time := float(cap / 2) * 0.1
	var changes = _chronicle.get_changes_since(mid_time)
	assert_gt(changes.size(), 0, "changes_since(mid) should return the second half")
	for entry in changes:
		assert_gte(entry.time, mid_time, "Entry at t=%.2f should be >= %.2f" % [entry.time, mid_time])
	var between = _chronicle.get_changes_between(mid_time, mid_time + 100.0)
	for entry in between:
		assert_between(entry.time, mid_time - 0.001, mid_time + 100.001,
			"Entry time %.4f should be in range [%.2f, %.2f]" % [entry.time, mid_time, mid_time + 100.0])


# Raw append throughput at 100k entries
func test_append_throughput() -> void:
	var cap := 100000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	var elapsed_ms := ScaleHelper.time_callable(func() -> void:
		for i in cap:
			_chronicle.set_fact("throughput.k_%d" % (i % 500), i)
	) / 1000.0
	assert_fact_count("*", 500)
	gut.p("100k timeline appends: %.1f ms (%.1f us/append)" % [elapsed_ms, elapsed_ms * 1000.0 / cap])


# Truncate correctness on wrapped buffer
func test_truncate_at_scale() -> void:
	var cap := 10000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	for i in cap:
		set_time(float(i) * 0.01)
		_chronicle.set_fact("trunc.k_%d" % (i % 100), i)
	var mid_time := float(cap / 2) * 0.01
	var result = _chronicle.rollback_to(mid_time)
	assert_rollback_ok(result)
	var after = _chronicle.get_changes_since(mid_time + 0.001)
	assert_eq(after.size(), 0, "No entries should exist after rollback point")
