extends ChronicleTestSuite

const ScaleHelper := preload("res://test/production/support/scale_helper.gd")


# Cache warmup — first write vs second write timing for 2048 keys
func test_cache_warmup_cost() -> void:
	var keys: Array[String] = []
	for i in 2048:
		keys.append("warmup_%d.key" % i)
	var first_us := ScaleHelper.time_callable(func() -> void:
		for key in keys:
			_chronicle.set_fact(key, true)
	)
	for key in keys:
		_chronicle.erase_fact(key)
	var second_us := ScaleHelper.time_callable(func() -> void:
		for key in keys:
			_chronicle.set_fact(key, true)
	)
	gut.p("First write (cold cache): %.0f us, Second write (warm cache): %.0f us" % [first_us, second_us])
	assert_fact_count("*", 2048)


# Cache thrashing — 5000 keys exceed 2048 cache, re-read forces re-validation
func test_cache_thrashing() -> void:
	for i in 5000:
		_chronicle.set_fact("thrash_%d.v" % i, i)
	assert_fact_count("*", 5000)
	for i in 2048:
		var val = _chronicle.get_fact("thrash_%d.v" % i)
		assert_eq(val, i, "Re-read after cache eviction should return correct value")


# Denormalize call frequency — substr allocation on every read
func test_denormalize_call_frequency() -> void:
	for i in 10000:
		_chronicle.set_fact("denorm_%d.val" % i, i)
	var mismatches := [0]
	var elapsed_us := ScaleHelper.time_callable(func() -> void:
		for i in 10000:
			var val = _chronicle.get_fact("denorm_%d.val" % i)
			if val != i:
				mismatches[0] += 1
	)
	gut.p("10k reads: %.0f us (%.1f us/read)" % [elapsed_us, elapsed_us / 10000.0])
	# Correctness: every denormalized key must resolve back to its stored value.
	assert_eq(mismatches[0], 0, "All 10k reads should return the correct value")
	assert_fact_count("*", 10000)
	# Spot-check the denormalize round-trip on boundary keys.
	assert_fact("denorm_0.val", 0)
	assert_fact("denorm_9999.val", 9999)
