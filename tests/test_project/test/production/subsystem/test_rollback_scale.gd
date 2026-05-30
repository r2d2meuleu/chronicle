extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# Rollback to origin at 1k facts
func test_rollback_to_origin_1k() -> void:
	_run_rollback_to_origin(1000)


# Rollback to origin at 10k facts
func test_rollback_to_origin_10k() -> void:
	_run_rollback_to_origin(10000)


func _run_rollback_to_origin(count: int) -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, count + 1000)
	set_time(0.0)
	_chronicle.set_fact("anchor.val", "start")
	for i in count:
		set_time(float(i + 1) * 0.01)
		_chronicle.set_fact("rb_%d.v" % (i % 200), i)
	var result = _chronicle.rollback_to(0.005)
	assert_rollback_ok(result)
	assert_fact("anchor.val", "start")


# rollback_steps over full timeline
func test_rollback_steps_full_timeline() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 5000)
	set_time(0.0)
	for i in 1000:
		set_time(float(i) * 0.01)
		_chronicle.set_fact("steps.k_%d" % i, i)
	var result = _chronicle.rollback_steps(1000)
	assert_rollback_ok(result)
	assert_eq(result.steps_reverted, 1000)


# Rollback with 500 active watchers — all fire correctly
func test_rollback_with_watchers() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 20000)
	set_time(0.0)
	_chronicle.set_fact("watched.base", 0)
	var events := watch_events("watched.*")
	for i in 500:
		_chronicle.watch("rb_watched_%d.*" % i, func(_k, _v, _o): pass)
	set_time(1.0)
	for i in 10000:
		_chronicle.set_fact("watched.k_%d" % (i % 100), i)
	events.clear()
	var result = _chronicle.rollback_to(0.5)
	assert_rollback_ok(result)
	# The 10000 writes hit 100 distinct keys (watched.k_0..k_99), all created at
	# time 1.0; rollback to 0.5 erases all 100, firing one net change each.
	# watched.base was set at time 0.0 so it survives and does not fire.
	events.assert_count(100)


# Rollback near timeline edge — earliest surviving entry boundary
func test_rollback_near_timeline_edge() -> void:
	var cap := 5000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	for i in cap:
		set_time(float(i) * 0.01)
		_chronicle.set_fact("edge.k_%d" % (i % 100), i)
	var first = _chronicle.get_first_change("*")
	assert_not_null(first)
	var result = _chronicle.rollback_to(first.time + 0.001)
	assert_rollback_ok(result)


# Rollback beyond retained window fails gracefully
func test_rollback_beyond_timeline() -> void:
	var cap := 1000
	ScaleHelper.setup_timeline_cap(_chronicle, cap)
	for i in cap + 500:
		set_time(float(i) * 0.01)
		_chronicle.set_fact("beyond.k_%d" % (i % 50), i)
	var result = _chronicle.rollback_to(0.001)
	assert_rollback_ok(result)


# Three sequential rollbacks — timeline truncation accumulation
func test_repeated_rollbacks() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 10000)
	set_time(1.0)
	_chronicle.set_fact("seq.a", 1)
	set_time(2.0)
	_chronicle.set_fact("seq.b", 2)
	set_time(3.0)
	_chronicle.set_fact("seq.c", 3)
	set_time(4.0)
	_chronicle.set_fact("seq.d", 4)
	set_time(5.0)
	_chronicle.set_fact("seq.e", 5)
	_chronicle.rollback_to(4.0)
	assert_no_fact("seq.e")
	assert_fact("seq.d", 4)
	_chronicle.rollback_to(3.0)
	assert_no_fact("seq.d")
	assert_fact("seq.c", 3)
	_chronicle.rollback_to(2.0)
	assert_no_fact("seq.c")
	assert_fact("seq.b", 2)
	assert_fact("seq.a", 1)
