extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")
const MemoryTracker := preload("res://test/production/support/memory_tracker.gd")


# Full roundtrip at 1k — baseline correctness
func test_roundtrip_1k() -> void:
	_run_roundtrip(1000)


# Full roundtrip at 10k — type preservation
func test_roundtrip_10k() -> void:
	_run_roundtrip(10000)


# Full roundtrip at 50k — enterprise save/load
func test_roundtrip_50k() -> void:
	_run_roundtrip(50000)


func _run_roundtrip(count: int) -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, count)
	var snapshot := {}
	for key in _chronicle.get_fact_keys("*"):
		snapshot[key] = _chronicle.get_fact(key)
	var data = _chronicle.serialize()
	_chronicle.clear()
	assert_fact_count("*", 0)
	var ok = _chronicle.deserialize(data)
	assert_true(ok, "Deserialize should succeed")
	assert_fact_count("*", count)
	for key in snapshot:
		var restored = _chronicle.get_fact(key)
		assert_eq(typeof(restored), typeof(snapshot[key]),
			"Type mismatch for %s: expected %d got %d" % [key, typeof(snapshot[key]), typeof(restored)])
		assert_eq(restored, snapshot[key], "Value mismatch for %s" % key)


# Serialize timing across scale tiers
func test_serialize_timing() -> void:
	for tier_info in [{n=1000, label="1K"}, {n=10000, label="10K"}, {n=50000, label="50K"}]:
		_chronicle.clear()
		ScaleHelper.generate_mixed_type_facts(_chronicle, tier_info.n)
		var out := [{}]
		var elapsed_ms := ScaleHelper.time_callable(func() -> void:
			out[0] = _chronicle.serialize()
		) / 1000.0
		var data: Dictionary = out[0]
		gut.p("Serialize %s facts: %.1f ms" % [tier_info.label, elapsed_ms])
		# Correctness: every non-transient fact must appear in the serialized output.
		assert_eq(data.facts.size(), tier_info.n,
			"Serialize %s should emit all facts (got %d, expected %d)" % [tier_info.label, data.facts.size(), tier_info.n])


# Deserialize timing across scale tiers
func test_deserialize_timing() -> void:
	for tier_info in [{n=1000, label="1K"}, {n=10000, label="10K"}, {n=50000, label="50K"}]:
		_chronicle.clear()
		ScaleHelper.generate_mixed_type_facts(_chronicle, tier_info.n)
		var data = _chronicle.serialize()
		_chronicle.clear()
		var elapsed_ms := ScaleHelper.time_callable(func() -> void:
			_chronicle.deserialize(data)
		) / 1000.0
		gut.p("Deserialize %s facts: %.1f ms" % [tier_info.label, elapsed_ms])
		# Correctness: restored state must match what was serialized.
		assert_fact_count("*", tier_info.n)
		# Spot-check deterministic facts (see ScaleHelper.generate_mixed_type_facts: i % 6).
		assert_fact("mixed_1.fact", 1)            # i % 6 == 1 -> int
		assert_fact("mixed_3.fact", "val_3")      # i % 6 == 3 -> String
		assert_fact("mixed_4.fact", [4, 5, 6])    # i % 6 == 4 -> Array


# Nested Godot types (Vector2, Color) in nested dicts survive roundtrip
func test_nested_godot_types() -> void:
	for i in 1000:
		_chronicle.set_fact("typed_%d.data" % i, {
			"pos": Vector2(float(i), float(i) * 2.0),
			"color": Color(float(i) / 1000.0, 0.5, 0.5),
			"nested": {"inner_pos": Vector3(1.0, 2.0, 3.0)}
		})
	roundtrip()
	for i in [0, 499, 999]:
		var d: Dictionary = _chronicle.get_fact("typed_%d.data" % i)
		assert_eq(typeof(d.pos), TYPE_VECTOR2, "Vector2 type preserved for entry %d" % i)
		assert_eq(d.pos, Vector2(float(i), float(i) * 2.0))
		assert_eq(typeof(d.color), TYPE_COLOR, "Color type preserved for entry %d" % i)
		assert_eq(typeof(d.nested.inner_pos), TYPE_VECTOR3)


# Serialize timeline cap interaction — only 1000 entries in output
func test_timeline_cap_interaction() -> void:
	ScaleHelper.setup_timeline_cap(_chronicle, 50000)
	for i in 50000:
		set_time(float(i) * 0.001)
		_chronicle.set_fact("tcap.k_%d" % (i % 100), i)
	var data = _chronicle.serialize()
	assert_has(data, "timeline")
	assert_lte(data.timeline.size(), 1000, "Serialize cap should limit to 1000 entries (got %d)" % data.timeline.size())


# File size measurement at each tier
func test_file_size_measurement() -> void:
	for tier_info in [{n=1000, label="1K"}, {n=10000, label="10K"}, {n=50000, label="50K"}]:
		_chronicle.clear()
		ScaleHelper.generate_mixed_type_facts(_chronicle, tier_info.n)
		var path = "user://test_size_%s.json" % tier_info.label
		var err = _chronicle.save_file(path)
		assert_eq(err, OK, "Save should succeed for %s" % tier_info.label)
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var size_bytes := file.get_length()
			file.close()
			gut.p("File size at %s facts: %s" % [tier_info.label, MemoryTracker.format_bytes(size_bytes)])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))


# Partial corruption — exactly the 100 corrupted facts (every 10th) are dropped
func test_deserialize_partial_corruption() -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, 1000)
	var data = _chronicle.serialize()
	var corrupt_count := 0
	var keys_array = data.facts.keys()
	for i in range(0, keys_array.size(), 10):
		# Non-String dict key is rejected by is_valid_type() — same "invalid type, dropped"
		# corruption path as a Node, without leaking an Object.
		data.facts[keys_array[i]] = {1: "corrupt"}
		corrupt_count += 1
	_chronicle.clear()
	_chronicle.deserialize(data)
	var restored = _chronicle.count_facts("*")
	# Every 10th of the 1000 facts is corrupted (100 total) and reliably dropped, so
	# the survivor count is exactly 900 — deterministic, not a loose lower bound.
	assert_eq(restored, 900, "Exactly the 100 corrupted facts should drop (got %d)" % restored)


# 50 save/load cycles — no drift
func test_repeated_roundtrip() -> void:
	ScaleHelper.generate_mixed_type_facts(_chronicle, 10000)
	var original_keys = _chronicle.get_fact_keys("*")
	original_keys.sort()
	for cycle in 50:
		roundtrip()
	var final_keys = _chronicle.get_fact_keys("*")
	final_keys.sort()
	assert_eq(final_keys.size(), original_keys.size(), "Key count should not drift after 50 cycles")
	for i in original_keys.size():
		assert_eq(final_keys[i], original_keys[i])
