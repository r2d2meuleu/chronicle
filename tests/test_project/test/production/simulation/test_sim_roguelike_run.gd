extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")
const FrameSimulator := preload("res://test/production/support/frame_simulator.gd")


func _setup_meta() -> void:
	for i in 30:
		_chronicle.set_fact("meta.unlock_%d" % i, i < 5)


func _start_run() -> void:
	for i in 200:
		_chronicle.set_fact("run.room_%d" % (i % 50), "empty", true, 0.0)
	_chronicle.set_fact("run.floor", 1, true, 0.0)
	_chronicle.set_fact("run.gold", 0, true, 0.0)


# A full 50-room run accumulates the expected gold total.
func test_run_lifecycle() -> void:
	_setup_meta()
	_start_run()
	for room in 50:
		set_time(float(room))
		for i in range(room * 4, room * 4 + 4):
			_chronicle.set_fact("run.room_%d" % (i % 50), "active", true, 0.0)
		_chronicle.increment_fact("run.gold", 10)
		for i in range(room * 4, room * 4 + 2):
			_chronicle.erase_fact("run.room_%d" % (i % 50))
	assert_fact("run.gold", 500)


# 50 staggered buffs each fire fact_expired as their lifetimes elapse.
func test_buff_expiry_cascade() -> void:
	_setup_meta()
	set_time(0.0)
	var expired := collect_signal(_chronicle, "fact_expired")
	for i in 50:
		_chronicle.set_fact("buff.effect_%d" % i, 1.0 + float(i) * 0.1, false, float(i) + 1.0)
	FrameSimulator.simulate_seconds(_chronicle, 55.0, 60.0)
	assert_eq(expired.count(), 50, "All 50 buffs should expire")


# Rolling back on death restores the room state to the target time.
func test_death_rollback() -> void:
	_setup_meta()
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	set_time(0.0)
	for room in 10:
		set_time(float(room) + 1.0)
		_chronicle.set_fact("run.room_state", room)
	assert_fact("run.room_state", 9)
	_chronicle.rollback_to(6.0)
	assert_fact("run.room_state", 5)


# Transient run facts are excluded from saves while persistent meta facts remain.
func test_transient_persistence_boundary() -> void:
	_setup_meta()
	_chronicle.set_fact("run.transient_val", 42, true, 0.0)
	_chronicle.set_fact("meta.persistent_val", 99)
	var data = _chronicle.serialize()
	assert_does_not_have(data.facts, "run.transient_val", "Transient should be excluded from save")
	assert_has(data.facts, "meta.persistent_val", "Persistent should be in save")


# Run-over-run, transient run state is cleared while meta progress accumulates.
func test_run_over_run_accumulation() -> void:
	_setup_meta()
	for run_idx in 10:
		_start_run()
		for room in 20:
			_chronicle.set_fact("run.floor", room, true, 0.0)
		_chronicle.set_fact("meta.runs_completed", run_idx + 1)
		var keys = _chronicle.get_fact_keys("run.*")
		for key in keys:
			_chronicle.erase_fact(key)
	assert_fact("meta.runs_completed", 10)
	assert_fact_count("run.*", 0)


# Rollback undoes facts written after the target time, restoring the anchor.
func test_expiry_during_rollback() -> void:
	_setup_meta()
	ScaleHelper.setup_timeline_cap(_chronicle, 10000)
	set_time(0.0)
	_chronicle.set_fact("test.anchor", "before")
	set_time(1.0)
	for i in 10:
		_chronicle.set_fact("buff.rb_%d" % i, true)
	set_time(2.0)
	_chronicle.rollback_to(0.5)
	assert_fact("test.anchor", "before")
	for i in 10:
		assert_no_fact("buff.rb_%d" % i)
