extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")
const FrameSimulator := preload("res://test/production/support/frame_simulator.gd")


# 50 serialize/deserialize autosave cycles preserve the fact count.
func test_50_autosave_cycles() -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, 5000)
	for i in 200:
		_chronicle.watch("mixed_%d.*" % (i % 100), func(_k, _v, _o): pass)
	var cycle_times: Array[float] = []
	for cycle in 50:
		for i in 200:
			_chronicle.set_fact("mixed_%d.fact" % (i + cycle * 200 % 5000), cycle)
		var elapsed_ms := ScaleHelper.time_callable(func() -> void:
			_chronicle.deserialize(_chronicle.serialize())
		) / 1000.0
		cycle_times.append(elapsed_ms)
	gut.p("Autosave cycle times: first=%.1f ms, last=%.1f ms" % [cycle_times[0], cycle_times[-1]])
	assert_fact_count("*", 5000)


# Saving a continuously growing state reaches the expected total fact count.
func test_growing_state_save() -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, 1000)
	for cycle in 50:
		for i in 500:
			_chronicle.set_fact("growth_%d.v_%d" % [cycle, i], cycle * 500 + i)
		var elapsed_ms := ScaleHelper.time_callable(func() -> void:
			_chronicle.serialize()
		) / 1000.0
		if cycle % 10 == 0:
			gut.p("Cycle %d: %d facts, serialize %.1f ms" % [cycle, _chronicle.count_facts("*"), elapsed_ms])
	assert_fact_count("*", 1000 + 50 * 500)


# Repeated overwrite cycles keep the serialized save size stable.
func test_save_file_size_stability() -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, 5000)
	var baseline_data = _chronicle.serialize()
	var baseline_size := JSON.stringify(baseline_data).length()
	for cycle in 50:
		for i in 200:
			_chronicle.set_fact("mixed_%d.fact" % (i % 5000), cycle)
		var data = _chronicle.serialize()
		var size := JSON.stringify(data).length()
		if cycle == 49:
			var ratio := float(size) / float(baseline_size)
			gut.p("Size ratio after 50 overwrite cycles: %.2f" % ratio)
			assert_lt(ratio, 1.10, "File size should not grow more than 10%% from overwrites")


# Saves during expiry churn exclude transient facts and keep persistent ones.
func test_save_during_expiry_churn() -> void:
	for i in 1000:
		_chronicle.set_fact("persist.key_%d" % i, i)
	set_time(0.0)
	for cycle in 50:
		for i in 500:
			_chronicle.set_fact("temp.val_%d" % i, cycle, false, 2.0)
		var data = _chronicle.serialize()
		assert_does_not_have(data.facts, "temp.val_0", "Transient facts should not be in save (cycle %d)" % cycle)
		assert_has(data.facts, "persist.key_0", "Persistent facts should be in save")
		advance_time(2.5)
		_chronicle.flush_expiry()


# Watchers keep firing through repeated deserialize cycles.
func test_deserialize_watcher_survival() -> void:
	for i in 100:
		_chronicle.set_fact("surv.key_%d" % i, i)
	var events := watch_events("surv.*")
	_chronicle.set_fact("surv.key_0", 999)
	# A single write to one watched key fires the watcher exactly once.
	events.assert_count(1)
	for cycle in 20:
		var data = _chronicle.serialize()
		_chronicle.deserialize(data)
		events.clear()
		_chronicle.set_fact("surv.key_0", cycle)
		events.assert_count(1)
