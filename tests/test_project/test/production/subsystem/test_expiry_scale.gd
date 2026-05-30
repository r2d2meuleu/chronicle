extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")
const FrameSimulator := preload("res://test/production/support/frame_simulator.gd")


# 1k concurrent expiry timers — all expire correctly
func test_concurrent_expiry_1k() -> void:
	_run_concurrent_expiry(1000)


# 10k concurrent expiry timers — scaling wall
func test_concurrent_expiry_10k() -> void:
	_run_concurrent_expiry(10000)


func _run_concurrent_expiry(count: int) -> void:
	set_time(0.0)
	for i in count:
		var lifetime := 1.0 + float(i) * 0.01
		_chronicle.set_fact("expiry_%d.timer" % i, i, false, lifetime)
	assert_fact_count("*", count)
	var max_time := 1.0 + float(count) * 0.01 + 1.0
	FrameSimulator.simulate_seconds(_chronicle, max_time + 1.0, 60.0)
	assert_fact_count("*", 0)


# Min-expiry guard short-circuits when no expiry is due
func test_min_expiry_guard_effectiveness() -> void:
	set_time(0.0)
	for i in 10000:
		_chronicle.set_fact("guard_%d.timer" % i, i, false, 100.0)
	var elapsed_us := ScaleHelper.time_callable(func() -> void:
		for frame in 100:
			_chronicle.flush_expiry()
	)
	var per_frame_us := elapsed_us / 100.0
	gut.p("10k timers, no expiry due: %.1f us/frame" % per_frame_us)
	assert_fact_count("*", 10000)


# Burst: 5k facts all expire at the same instant
func test_expiry_burst() -> void:
	set_time(0.0)
	var expired_events := collect_signal(_chronicle, "fact_expired")
	for i in 5000:
		_chronicle.set_fact("burst_%d.v" % i, i, false, 5.0)
	assert_fact_count("*", 5000)
	set_time(4.99)
	_chronicle.flush_expiry()
	assert_fact_count("*", 5000)
	set_time(5.01)
	_chronicle.flush_expiry()
	assert_fact_count("*", 0)
	expired_events.assert_count(5000)


# Expiry-triggered watcher dispatch with correct EraseSource
func test_expiry_with_active_watchers() -> void:
	set_time(0.0)
	var events := watch_events("watched.*")
	for i in 1000:
		_chronicle.set_fact("watched.timer_%d" % i, i, false, 2.0)
	events.clear()
	set_time(2.01)
	_chronicle.flush_expiry()
	assert_fact_count("watched.*", 0)
	events.assert_count(1000)
	for i in mini(10, events.count()):
		assert_null(events.events[i].value, "Expired value should be null")


# Interleaved expiry and writes — min_dirty correctness
func test_expiry_interleaved_with_writes() -> void:
	set_time(0.0)
	for round_idx in 10:
		for i in 100:
			var key := "interleave_%d_%d.v" % [round_idx, i]
			_chronicle.set_fact(key, i, false, 1.0 + float(round_idx))
		advance_time(1.0)
		_chronicle.flush_expiry()
	advance_time(20.0)
	_chronicle.flush_expiry()
	assert_fact_count("*", 0)
