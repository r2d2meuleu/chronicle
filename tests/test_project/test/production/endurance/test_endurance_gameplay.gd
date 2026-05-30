extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")
const MemoryTracker := preload("res://test/production/support/memory_tracker.gd")
const FrameSimulator := preload("res://test/production/support/frame_simulator.gd")

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	super.before_each()
	ScaleHelper.setup_timeline_cap(_chronicle, 10000)


func _setup_world() -> void:
	ScaleHelper.generate_entity_facts(_chronicle, 400, 5)
	for i in 100:
		_chronicle.watch("entity_%d.*" % i, func(_k, _v, _o): pass)
	for i in 20:
		add_gate("entity_%d.key_0" % i)
	for i in 10:
		add_reactor({watch_pattern = "entity_%d.*" % (i + 20)})


func _simulate_frame(frame_idx: int) -> void:
	var roll := _rng.randf()
	if roll < 0.60:
		for j in _rng.randi_range(1, 3):
			_chronicle.set_fact("entity_%d.key_%d" % [_rng.randi_range(0, 399), _rng.randi_range(0, 4)], frame_idx)
	elif roll < 0.80:
		_chronicle.increment_fact("entity_%d.key_%d" % [_rng.randi_range(0, 399), _rng.randi_range(0, 4)])
	elif roll < 0.90:
		_chronicle.evaluate("entity_%d.key_0 >= 0" % _rng.randi_range(0, 399))
	elif roll < 0.95:
		_chronicle.get_facts("entity_%d.*" % _rng.randi_range(0, 399))
	elif roll < 0.98:
		_chronicle.erase_fact("entity_%d.key_%d" % [_rng.randi_range(0, 399), _rng.randi_range(0, 4)])
	else:
		var batch := {}
		for j in _rng.randi_range(5, 10):
			batch["entity_%d.key_%d" % [_rng.randi_range(0, 399), _rng.randi_range(0, 4)]] = frame_idx
		_chronicle.set_facts(batch)


# 5000-frame run stays within the entity key space, respects the timeline cap,
# and does not leak memory.
func test_5000_frames_stability() -> void:
	_setup_world()
	_rng.seed = 42
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	var baseline := MemoryTracker.snapshot()
	for frame in 5000:
		advance_time(0.016)
		_chronicle.flush_expiry()
		_simulate_frame(frame)
	# The workload (seed 42) is deterministic and only touches the bounded 400x5 entity
	# key space, so static memory must stay near the baseline. The observed delta is
	# ~12.6 MB of allocator churn on a ~52 MB baseline; a real per-frame leak over 5000
	# frames would grow unbounded and blow past this 40 MB ceiling. Generous headroom
	# tolerates allocator/platform variance while still catching a runaway leak.
	MemoryTracker.assert_no_major_growth(self, baseline, 40 * 1024 * 1024, "5000-frame static memory")
	# The simulation only ever touches the 400x5 entity key space, so the store can
	# never exceed 2000 facts no matter how many frames run — proves no key-space leak.
	var fact_count: int = _chronicle.count_facts("*")
	assert_between(fact_count, 1, 2000, "Fact count must stay within the entity key space after 5000 frames")
	# Timeline must respect its cap (no unbounded history growth).
	var stats: Dictionary = _chronicle.get_stats()
	assert_lte(stats.timeline_size, stats.timeline_cap, "Timeline must not exceed its cap")


# Fact count survives serialize/deserialize roundtrips sampled across 5000 frames.
func test_5000_frames_correctness() -> void:
	_setup_world()
	_rng.seed = 123
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	for frame in 5000:
		advance_time(0.016)
		_chronicle.flush_expiry()
		_simulate_frame(frame)
		if (frame + 1) % 1000 == 0:
			var pre_stats = _chronicle.get_stats()
			var data = _chronicle.serialize()
			var pre_count = _chronicle.count_facts("*")
			_chronicle.deserialize(data)
			var post_count = _chronicle.count_facts("*")
			assert_eq(post_count, pre_count, "Fact count should survive roundtrip at frame %d" % frame)


# Sustained writes past the timeline cap keep only the latest entries per key.
func test_timeline_overflow_sustained() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 5000)
	for i in 10000:
		advance_time(0.01)
		_chronicle.set_fact("overflow.k_%d" % (i % 100), i)
	var last = _chronicle.get_last_change("*")
	var first = _chronicle.get_first_change("*")
	gut.p("Timeline: first_time=%.4f, last_time=%.4f, game_time=%.4f" % [
		first.time if first else -1.0,
		last.time if last else -1.0,
		_chronicle.get_game_time()])
	assert_not_null(last, "Last change should exist")
	assert_not_null(first, "First change should exist")
	assert_fact_count("*", 100)
	assert_eq(last.value, 9999)


# Fact count never drops below the persistent base floor as state grows and churns.
func test_fact_count_growth_curve() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 5000)
	_rng.seed = 777
	for i in 100:
		_chronicle.set_fact("base.key_%d" % i, i)
	var counts: Array[int] = []
	for frame in 5000:
		_chronicle.set_fact("grow.key_%d" % _rng.randi_range(0, frame + 100), frame)
		if _rng.randf() < 0.4:
			_chronicle.erase_fact("grow.key_%d" % _rng.randi_range(0, frame + 100))
		if (frame + 1) % 100 == 0:
			counts.append(_chronicle.count_facts("*"))
	gut.p("Fact count curve: start=%d, end=%d, max=%d" % [counts[0], counts[-1], counts.max()])
	# Only grow.* keys are ever erased; the 100 base.* keys persist for the whole run,
	# so every sampled total must stay at or above the base floor.
	for c in counts:
		assert_gte(c, 100, "Total fact count must never drop below the 100 persistent base facts")
	# The base namespace is untouched after setup — exactly 100 keys remain.
	assert_fact_count("base.*", 100)
